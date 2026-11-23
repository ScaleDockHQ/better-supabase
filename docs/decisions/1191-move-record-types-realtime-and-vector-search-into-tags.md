# 1191: Move record types, realtime tables and vector search entries into table tags

- Status: accepted
- Date: 2026-11-22

## Context

The `subject`, `realtime` and `vector-search` tags already declare what
`recordTypes`, `realtime` and `vectorSearch` declare in the config, but only
`init --schema-first` wrote them. An existing project had no way to move its
entries, and the `subject` tag had no word for `held`, `template` or
`readAccess`.

## Decision

- The `subject` tag gains `held`, `template` (a column name) and `read-access`.
  A subject with a team, `history`, `auditReads` or template child tables keeps
  its entry in the config.
- `codemod table-tags` moves a `recordTypes` entry, a `realtime.tables` element
  (with its `global` and `users` entries) and a `vectorSearch` entry into the
  tag on the schema file that creates the table. Each move is kept only when
  the config read back through the tag gives the entry's own value; otherwise
  the entry stays and the codemod lists why.
- A subject registered under an alias keeps its entry: the resolved config is
  keyed by the alias, and the tag has no word for it.
- The codemod lists each hand-written trigger that calls
  `better_supabase.broadcast_topic()`. `realtime.triggers` declares the same
  trigger, so the hand-written one is a second copy that the codemod does not
  remove.
- Removing several elements of one config list shifts the later indexes, so the
  codemod adjusts each index by the elements already cut.

## Alternatives considered

- Rewrite the hand-written trigger into `realtime.triggers`: the SQL does not
  say which topic template the config exports, so the result could differ.

## Consequences

A project with these entries in the config can run `codemod table-tags --explain`
and move them. The config shrinks, and the table carries what it declares.
