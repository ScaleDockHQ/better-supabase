# validation-centrakit

CentraKit's tenant, identity, platform and automation tables adopting the
better-supabase SaaS blocks, run against the local stack. The tests check
that the generated SQL works on a schema better-supabase didn't design, with
permissions owned by an authorization provider instead of the built-in
catalog.

Run it from this folder with the local stack up (`pnpm supabase:start` at the
root):

```sh
set -a && . ../../.env.development.local && set +a
pnpm test
pnpm sql:check
```

`pnpm sql:check` fails when the committed `supabase/schemas/900_*` files and
`supabase/better-supabase-data` drift from `better-supabase.config.ts`. Run
`better-supabase sql sync` and `better-supabase sql data` to regenerate them;
never edit them by hand. `src/sync-check.test.ts` runs the same check and
doctor against the live schema, and expects only the five BS314 warnings for
tables that carry user data without a lifecycle rule.

## The provider snapshot

`authorization-provider.json` is a frozen snapshot of the provider document
CentraKit's authorization library exports (`AuthorizationProvider`,
`apiVersion: 1`). `src/provider.ts` reads it, so the fixture needs no
dependency on that library. The functions its templates name are defined at
the end of `supabase/schemas/000_centrakit.sql`, with hard-coded role grants.

To refresh it, export the provider document from CentraKit, then sanitize it
before committing:

- Rename every function to `centrakit.authz_*` and keep the template
  placeholders (`{scope}`, `{user}`, `{permission}`, `{tenant}`, `{role}`).
- Remove the library's name, its key prefixes and its helper names. The
  repo check for invariant 15 in `AGENTS.md` fails on any of them.
- Keep `permissions` sorted, and update the functions in `000_centrakit.sql`
  when a key or a role grant changes.

CentraKit's permission catalog tables (`permissions`, `role_permissions` and
the per-organization overrides) are not in the fixture. The provider owns
those decisions, so the tests that used to edit overrides now check the
provider's answers through `can` and the invitation role checks instead.

The fixture keeps its name for history. `validation-adopt-provider` would
describe it better if it ever gains a second adopted schema.
