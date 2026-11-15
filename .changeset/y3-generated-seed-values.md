---
"better-supabase": minor
---

An entity page's `seed` takes four more keys, so `gen` can write demo rows for
pages it could not seed before. `fields` sets the value of an input field by its
name (a scalar for every row, or a list that row `i` reads at `i` modulo its
length), which seeds a risk's `category` with the block's configured categories.
`rows` declares the rows by hand for a block with no input schema that fits, and
`table` and `tenant` name the table when the block declares none. The descriptor
stays at `apiVersion: 1`. `gen` now stops with `config_invalid` when a `seed` has
no table instead of writing nothing. The `periods` block exports
`periodInputSchema`, the input of `createPeriod`, so a periods page seeds
through it and `gen` writes a `periods.form.ts` for the page.
