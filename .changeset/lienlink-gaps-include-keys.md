---
"better-supabase": patch
---

`list`, `page` and `get` reject an `include` key that names no relation at compile time, also next to a real one (`include: { notes: true, note: true }`). The generic `const A` argument skipped TypeScript's excess property check, so a misspelled relation compiled and failed at runtime.
