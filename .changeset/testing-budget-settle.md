---
"better-supabase": patch
---

`expectDbBudget` and `expectInstant` keep listening after the navigation until no response has arrived for `settleMs` (500 ms by default), so a render that starts after an `instant()` lock releases is counted. A budget on a navigation that no render reached now fails, because the client cache served it and there is nothing to measure.
