---
"better-supabase": minor
---

Breaking: `db.$decode(table).row()` and `.rows()` return an `AsyncResult`, so `$decode` works with lazy tables (`gen.serverTables: "lazy"`). It loads the table and every table an embedded relation in the value reaches before it decodes; before, it threw `unknown table` for a table the process had not loaded yet. Add `await` where you read the result: `const customers = await db.$decode("customers").rows(rows)`. A failure that is not a database error is now an error result instead of a thrown exception.
