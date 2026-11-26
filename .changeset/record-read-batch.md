---
"better-supabase": minor
---

`bsb.record(type).get` and `timeline` read a page's bindings in one request. The `read-sets` block now writes `read_batch(calls jsonb)`, a `stable`, `security invoker` function that runs up to 50 `stable` JSON reads of the exposed schema as the caller and returns one result per call. The first read of every binding goes into one `read_batch` call, and each binding gets the same data or `DbError` a direct call returns. Reads that write, and every read in a project without the function, run on their own as before.

Run `better-supabase upgrade` and generate a migration (`supabase db diff`) to add the function. Ask for every binding a page shows in one `get` to get the saving.
