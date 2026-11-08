---
"better-supabase": minor
---

Doctor has four rules for declarative schema files. BS371 reports an object two schema files both declare, and names the prelude when a module file still pastes one of its helpers. BS372 reports a `do` block in an app file that creates objects, BS373 reports `if not exists` on an app table or index, and BS374 reports an insert in a block module file. `better-supabase upgrade --check` also fails while a module file declares a function the prelude defines.
