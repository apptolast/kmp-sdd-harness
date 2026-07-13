---
name: cloud-functions-counters
description: Úsala al tocar los contadores de votos/reportes de la flota KMP de AppToLast (Firestore + Cloud Functions Gen2). Cuando implementes upvote/downvote, el auto-ocultar contenido por reportes, o el custom claim admin; cuando el cliente escriba en `votos/`/`reportes/` y necesites que un trigger recalcule los contadores; o cuando despliegues las functions a los entornos `debug` y `(default)`. Define el patrón canónico: CF como fuente de verdad de los contadores + UI optimista en el cliente (REST, sin listeners).
version: 0.1.0
---

# Receta: contadores de votos/reportes con Cloud Functions (Gen2)

Patrón **canónico** para mantener contadores agregados en Firestore desde triggers Gen2 (Eventarc), sustituyendo los triggers de PostgreSQL del backend Rust retirado. Fuente: inemsellar `functions/index.js`, `firebase.json`, `functions/package.json`.

## Cuándo usarla
- Al implementar upvote/downvote sobre `ofertas`/`consejos`/`cursos` (contadores `upvotes`/`downvotes`).
- Al implementar el reporte de contenido con **auto-ocultar** al superar un umbral configurable.
- Al gestionar el custom claim `admin` (allowlist de emails) que leen las reglas de Firestore.
- Al desplegar/actualizar las functions para los dos entornos (`debug` + `(default)`).

## Modelo de datos (el cliente escribe, la CF agrega)
- **Voto**: subcolección por usuario `‹coleccion›/{contentId}/votos/{voterId}`, doc con `tipoVoto` (`1` = upvote, `-1` = downvote). Un doc por votante ⇒ idempotente.
- **Reporte**: doc plano `reportes/{reportId}` (convención `{tipo}_{id}_{uid}`) con `tipoContenido` (`oferta`/`consejo`/`curso`) e `idContenido`.
- **Contadores** viven en el doc de contenido: `upvotes`, `downvotes`, `reportes`, `activo`, `estadoModeracion`. **El cliente NO los escribe**; son propiedad de la CF (fuente de verdad).

## Cómo se hace

### 1. Trigger de votos — `onDocumentWritten` sobre la subcolección
Calcula el delta antes→después para soportar crear, cambiar y borrar el voto en un único trigger:

```javascript
function voteDelta(before, after) {
  const b = before?.tipoVoto ?? 0;
  const a = after?.tipoVoto ?? 0;
  const up = (a === 1 ? 1 : 0) - (b === 1 ? 1 : 0);
  const down = (a === -1 ? 1 : 0) - (b === -1 ? 1 : 0);
  return { up, down };
}

function makeVoteCounter(collection, database) {
  const dbi = database ? getFirestore(database) : db;
  const path = `${collection}/{contentId}/votos/{voterId}`;
  return onDocumentWritten(database ? { document: path, database } : path, async (event) => {
    const { up, down } = voteDelta(event.data?.before?.data(), event.data?.after?.data());
    if (up === 0 && down === 0) return;
    const ref = dbi.collection(collection).doc(event.params.contentId);
    await ref.update({
      upvotes: FieldValue.increment(up),
      downvotes: FieldValue.increment(down),
    }).catch((e) => {
      // Contenido borrado (NOT_FOUND, code 5) es benigno; CUALQUIER otro error debe ser VISIBLE.
      if (e?.code === 5 || /NOT_FOUND/i.test(String(e?.message))) return;
      logger.error("voteCounter: fallo al actualizar contadores", { collection, contentId: event.params.contentId, error: String(e) });
    });
  });
}
```

### 2. Trigger de reportes — `onDocumentCreated` + transacción + auto-ocultar
El umbral se lee de `configuracion/umbral_reportes_ocultar` (default 5). La transacción evita carreras entre reportes concurrentes:

