---
"better-supabase": minor
---

Add `defineBetterResultErrors(Result, classes, fallback)`: a typed mapping from `DbError` kinds to error classes, usually better-result `TaggedError` classes, bound to better-result's `Result` namespace. The converter it returns turns a `Result` or `AsyncResult` into better-result's `Result<T, E>` with the mapped error instances, checks the expected type like `toBetterResult`, and `map(error)` maps one `DbError` with a type picked by its kind. `toBetterResult` is unchanged.
