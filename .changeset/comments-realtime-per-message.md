---
"better-supabase": minor
---

The comments controller and its React, Vue, Svelte and Solid hooks fetch only the comment a Realtime ping names, and its thread's root for the reply count, instead of loading the whole thread again. A client passed to `createCommentsController` now needs `get`.
