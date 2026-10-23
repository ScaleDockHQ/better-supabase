---
"better-supabase": minor
---

Removes `better-supabase scaffold screens`. The library writes no pages: build a table's screens
on its generated data hooks (`useTasks`, `useTask`) and start from the `record-*` UI recipes.
Running the old command exits with a message that says so. `scaffold api` is unchanged.
