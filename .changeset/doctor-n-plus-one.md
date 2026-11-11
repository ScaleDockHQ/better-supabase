---
"better-supabase": minor
---

Doctor reports database reads made once per item of a loop or a `map` callback (BS634) and reads that wait for an earlier read of a related table (BS635), and names the fix: an `include` on the outer read when the snapshot has a foreign key between the tables, otherwise one read with an `in` filter. Both are warnings; accept a deliberate case in the baseline or add the code to `tooling.doctor.ignore`. The new `tooling.doctor.parallelReads` option (default 3) sets how many reads one `Promise.all` may await before BS609 suggests a read set.
