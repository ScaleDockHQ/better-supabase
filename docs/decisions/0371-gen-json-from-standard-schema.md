# 0371: Type jsonb columns from the Standard Schema setup

## Status

Accepted

## Context

The `json` option of `standardSchema()` already named a schema value per jsonb column, and `gen.json` named a type for the same column, so one column was declared twice. The plan also lists settings among the things inferred from Standard Schema exports.

## Decision

`gen` types a jsonb column as `StandardSchemaV1.InferOutput<typeof name>` when a configured `standardSchema({ json })` names it and `gen.json` has no entry for it. The generated module imports the schema value with `import type`, which allows `typeof`, and imports `StandardSchemaV1` from the runtime package. `gen.json` wins. Settings are not inferred: `blocks.settings.options.schemas` takes a runtime value (the `defineSettings()` result) that the config loader would have to import, so it stays one explicit line.

## Consequences

A project declares a typed jsonb column once. The settings option stays explicit and is the one open part of this item.
