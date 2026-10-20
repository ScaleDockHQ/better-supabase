---
"better-supabase": minor
---

Check a Create design in one call, and hand designs too large for a URL to `init` as a file.

- `checkDesign(input, preset)` in `better-supabase/create` checks a design object, design code or
  `/create` URL against a preset with every rule the canvas and `sql sync` apply. It returns
  `{ ok: true, design, code }`, where `code` is `null` for a design too long for a URL, or
  `{ ok: false, issues }`, and never throws for a bad design.
- `parseDesign(value)` in `better-supabase/preset` checks the shape of a design object.
- `designFileSource` and `readDesignFile` write and read a design file
  (`better-supabase.design.json`, `DESIGN_FILE`), which holds the preset code and the design as
  JSON with no length limit.
- `init --preset ./better-supabase.design.json` and `apply --preset ./better-supabase.design.json`
  read a design file like a Create URL. `DesignTooLongError` now points to it.
