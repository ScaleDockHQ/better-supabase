---
"better-supabase": patch
---

Fix `useRecordListState` dropping the facets of a list. nuqs keeps each facet under its own URL key (`status=active`), but the hook passed that flat state to `toSearchParams`, which reads facets from `facets`, so `searchParams` and `query` never carried a facet and a list route called with them returned every row. The hook now moves the facet keys under `facets` using the list's `facets`, so `list.set({ status: ["active"] })` reaches both the URL and the query.
