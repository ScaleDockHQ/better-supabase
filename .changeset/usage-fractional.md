---
"better-supabase": minor
---

Usage quantities, counters and quota limits are `numeric`, so a meter counts fractions (GB-hours, decimal credits) against a fractional quota. The `usage` module moves to version 2: the counter, event and quota columns change type in place, and `record_usage`, `consume_quota` and `mark_usage_reported` take `numeric` (`better-supabase sql upgrade` drops the `bigint` signatures). `within_quota` keeps its whole `quantity`.
