---
"better-supabase": minor
---

Every policy a block generates is named `bsb_<name>`, shortened with a hash past 63 bytes. Run `better-supabase codemod naming` to write the migration that renames them in an installed app (`alter policy ... rename to`); no data moves. `bsbPolicyName()` in `better-supabase/sql` returns the generated name for a module's name.

| Old                                          | New                                |
| -------------------------------------------- | ---------------------------------- |
| policies of block tables, `<table>_read` etc | the same name with `bsb_` in front |
