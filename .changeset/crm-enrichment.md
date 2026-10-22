---
"better-supabase": minor
---

Add the `enrichment` block (`better-supabase/blocks/enrichment`). `createEnrichment({ transport, provider })` looks a parties company or person up and stores the profile per record and provider. A match fills the record's empty `domain` and `website`, or `phone` and `title`, and never overwrites a value. `enrichDue()` works through records with no result or a stale one from a cron, and every result writes `party.enriched`. `peopleDataLabsEnrichment({ apiKey })` calls People Data Labs over `fetch`; any other source plugs in as an `EnrichmentProvider` with `apiVersion: 1`. The block adds the `enrichment.read` and `enrichment.run` permissions.
