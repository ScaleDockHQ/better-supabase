---
"better-supabase": patch
---

Maps the AI SDK's `steering-message` UI part to a `ui.steering-message` data part that keeps its text and file parts, and lets `syncWithAuth` infer its connector type from the `connector` option, so PowerSync 2.5's overloaded `connect` no longer breaks it.
