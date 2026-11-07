# 0254: Keep unscoped statements in one file and grant sequences by name

- Status: accepted
- Date: 2026-11-07
- Amends: 0250

## Context

Event triggers belong to no schema, and a trigger on `auth.users` belongs to a
schema the app doesn't own, so a diff limited to some schemas never plans them.
They sat in six module files between statements the diff does plan. The
workflow-sdk module also granted the service role `on all sequences in schema
workflow`, which names whatever the schema holds when the statement runs.

## Decision

`withUnscopedFile` in `src/sql/pipeline/unscoped.ts` moves each `create event
trigger` (with its `drop event trigger if exists` and the comment lines above
it) and each trigger on an `auth` table out of the module schema files and into
`900_better_supabase_999_unscoped.sql`. The file is a pseudo module named
`unscoped`, like the prelude: it has a `@bsb-block` line, `upgrade` writes and
removes it, and doctor leaves it out of the module list. The migrations workflow
(`layout.rerunnable`) keeps each statement in its module because it applies
statements in file order. The module data files still repeat the event
triggers.

`workflow-sdk` reads the sequences of the World's `serial` columns from its DDL
and grants each by name. A test over every module asserts that no grant or
revoke uses `on all`, and that a file never grants on an object before it
revokes `all` on it, so the final privileges come last.

The `do` block that copied the old `ai_chat_shares` rows into `share_links` is a
data statement. `ai-chat` now hands it to `share-links` as the new `data` field
of a share link contribution, and `share-links` writes it to its data file,
which `add --adopt` puts in a migration. Seeds already follow that path: the
`seeds` module's functions take a locale and no module schema file inserts rows.

Callbacks stay as they were: a hook is a function name from
`hooks.functions` that the block looks up with `to_regprocedure` when the call
runs, and its body lives in an app file. Writing `perform <name>(...)` at
generation time would need every pgTAP hook test to define its function before
the module is generated, and an app that adds a hook would have to run
`upgrade` before the hook fires.

## Alternatives considered

One unscoped file per module would leave the statements spread over six files.
Resolving hooks against the schema model at generation time was tried and
dropped for the reason above.

## Consequences

The repository's `supabase/` folder and the CentraKit fixture gain the unscoped
file and lose the statements from six modules; the schema sync reports no
changes and the 172 pgTAP files pass. Installed apps run `better-supabase
upgrade`.
