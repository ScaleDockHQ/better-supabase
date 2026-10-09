---
"better-supabase": minor
---

Writes take conditions, return rows from bulk calls and cap how many rows they change.

- `update(key, patch, { where })` returns `not_found` for a row that doesn't match, `expect` takes `where` operators, and `updateMany` and `deleteMany` take `returning: true`.
- `updateMany` and `deleteMany` take `maxAffected`; a write matching more rows fails with `max_affected` and changes nothing. It needs PostgREST 13 (set `postgrestVersion: "12.2"` on older servers), and the rules plugin's `strict()` preset requires it.
- Every call takes `timeout` and `retry`, `createMany` and `upsertMany` take `defaultToNull`, and mutations take `count: "planned"`.
- **Breaking:** `deleteMany` and `updateMany` refuse a `where` that filters nothing. Pass `allowAll: true` to `updateMany` to update every row.
- **Breaking:** an update whose `data` sets no columns returns `invalid_request` instead of `not_found`.
- **Breaking:** a `*` in `like` and `ilike` patterns is a literal character; use `%`.