```javascript
function makeReportCounter(database) {
  const dbi = database ? getFirestore(database) : db;
  return onDocumentCreated(database ? { document: "reportes/{reportId}", database } : "reportes/{reportId}", async (event) => {
    const r = event.data?.data();
    const collection = TIPO_TO_COLLECTION[r?.tipoContenido]; // { oferta:"ofertas", consejo:"consejos", curso:"cursos" }
    if (!collection || !r.idContenido) return;
    const ref = dbi.collection(collection).doc(r.idContenido);

    const cfg = await dbi.collection("configuracion").doc("umbral_reportes_ocultar").get();
    const umbral = Number.parseInt(cfg.exists ? cfg.data().valor ?? "5" : "5", 10) || 5;

    await dbi.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return;
      const nuevos = (snap.data().reportes ?? 0) + 1;
      const patch = { reportes: nuevos };
      if (nuevos >= umbral) { patch.activo = false; patch.estadoModeracion = "en_revision"; }
      tx.update(ref, patch);
    });
  });
}
```

### 3. Doble entorno: una función por colección × base
Se exporta una variante por defecto (base `(default)`, release) y una `*Debug` (base `debug`). Coexisten; cada build de la app escribe en la base de su `APP_ENV` y dispara solo su trigger:

```javascript
export const consejosVoteCounter = makeVoteCounter("consejos");
export const consejosVoteCounterDebug = makeVoteCounter("consejos", "debug");
export const onReportCreate = makeReportCounter();
export const onReportCreateDebug = makeReportCounter("debug");
```

### 4. Custom claim admin (blocking functions — NO desplegar por defecto)
`beforeUserCreated`/`beforeUserSignedIn` fijan `{ admin: true|false }` según la allowlist `ADMIN_EMAILS` (functions param). Interceptan TODOS los sign-in ⇒ no van en el deploy normal; el claim se otorga con `scripts/admin/grant-admin.mjs`.

### 5. Cliente KMP: UI optimista, sin listeners
El acceso a datos es **REST-sobre-Ktor** (`FirestoreClient`), no el SDK ⇒ **no hay listeners** que reflejen los contadores automáticamente. Patrón (Option A): el cliente escribe su doc `votos/{uid}`, actualiza el contador **de forma optimista** en la UI, y trata la CF como fuente de verdad al refrescar. No escribir nunca `upvotes`/`downvotes` desde el cliente.

### 6. Deploy
Config: `setGlobalOptions({ region: "europe-west1", maxInstances: 10 })`, `engines.node: "20"`, `type: "module"` (ESM). `firebase.json` declara ambas bases (`(default)` + `debug`) y el codebase `functions`. Despliega solo los contadores (no las blocking-auth):

```bash
firebase deploy --project inemsellar-app --only \
  functions:consejosVoteCounter,functions:onReportCreate,functions:consejosVoteCounterDebug,functions:onReportCreateDebug
```

## Gotchas
- **No silencies el `catch`**: solo `NOT_FOUND` (code 5, contenido borrado) es benigno. Un catch mudo ocultó una vez la falta del rol `datastore.user`/permisos de escritura de la SA del trigger.
- **`getFirestore(database)` por base**: la variante sin sufijo usa `db` (default); la `*Debug` debe instanciar `getFirestore("debug")` **y** pasar `{ document, database }` al trigger; si olvidas el `database` en el objeto, el trigger se registra sobre `(default)`.
- **Reportes en transacción**: usa `runTransaction` (no `increment`) porque hay que leer el valor para comparar con el umbral y aplicar `activo=false` atómicamente.
- **Idempotencia de votos**: un doc por votante (`votos/{voterId}`) más `onDocumentWritten` con delta evita doble conteo al re-votar; no uses `onDocumentCreated` para votos (rompería el cambio up→down).
- **Blocking-auth no se despliega**: si la incluyes en el `--only`, interceptas todos los sign-ins. Deja `setAdminOnCreate/SignIn` fuera del deploy y usa el script de allowlist.
- **Un deploy cubre los dos entornos**: los triggers `*` y `*Debug` coexisten; no hace falta un deploy por base.

Fuente: `functions/index.js`, `functions/package.json`, `firebase.json` (proyecto inemsellar) · `.github/workflows/deploy-functions.yml`.
