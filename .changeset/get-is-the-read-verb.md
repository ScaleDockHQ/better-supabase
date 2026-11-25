---
"better-supabase": minor
---

Reads are `get*` everywhere (ADR 1250). The functions that read a source lose
their `load` and `read` verb, the record binding `load` member is `get`, and
`better-supabase codemod naming` renames the functions in your app.

| Old                                                   | New                                                  |
| ----------------------------------------------------- | ---------------------------------------------------- |
| `loadConfig`, `loadProject`, `loadSnapshot`           | `getConfig`, `getProject`, `getSnapshot`             |
| `loadEnv`, `loadJsonPath`                             | `getEnv`, `getJsonPath`                              |
| `loadBindings`, `loadMyWork`, `loadTimeline`          | `getBindings`, `getMyWork`, `getTimeline`            |
| `readCatalog`, `readSecurityCatalog`                  | `getCatalog`, `getSecurityCatalog`                   |
| `readDesignFile`                                      | `getDesignFile`                                      |
| `readPolicies`, `readGrants`, `readRulePolicies`      | `getPolicies`, `getGrants`, `getRulePolicies`        |
| `readArgSource`, `readArgSqlType`                     | `getArgSource`, `getArgSqlType`                      |
| `readStatus`, `readBitstringStatus`                   | `getStatus`, `getBitstringStatus`                    |
| `readC2paManifest`                                    | `getC2paManifest`                                    |
| `bsb.record(...).load(id)`, `recordListServer.load`   | `bsb.record(...).get(id)`, `recordListServer.get`    |
| record binding `load`                                 | `get`                                                |
| `SchemaMeta.tableLoaders`, `SchemaMeta.loadFunctions` | `SchemaMeta.tableGetters`, `SchemaMeta.getFunctions` |
| generated `load<Name>SearchParams`                    | `get<Name>SearchParams`                              |
