---
"better-supabase": minor
---

Read SQL with one reader and compare statements by their canonical text (ADR 1212 and 1213).

Breaking for callers of `better-supabase/sql`: the statement splitter is gone from the entry. The CLI reads statements from the parser's scanner, which needs no valid grammar and keeps the same lines.

| Removed from `better-supabase/sql` | Use instead                                                                                       |
| ---------------------------------- | ------------------------------------------------------------------------------------------------- |
| `splitStatements`                  | Split in your own code, or read the file with the `better-supabase` CLI (`doctor`, `gen`, `sync`) |
| `SqlStatement` (type)              | `{ text: string; line: number }`                                                                  |

`sync` and the codemods compare statements by the parser's deparse, so spacing, comments, keyword case and redundant quoting no longer make a statement new. The migration file hash is versioned: new files end in `_v2-<8 hex digits>.sql`. A migration an earlier release wrote, with the old hash, is still recognized as the same file and is never renamed, so upgrading writes no new migration. A statement set that does not parse keeps the old name form.

- `better-supabase/sql` no longer exports the SQL text readers: `addedColumnTypes`, `adoptedColumnProblems`, `adoptedTables`, `adoptedViews`, `appColumnsOf`, `auditRegistrations`, `buildModel`, `checkValues`, `columnTagComments`, `conflicts`, `declaredCheckValues`, `declaredColumnTypes`, `declaredForeignKeys`, `declaredIndexes`, `declaredPolicies`, `declaredTableColumns`, `declaredTables`, `declaredUpdatedAtTriggers`, `declaredViews`, `duplicateObjects`, `duplicatePolicies`, `extensionSchema`, `mappingTagsOf`, `moduleWritesText`, `ownedColumns`, `ownerOf`, `parseDeclared`, `policyGrants`, `rlsTables`, `sameTenantLayout`, `sameTenantTagsOf`, `setParseStore`, `splitStatements`, `widenedCommands`, `withMappingTags`, `writtenValues` and the types `AdoptedTable`, `AdoptedView`, `CheckValues`, `ColumnTagComment`, `Declaration`, `DuplicateObject`, `OwnedColumn`, `ParseStore`, `SameTenantTags`, `SchemaModel`, `SqlStatement`, `TableCheckValues`. The CLI reads SQL with one reader on `@supabase/pg-parser`, and `sync` compares statements by their canonical text. New migration files end in `_v2-<hash>.sql`; earlier names stay recognized. `migrationFile` is async.
