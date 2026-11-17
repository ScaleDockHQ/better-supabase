---
"better-supabase": patch
---

PowerSync uploads now replay for tables that load on first use. Before, `createUploadConnector` and `uploadRoute` refused every queued `PUT` and `PATCH` on such a table as `unsupported` and dropped the change, because the lazy repository answered `false` to `"upsert" in repository`. A lazy repository now answers the `in` operator like its getter: before the table loads every method name is present, and after it loads the built repository answers.
