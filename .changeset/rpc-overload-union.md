---
"better-supabase": minor
---

`gen` keeps every overload of a database function. `Functions` types an overloaded name as a union of `{ Args; Returns }`, one member per overload in signature order, and its metadata entry lists each signature in `overloads`. `db.$rpc` accepts the arguments of any overload and returns the type of the overload whose argument names the call passes (the union when overloads share their names). At runtime it picks the same overload by argument names for result decoding and the Postgres executor. Before, `gen` kept only the first overload, so calls to the others were mistyped.
