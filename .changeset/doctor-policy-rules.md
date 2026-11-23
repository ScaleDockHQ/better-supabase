---
"better-supabase": minor
---

Doctor gains three information rules. BS641 reports a table with more than
`doctor.policies.max` policies (default 4) for one command and names each policy's kind and
origin: library, provider or app. BS642 reports an exposed table with RLS whose index leads with
an enum column, because `enum_eq` is not leakproof. BS643 counts the functions per schema by
caller: policy, trigger, app RPC, service only or unreferenced. The new `config functions`
command lists the same inventory, and `listFunctions` in `better-supabase/sql` classifies it
(ADR 1216).
