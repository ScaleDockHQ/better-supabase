---
"better-supabase": minor
---

One project pipeline for Create, the CLI and the cloud (ADR 0100). `better-supabase/create` adds `loadProject`, `checkProject` and a single `Issue` type with a `severity` and a `source`; `checkDesign`, `designIssues` and `validateDesign` now report `Issue` values, and the two `DesignIssue` types are gone (breaking: a lite issue has `table` and `file` where it had `module` and `path`). `previewFiles` takes `ownTables` and `ownColumns` to render over tables the project already has. `better-supabase/preset` exports the instance rules the cloud copied: `canAddInstance`, `blockRequires`, `instanceNameProblem`, `withInstance`, `withoutInstance`, `withEntityName`, `installedBlocks`, `presetKey`, `createQuery` and `presetArgumentOf`. Rename `DesignIssue` to `Issue` and read `issue.file` and `issue.table` for lite findings.
