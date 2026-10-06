---
"better-supabase": minor
---

**Breaking:** a connected bucket's `publicUrl()` returns a `Result<string>` instead of a string, like `path()`. It used to throw a `DbException` for a path outside the bucket's templates or another tenant's path, while every other bucket method reported those as an error `Result`. To upgrade, read `.data` (`null` on an error) or check `.ok` where you call `publicUrl()`; `better-supabase codemod 0.6` lists those calls.
