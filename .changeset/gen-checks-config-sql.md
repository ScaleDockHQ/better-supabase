---
"better-supabase": patch
---

Make `gen` parse the SQL expressions in your config before it reads the schema. An authorization provider's `functions` template or a block's `{ sql }` event payload column that is not valid SQL now stops `gen` with the config key and the parser's message, instead of failing later in a migration. Placeholders such as `{user}` and `{row}` are accepted.
