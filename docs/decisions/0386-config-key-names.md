# 0386: Config keys name a directory `dir`, a file `file` and the record types `recordTypes`

- Status: accepted
- Date: 2026-11-08
- Amends: 0100, 0246, 0261

## Context

The naming plan gives each config key one spelling: `tenant` for the tenant,
`recordTypes` for the registry of record types, `adapters` for the framework
and runtime glue, `file` for a file path and `dir` for a directory. The config
still wrote `output` for every file, `subjects` for the registry, and the flat
`integrations` and `organization` keys survived in the flat shape the resolver
reads.

## Decision

- `subjects` is `recordTypes`. The `gen.recordTypes` switch that writes
  `records/<type>.ts` is `gen.records`. The `subjects` key inside a block entry
  stays: it binds that block to record types (ADR 0102 names it `on`).
- Every `output` that names a file is `file`: `gen.file`, `database.seed.file`,
  `database.seed.sample.file`, `database.realtime.policies.file`,
  `tooling.env.file`, `tooling.keys.file`, `tooling.doctor.file` and the
  `file` of each `api.specs.outputs` entry. The resolved config keeps
  `output` and `databaseTypesOutput` at its top level, because
  `GeneratorConfigView` is part of the plugin contract (`apiVersion` 2).
- The flat shape the resolver reads says `tenant` and `adapters`, as the
  grouped shape does. The design field `integrations` of a preset is
  `adapters`.
- A config that still writes an old key is refused with the new name
  (`movedKeyIssues`, which `doctor` and every command report). There is no
  alias.
- `codemod naming` rewrites the same-parent keys in the file that calls
  `defineConfig`, from `configKey` rows of `api/naming.json`; a scanner follows
  the nesting, so `blocks.<name>.subjects` is untouched. A key that moved to
  another parent (`organization` to `auth.tenant`) is reported for the author
  to move.

## Not done

`blocks.<name>.subjects` and `specs.outputs` keep their names, and the file and
`dir` keys of the generated layout move with ADR 0387.
