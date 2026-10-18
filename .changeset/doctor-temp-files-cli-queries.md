---
"better-supabase": patch
---

Doctor BS208 no longer warns about temporary files written by better-supabase's own catalog reads. `introspect`, `gen` and `doctor` now start each query they send over a database connection with the comment `/* better-supabase */`, and BS208 leaves those statements out, so running `introspect` before `doctor --strict` on a large schema no longer fails the check.
