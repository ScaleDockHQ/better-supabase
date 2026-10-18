---
"better-supabase": minor
---

App table columns take `format` (`email`, `url`, `phone`, `long_text`, `color`, `rating`, `percent`, `currency`), `options` for a single or multi-select, `min` and `max`, `comment` and `identity`. Tables take `id: "bigint"`, composite `unique` keys, `indexes` and a `comment`. `sql sync` renders each as a named constraint, index or comment, and the pgTAP file checks them; `email`, `url`, `rating`, `percent`, options and bounds add a check. No key takes free SQL.

A Create design that uses one of these keys gets `version: 1` in its JSON (`designFormat`, `DESIGN_FORMAT` from `better-supabase/preset`); older designs encode to the same code as before, and a code newer than the installed release fails with a message to update. Create's column type picker is grouped (Text, Number, Date and time, Choice, Relation, Other) with Single select, Email, Rating, Autonumber, Person and Currency, which splits into `<name>_minor` and `<name>_currency`.
