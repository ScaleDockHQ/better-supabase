---
"better-supabase": minor
---

Breaking: the SQL engine says block. `SqlModule` is `BlockSql`, `ModuleDefinition` is `BlockSqlDefinition`, and the other `Module*` types from `better-supabase/sql` are `BlockSql*` (`BlockSqlContext`, `BlockSqlLayout`, `BlockSqlNames`). `renderModules`, `resolveModules`, `resolveModule`, `isModuleIdType`, `sameModuleFile`, `InstalledModule` and `SkippedModule` are `renderBlocks`, `resolveBlocks`, `resolveBlock`, `isBlockSqlIdType`, `sameBlockFile`, `InstalledBlock` and `SkippedBlock`.

Four exports take their glossary names: `SubjectRef` is `RecordRef`, `entityForm` is `recordForm` (with `useRecordForm` and the `RecordForm*` types), `ShipmentCarrier` is `ShippingProvider` (`testShippingProvider`), and `QueueBackend` is `QueueProvider` (`sqlQueueProvider`, `transportQueueProvider`, `vercelQueueProvider`, `testQueueProvider`). `better-supabase codemod 0.15` renames these imports.

Installed versions live in `better_supabase.blocks` instead of `better_supabase.modules`. `sql upgrade` creates the new table and copies the rows before the schema diff drops the old one, and doctor reads the old table while the new one is missing. Block files carry `-- @bsb-block`, `-- @bsb-block-data`, `-- @bsb-block-test`, `-- @bsb-names` and `-- @bsb-tables` lines; `sql upgrade`, `sql sync` and doctor read the `@bs-*` lines of files written by 0.14 and older.
