---
"better-supabase": minor
---

`gen` writes a record feature per subject, so a record page needs no hand-written loader or actions.

- With a block that adds record sections installed, `gen` writes `features/<subject>/` next to the main module: the feature (`defineRecordFeature`), and for Next.js a server file (`recordServer`), one Server Action per section write and a client provider. With TanStack Query installed it also writes the record's query options. Set `generateFeatures: false` to turn it off. No UI is generated; the cards stay recipes.
- The share links, relations, versions and SLA blocks add sections (`shareLinks`, `relations`, `versions`, `sla`), and every section can declare its writes.
- `better-supabase/records` adds `defineRecordFeature`, `featureWrites` and `runSectionWrite`; `better-supabase/next` adds `recordServer`; `better-supabase/react` adds `createRecordProvider`; `better-supabase/query` adds `recordQueries` and `invalidateOnRecordEvents`.
