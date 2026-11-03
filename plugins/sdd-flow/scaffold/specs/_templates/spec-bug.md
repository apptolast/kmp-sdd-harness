# Spec — <feature name>

- Slug: `<feature-slug>`
- Estado: `borrador` | `aprobado` | `en-curso` | `implementado` | `hecho` | `bloqueado`
- Ticket: `<TICKET-ID o n/a>`
- Tipo: bug
- Plataformas: <Android · iOS · Desktop · Web — dónde se reproduce>

Resumen: <una línea: qué está roto, para quién y cómo es estar arreglado>

## Comportamiento actual

<El defecto, como condición reproducible. Una línea por condición.>

- CUANDO <condición> ENTONCES <resultado incorrecto>

## Fuera de alcance

<Comportamiento que este arreglo deja a propósito como está.>

- <excluido>

## Criterios de aceptación

<Una lista numerada en dos grupos. `converge` valida ambos: el arreglo, y que nada de al lado se movió.>

### Esperado (el arreglo)

- [ ] AC1 CUANDO <condición> ENTONCES <resultado correcto>

### Sin cambios (debe seguir funcionando)

- [ ] AC2 CUANDO <condición vecina> ENTONCES <el resultado de hoy, sin cambios>

## Preguntas abiertas

- Q1 <pregunta> — recomendado: <respuesta>   (o "Ninguna")

---
Presupuesto: 60 líneas. La causa raíz y las opciones de arreglo van en `plan.md`; la investigación en
`journal.md`.
