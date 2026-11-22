---
"better-supabase": minor
---

A Supabase project on Vercel works without renamed variables.

- The CLI (`gen`, `db`, `doctor`) and the Workflow World read `POSTGRES_URL_NON_POOLING` and
  `POSTGRES_URL`, the names the Supabase integration syncs. The CLI prefers the direct string, the
  World the pooled one.
- `loadEnv` and `parseEnv` take `prefix` for an integration connected with a custom prefix (`DB1`
  reads `DB1_SUPABASE_URL`), and say when only the legacy `SUPABASE_ANON_KEY` or
  `SUPABASE_SERVICE_ROLE_KEY` name is set. New exports: `withEnvPrefix` and `projectRefOf`.
- New `better-supabase/vercel` entry: `deploymentUrl`, `protectionBypassHeaders`,
  `protectionBypassUrl`, `deploymentIssues` and `assertDeployment`. The bypass secret is only sent
  to the deployment's own hosts. The Workflow World adds the header to its flow route.
- `better-supabase doctor --vercel` reads `.vercel/.env.<name>.local` and reports BS513 (an
  environment lacks a Supabase variable), BS514 (a secret under a browser prefix) and BS515
  (preview and production on one Supabase project).
- New docs page: Deploy on Vercel.

Upgrade: nothing breaks. A CLI run that had `POSTGRES_URL` in its shell now connects with it when no
other connection string is set; pass `--db-url-stdin` or set `DATABASE_URL` to choose another.
