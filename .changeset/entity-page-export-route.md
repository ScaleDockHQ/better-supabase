---
"better-supabase": minor
---

`defineEntityPage` takes `export: { filename, columns, maxRows }`. `gen` then writes `GET /api/<name>/export`, which streams `exportResponse` over the entity's `page` under the list query's `q`, `sort` and filters, and lists the route as `export` in `pages/routes.manifest.ts` (`EntityRouteEntry.export` is optional). A page without `export` writes nothing new. The eight format-specific exports (payroll, OSCAL, SEPA, iCalendar, promptfoo, audit log, governance subject and data export) keep their own methods.
