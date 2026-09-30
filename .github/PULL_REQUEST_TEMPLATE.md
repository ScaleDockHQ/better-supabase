## What

<!-- What changed and why, in a few sentences. -->

## Verify

<!-- How a reviewer can check it: commands, pages, or screenshots. -->

- [ ] `pnpm verify` passes
- [ ] `pnpm test:integration` passes, if this touches SQL, auth or adapters

## Checklist

- [ ] Schema: `supabase/` changes come with a migration and pgTAP tests
- [ ] Env: new keys are in the t3-env schema, `turbo.json`, `.env.example` and all three Vercel environments
- [ ] Changeset: user-visible changes have one (`pnpm changeset`)
- [ ] Public API changes update the docs page, the example and `api/exports.json`
- [ ] AGENTS.md "When you change X, also update Y" is followed
