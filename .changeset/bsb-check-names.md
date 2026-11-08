---
"better-supabase": minor
---

Every check constraint a block adds is named `bsb_<table>_<column>_check` (`bsb_<table>_check` when it reads more than one column), where Postgres used to choose the name. Run `better-supabase codemod naming` to write the migration that renames the checks of an installed app; no data moves.

| Old                                              | New                                |
| ------------------------------------------------ | ---------------------------------- |
| checks of block tables, `<table>_<column>_check` | the same name with `bsb_` in front |
| checks a module named, `<table>_<name>`          | the same name with `bsb_` in front |
