---
name: better-supabase-testing
description: Test Supabase RLS policies, APIs and SQL against the local stack with better-supabase/testing, typed seeds and pgTAP. Use when writing or fixing tests that touch the database, policies or auth.
---

# Testing with better-supabase

Test against the local stack (`supabase start`) as real users. Don't mock
supabase-js, and don't use the service role for anything a user does.

## Setup

- `better-supabase env` writes the URL and keys to `.env.local`; load it in the test setup.
- Typed fixtures live in `supabase/seed.ts`:

```ts
import { defineSeed } from 'better-supabase/testing';
import { sb } from '../src/lib/supabase.ts';

export const seed = defineSeed(sb, {
  organizations: { acme: { id: ACME, name: 'Acme' } },
  customers: { first: { id: FIRST, organizationId: ACME, name: 'First' } },
});
```

  `better-supabase seed` renders them to SQL for `supabase db reset`, and
  tests import the same rows (`seed.rows.customers.first.id`).

## RLS tests

```ts
const alice = await asUser(sb, { sub: aliceId, org_id: ACME }, { postgres });
expect(await alice.db.customers.count().orThrow()).toBe(1);
expect(await alice.db.customers.findById(OTHER_ORG_CUSTOMER)).toMatchObject({ ok: false });
```

- Check both directions: the user sees their own rows and never sees another tenant's.
- `alice.sql` runs the same checks over direct Postgres.
- Assert on `result.error.kind` (`not_found`, `forbidden`, `conflict`, `validation`), not on messages.

## API tests

Pass `auth: { resolvers: [localAuth(LOCAL_JWT_SECRET)] }` to the adapter and
send `authorization: Bearer ${alice.token}`.

## pgTAP

`better-supabase sql add pgtap` installs `tests.create_user`,
`tests.authenticate_as(user, claims)`, `tests.clear_authentication()` and
`tests.rls_enabled('public')` for `supabase test db`. Put
`select tests.rls_enabled('public');` in a test so tables without RLS fail CI.
