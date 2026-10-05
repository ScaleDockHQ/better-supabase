---
"better-supabase": minor
---

`toBetterResult` returns better-result's own `Result<T, E>` type when the call has one as its expected type (a variable annotation or a function's return type) or as its type argument, so the `as Result<T, E>` cast is no longer needed. The type is checked against the row type and the error that `mapError` returns. Without an expected type the return type is `BetterResultValue<T, E>` as before, and existing casts still compile. New exported types: `BetterResultOk<R>` and `BetterResultErr<R>`.
