# 0630: Add db squash, env.map, a fetch-level PostgREST fake, asSignedInUser and two pgTAP helpers

- Status: accepted
- Date: 2026-11-10

## Context

CentraKit keeps a shell script that squashes its migrations (it calls `sql data`, which no longer
exists), a wrapper that renames the variables `dev env` writes, a PostgREST fake of its own, a
test user that signs in through Auth and two pgTAP helpers. The second audit listed all five.

## Decision

- `better-supabase db squash` deletes the migrations, writes one baseline with
  `supabase db schema declarative sync --no-apply --strict-coverage`, and carries over the module
  extensions migration and the data migrations `--keep` names (one file per name, merged in
  order). It restores the old files when the baseline fails, asks for consent before deleting
  (`overwrite`), and has `--dry-run`. It never touches a database.
- `env.map` (`{ NAME: source }`) adds variables to what `dev env` and `dev run` set. A source is a
  variable the command writes or a key of `supabase status -o json`; an unknown source is an
  `invalid_input` error. It adds names and never removes the standard ones.
- `createFakePostgrest(handler)` in `better-supabase/testing` is a `fetch` that answers
  `/rest/v1/...` from the handler `createFakeClient` already takes, so the real supabase-js client
  runs. It answers `count=exact` and `.single()` like PostgREST.
- `asSignedInUser(bsb, { email, password })` signs in through `/auth/v1/token` and reads the claims
  from the token, so a custom access token hook shows in tests.
- The pgTAP module gets `tests.act_as(role, user_id, claims)` and
  `tests.visible_row_count(relation, filter)`. They run `set local role` and `count(*)` as the
  caller, so RLS applies.

## Alternatives considered

- Run `sql data` in `db squash`: the command was removed, and module data now comes from the
  declarative layer.
- Merge `env.map` into `env.prefix`: a prefix adds two names, a map names any.
- A separate `tests` schema file for the helpers: the pgtap module already installs the `tests`
  schema, and a second file would install it twice.

## Consequences

Each CLI addition has a docs section, a help snapshot and a changeset. `db squash` is for a
deliberate reset: it must not run against migrations a hosted project applied. The fake does not
parse filters; the handler reads `query` like it does with `createFakeClient`.
