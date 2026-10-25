# 0100: One project pipeline for the config, the CLI, Create and the cloud

- Status: accepted
- Date: 2026-10-25

## Context

The config, the CLI, Create and the cloud app each read a project in their own way. A design
converts to config in two places (`designConfig` and `writeDesign`). Four validators
(`checkDesign`, `designIssues`, `validateDesign` and `validateDraft`) each cover a different
subset, and two exported types are both named `DesignIssue`. `previewFiles` renders without the
app's own tables, so Create can't show what a block does over an existing table. The cloud copies
library rules (core blocks, instance names, requirements, URL and command builders, column enums).

## Decision

A project is `{ config, files, catalog }`.

- `loadProject(source)` reads it from disk, memory, a stored version or a design file and returns
  the project with its own tables read from the catalog, never from a regex over SQL.
- `checkProject(project)` returns one `Issue[]` that covers config, tags, SQL, the verifier (ADR 0105) and the plan (ADR 0106). `checkDesign`, `designIssues` and `validateDesign` become thin
  wrappers, then go.
- The renderer always receives own tables, in Create as well, so every surface shows the same
  output.
- The library exports the rules the cloud copied: core blocks, `instancePrefix`, instance-name
  checks, requirements, the tables each instance owns, the URL and command builders, `presetKey`
  and `installedBlocks`.
- The grouped config is the only public shape. The flat shape stays internal, and `tables` means
  one thing.

## Alternatives considered

- Keep the validators and add an adapter per consumer: each consumer keeps its own gaps.
- Move the pipeline to the cloud: the CLI and Create would still diverge from it.

## Consequences

Breaking: `validateDesign`, `designIssues` and the second `DesignIssue` type go. The cloud deletes
its copies after the library release. Every surface shows the same findings for the same project.
