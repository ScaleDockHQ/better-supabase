---
"better-supabase": minor
---

`gen` runs generators that declare `workerSafe` and a `module` on worker threads once a schema has 1500 tables, and writes the same files as a single thread. The built-in generators declare their module; `Generator` gains `module` (`{ specifier, export }`) and `testGeneratorPlugin` checks that the generator rebuilds from it.
