---
"better-supabase": patch
---

`doctor` and `codemod` use TypeScript 7.1 or newer, when your project has it, to follow a name across files. BS609, BS634 and BS635 drop a read whose receiver TypeScript types as a plain collection such as a `Map`. `codemod naming` renames the files that import a renamed export your app re-exports, and `codemod config` removes a `columns` entry from the file that declares an imported config value. Without TypeScript 7.1, doctor adds an info finding that says receivers were matched by name, and each codemod lists the files it did not follow as review lines.

The config, naming and column codemods now rewrite your config and source through a parser, and the doctor source checks read functions, loops and `Promise.all` calls from the syntax tree, so a regular expression, a template literal or JSX text no longer changes what they find.
