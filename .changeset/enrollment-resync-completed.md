---
"better-supabase": patch
---

`enrollment_ensure` now emits `enrollment.completed` when a resync removes the steps that were left and completes the enrollment. Run `better-supabase upgrade` to update the function.
