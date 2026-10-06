---
"better-supabase": minor
---

**Breaking:** a bucket definition's `path(values)` returns a `Result<StoragePath>` instead of a `StoragePath`, like the connected client's `path()` and `publicUrl()`. It used to throw a `DbException` for a value Storage would refuse (empty, `.` or `..`, a `/` or an unsupported character) or for keys no template takes, so a path built from user input needed a `try`. To upgrade, read `.data` (`null` on an error) or check `.ok` where you call `bucket.path({ ... })`; the type checker flags each call that expects a string, and `better-supabase codemod 0.6` lists them.
