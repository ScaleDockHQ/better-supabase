# validation-single-tenant

A B2C app with no organizations (ADR 0470). `supabase/schemas/010_app.sql` has
a `profiles` table and a `todos` table with owner policies. The config adopts
`profiles` and installs `sessions`. The tests hold `upgrade` to modules that
name no tenant, organization, membership or team, to owner-based policies, to a
second run that changes nothing, and to doctor's ownership rules.

```sh
pnpm test
```

`notifications` and `audit` keep a nullable `tenant_id`, so this app doesn't use them.
