---
"better-supabase": minor
---

Show record sections as list columns, merge a record's sections into one timeline, and list what waits on the caller across blocks. See [Record lists and My work](https://bettersupabase.com/docs/blocks/record-lists).

- `defineRecordList(feature, list, { columns })` in `better-supabase/records` runs a list query and fills each section column (`count` or `data`) for the whole page in one wave, with `can` flags and the filter fields. `recordListServer(bs, recordList)` in `better-supabase/next` loads it as plain data.
- `loadTimeline(source, subject)` merges every section with a `timeline` hook, newest first, and lists the sections it skipped. The comments, versions and attachments sections map their rows to timeline entries, and the comments section counts rows for list columns. `recordServer(...).timeline(id)` loads it after the permission check.
- The subjects block installs `my_work(tenant, page_size)`: assigned work items, approvals the caller can decide, due reminders, mentions and SLA warnings, each only when its block is installed. `blocks.subjects.myWork()` calls it, and `loadMyWork` groups the items by kind with counts.
- `useRecordListState(list, useQueryStates(parsers))` in `better-supabase/react` keeps a list's sort, facets, filter and page in the URL through nuqs and returns the typed query.
- With record features on, `gen` writes `navigation.generated.ts` and `commands.generated.ts`: a sidebar item and a "Go to" command per subject with a list route, each with its read permission.

Run `better-supabase sql upgrade` to add `my_work` to an installed subjects block.
