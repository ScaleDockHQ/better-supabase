---
name: better-supabase-testing
description: Test Supabase RLS policies, APIs and SQL against the local stack with better-supabase/testing, typed seeds and pgTAP. Use when writing or fixing tests that touch the database, policies or auth.
---

# Testing with better-supabase

Test against the local stack (`supabase start`) as real users. Don't mock
supabase-js, and don't use the service role for anything a user does.

## Workflow: test a table or policy

1. Start the stack (`supabase start`) and write `.env.local` with
   `better-supabase env`.
2. Add the rows the test needs to `supabase/seed.ts`, including one row
   owned by another tenant, then `supabase db reset`.
3. Write the RLS test with `asUser` for each role that matters.
4. Assert both directions: the user sees and changes their own rows, and
   another tenant's rows come back as `not_found` or `forbidden`.
5. Run `supabase test db` if the project has pgTAP tests.

Done when the test fails after you drop or loosen the policy, and passes
again once you restore it.

## Setup

- `better-supabase env` writes the URL and keys to `.env.local`; load it in the test setup.
- `better-supabase keys` creates `supabase/signing_keys.json`. Set `signing_keys_path = "./signing_keys.json"` under `[auth]` in `supabase/config.toml`, gitignore the file and restart the stack. `asUser` signs ES256 tokens with it.
- Typed fixtures live in `supabase/seed.ts`:

```ts
import { defineSeed } from "better-supabase/testing";
import { sb } from "../src/lib/supabase.ts";

export const seed = defineSeed(sb, {
  organizations: { acme: { id: ACME, name: "Acme" } },
  customers: { first: { id: FIRST, organizationId: ACME, name: "First" } },
});
```

`better-supabase seed` renders them to SQL for `supabase db reset`, and
tests import the same rows (`seed.rows.customers.first.id`).

## RLS tests

```ts
const alice = await asUser(sb, { sub: aliceId, tenant_id: ACME }, { postgres });
expect(await alice.db.customers.count().orThrow()).toBe(1);
expect(await alice.db.customers.findById(OTHER_ORG_CUSTOMER)).toMatchObject({
  ok: false,
});
```

- Check both directions: the user sees their own rows and never sees another tenant's.
- `alice.sql` runs the same checks over direct Postgres.
- Assert on `result.error.kind` (`not_found`, `forbidden`, `conflict`, `validation`), not on messages.

## API tests

Send `authorization: Bearer ${alice.token}` (or a token from `signLocalJwt`).
The adapter verifies it against the local JWKS; no test-only resolver is needed.

## pgTAP

`better-supabase sql add pgtap` installs `tests.create_user`,
`tests.authenticate_as(user, claims)`, `tests.clear_authentication()` and
`tests.rls_enabled('public')` for `supabase test db`. Put
`select tests.rls_enabled('public');` in a test so tables without RLS fail CI.
