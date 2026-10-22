---
"better-supabase": minor
---

Breaking: the runtime instance is `bsb`, matching the CLI's short name, so `const db = await bsb.db()` replaces `bs.db()` in the docs, skills, examples, generated files and the `ctx.bsb` key on request contexts (`c.var.bsb`, `locals.bsb`, `context.bsb`). Run `better-supabase codemod 0.15` to rename the instance where a file creates, imports or destructures it; it lists cache tags and query keys that start with `bs` for review.

Strings on the wire move with it, so deploy the new package and run `better-supabase sql upgrade` together: realtime topics start with `bsb:t:`, the request and job headers are `x-bsb-actor`, `x-bsb-job` and `x-bsb-signature`, workflow run attributes are `bsb.*`, the debug header is `x-bsb-db-calls`, the stats route is `/api/bsb-stats`, and Server-Timing names are `bsb-proxy` and `bsb-verify`. Workflow runs started before the upgrade keep their `bs.*` attributes, so failure alerts don't count them. The support session cookie is `bsb-support` and the replica cookie is `bsb-primary-until`, so staff in a support session start it again after the deploy.

Stored names keep `bs`, because renaming them would orphan existing data: Vault secret names (`bs:field-key:`, `bs:cred:`, `bs:signing:`, `bs:marketplace:`), the queue envelope key `$bs` and the API key prefix `bs`, which existing keys are verified against.
