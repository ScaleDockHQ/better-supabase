---
"better-supabase": minor
---

New `prompts` block (`better-supabase/blocks/prompts`) for versioned prompt templates. `create`
saves the next immutable version of a named prompt, per tenant or for the whole system, and
`setLabel` points a label such as `production` at a version. `get` reads a label or an exact
version, and `render` fills `{{name}}` placeholders and throws on a missing or unused variable.
Only the service role reads or writes the tables. Run `better-supabase add prompts` to install it.
