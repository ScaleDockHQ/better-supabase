---
"better-supabase": minor
---

`better-supabase/workflow-sdk/world` follows `@workflow/world` and `@workflow/world-postgres` 5.1 (peer range `>=5.1.0 <5.2`, protocol 5.1.0). The `workflow-sdk` module is version 4: apply its migration before you deploy, because it converts the World timestamps to `timestamptz`. `createWorld()` now returns one World per process, `onDeadLetter`, `enableInvoke` and `streamFlushIntervalMs` are new options, `world.start()` fails with `MigrationDrift` when the installed World migrations differ from the generated ones, and `openHooks()` decodes `metadata_cbor`.

Release age exception (ADR 0210): the repo owner allowed `@workflow/world@5.1.0`, `@workflow/world-postgres@5.1.0`, `@workflow/world-local@5.2.0` and `@workflow/errors@5.1.0` through `minimumReleaseAgeExclude` before the 1440 minute window closed; remove the list on or after 2026-11-03 22:46 UTC.
