---
"better-supabase": minor
---

`DbStats` now carries a `trace` of every database call with its name, start and end in milliseconds, wave and phase (`action` inside `bsb.action`, `render` for every other call). The stats endpoint of the testing API returns it, so a harness can name each call of a page or action.
