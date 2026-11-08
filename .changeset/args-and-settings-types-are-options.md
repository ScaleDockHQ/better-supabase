---
"better-supabase": minor
---

Exported `*Args` and `*Settings` types are `*Options`, with no alias. `better-supabase codemod naming` renames them in your code. `RateLimitSettings` and `IdempotencySettings` are part of `RateLimitOptions` and `IdempotencyOptions`, `AccountingSettings` is `AccountingSetup` and `BucketSettings` is `StorageBucketOptions`.

| Old                        | New                           |
| -------------------------- | ----------------------------- |
| `AgentPassthroughSettings` | `AgentPassthroughOptions`     |
| `AddArgs`                  | `AddOptions`                  |
| `AggregateArgs`            | `AggregateOptions`            |
| `AssistantRunArgs`         | `AssistantRunOptions`         |
| `BoundArgs`                | `BoundOptions`                |
| `BulkActionArgs`           | `BulkActionOptions`           |
| `CodemodArgs`              | `CodemodOptions`              |
| `CountArgs`                | `CountOptions`                |
| `DataListArgs`             | `DataListOptions`             |
| `DeleteArgs`               | `DeleteOptions`               |
| `DurableTurnAgentArgs`     | `DurableTurnAgentOptions`     |
| `EveDispatchArgs`          | `EveDispatchOptions`          |
| `EveScheduleArgs`          | `EveScheduleOptions`          |
| `GenerationRunArgs`        | `GenerationRunOptions`        |
| `GetArgs`                  | `GetOptions`                  |
| `GuardsFindArgs`           | `GuardsFindOptions`           |
| `IncludeArgs`              | `IncludeOptions`              |
| `InitArgs`                 | `InitOptions`                 |
| `KeysArgs`                 | `KeysOptions`                 |
| `ManyWriteArgs`            | `ManyWriteOptions`            |
| `MembershipsFindArgs`      | `MembershipsFindOptions`      |
| `MigrateSchemaFirstArgs`   | `MigrateSchemaFirstOptions`   |
| `OffsetPageArgs`           | `OffsetPageOptions`           |
| `OffsetRangeArgs`          | `OffsetRangeOptions`          |
| `OverloadArgs`             | `OverloadOptions`             |
| `PresetSubjectSettings`    | `PresetSubjectOptions`        |
| `QueuePurgeArgs`           | `QueuePurgeOptions`           |
| `ReadArgs`                 | `ReadOptions`                 |
| `RemoveArgs`               | `RemoveOptions`               |
| `TanStackStartHandlerArgs` | `TanStackStartHandlerOptions` |
| `TanStackStartServerArgs`  | `TanStackStartServerOptions`  |
| `TrashDeleteArgs`          | `TrashDeleteOptions`          |
| `TrashFindArgs`            | `TrashFindOptions`            |
| `UpdateArgs`               | `UpdateOptions`               |
| `UpsertArgs`               | `UpsertOptions`               |
| `UpsertManyArgs`           | `UpsertManyOptions`           |
| `WriteArgs`                | `WriteOptions`                |
| `WriteManyArgs`            | `WriteManyOptions`            |
| `AccountingSettings`       | `AccountingSetup`             |
| `BucketSettings`           | `StorageBucketOptions`        |
| `RateLimitSettings`        | `RateLimitOptions`            |
| `IdempotencySettings`      | `IdempotencyOptions`          |
