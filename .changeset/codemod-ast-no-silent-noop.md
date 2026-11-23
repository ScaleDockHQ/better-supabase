---
"better-supabase": patch
---

Make the codemods read TypeScript through the syntax tree and never skip a file in silence:

- `codemod naming` renames an environment variable where code names it (`process.env.NAME`, a key, a binding) and a hint code or event name only when the whole string is the name. Comments stay as they are, and a string that holds a renamed environment variable among other words gets a review line. `.env*` files and `turbo.json` keep a text rename.
- Every codemod with a source stage lists a TypeScript file that does not parse, with the line and the parser's message, instead of returning it unchanged.
