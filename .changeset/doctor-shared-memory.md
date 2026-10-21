---
"better-supabase": minor
---

Add doctor checks for the machine's System V shared memory, which every local stack and shadow database needs.

- BS700 warns when 80% of the segment limit is in use (32 on macOS) and names the stacks that hold segments, so `supabase db diff` failing with `could not create shared memory segment` points at `stack prune`.
- BS701 warns when a stack holds more than its one interlock segment, which means its Postgres sets `shared_memory_type` or `dynamic_shared_memory_type` to `sysv`.
