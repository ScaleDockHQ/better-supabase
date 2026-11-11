# 0671: Page the import issue and diff lists by keyset

- Status: accepted
- Date: 2026-11-11
- Amends: 0660

## Context

ADR 0660 left `list_import_issues` and `list_import_diff` on positional `row_limit` and `row_offset`
arguments, because a changed signature is a migration for every caller. The user accepted that break.
Both functions also counted every matching issue before they returned a page.

## Decision

**A fifth argument, `after text default null`, pages by keyset.** The result adds `next_cursor`, which is
null on the last page. The offset arguments still work while `after` is null, so a caller that shows page
numbers keeps them. The old four-argument signatures are dropped, so a caller that named all four
arguments by position still compiles against the new ones.

- `list_import_issues` orders by `(created_at, id)`. The cursor is that pair as URL-safe base64, and a
  malformed cursor fails with `IMPORT_ITEM_INVALID` (`22023`). The `total` counts at most 10,000 rows
  with a bounded subquery, and is null on a keyset page, so a caller keeps the total from the first page.
  Two indexes end in the id: `(run_id, created_at, id)` and `(run_id, entity, created_at, id)`, which
  replaces the old `(run_id, entity)` index.
- `list_import_diff` reads the diff array of the run. The cursor is the 1-based position of the last
  returned entry, and the page starts after it. The diff lives in one jsonb column, so no index applies.

## Consequences

Measured on the native stack with 60,000 issues and a 60,000 entry diff in one run
(`supabase/tests/scale/scale_import_lists.test.sql`). One cold run each, in milliseconds:

| Read                                 | Before | After |
| ------------------------------------ | ------ | ----- |
| issues, first page of 50             | 9.7    | 1.5   |
| issues, deep offset page (59,900)    | 13.8   | 4.5   |
| issues, deep keyset page             | n/a    | 3.7   |
| issues, entity filter, offset 29,900 | 8.3    | 3.2   |
| diff, first page                     | 4.8    | 4.8   |
| diff, deep offset page (59,900)      | 6.0    | 6.3   |
| diff, entity filter, offset 29,900   | 7.9    | 7.7   |

The issues list gains from the capped count and the indexes. The diff list does not change at this size:
it walks one jsonb array in memory either way, so the keyset form only gives a stable page while a run
is still adding entries. A diff of millions of entries would need its own table.
