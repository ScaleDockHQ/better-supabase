# 0663: Declare broadcast triggers on topics and copy database types to more files

- Status: accepted
- Date: 2026-11-10
- Amends: 0637, 0642

## Context

ADR 0637 and ADR 0642 listed two items as not done: broadcast triggers from `defineTopic`, and several
`gen` output targets. A topic's policies come from `defineTopic`, but its triggers lived in a separate
config list (`database.realtime.triggers`) that names the topic by template, so a rename of the topic
broke the config and the two places drifted. In a monorepo, a web app, a native app and a shared
package each need `database.types.ts`, and each ran `gen` against its own output.

## Decision

**Triggers on the topic.** `defineTopic(template, { broadcast: [...] })` takes entries with a `table`
and the options `topic.trigger()` takes, without `topic`. The topic keeps them in `topic.broadcasts`.
`upgrade` writes one trigger per entry to the `realtime.policies` output after the policies and the
config triggers, through the same `trigger()` call, so the SQL is the same as the config form. Errors
name the topic and the entry's position, and a `broadcast_topic()` trigger still needs `realtime-tables`.
An entry that sends to several topics stays in `database.realtime.triggers`, which takes `topics`.

**A copy of the types.** `gen.types.also` lists files, relative to the root, that get the same
`database.types.ts` as `gen.types` writes. The file is self-contained, so a copy needs nothing beside
it. The copies join the generated file list, so `gen --check` fails when one is stale. A path equal to
the main types file is written once. The content mapper has no `database.types.ts`, so it writes no
copies.

## Alternatives considered

- Mirror the whole generated set to other directories: the generated modules import config modules by
  relative path, so a verbatim copy elsewhere breaks its imports. Only the self-contained file copies.
- Make `realtime.triggers` read the topic's own list: it keeps two sources for one trigger.

## Consequences

A topic file now carries SQL-level table names, so it is read by the CLI as before and by the browser
as a plain array of strings and options. Apps that already use `realtime.triggers` need no change.
