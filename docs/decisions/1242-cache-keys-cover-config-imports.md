# 1242: Key the render and generator caches on the config imports

- Status: accepted
- Date: 2026-11-22

## Context

The render cache keyed on the block names, the layout, the CLI version and
`generatorHash()`. A config file can import helpers (a table of rows, a shared
column map) and the resolved layout holds their results, but a layout that
carries a function is never cached, and the generator cache keyed on neither the
generator files nor the config's imports. A rebuilt generator or an edit to an
imported file could serve an older result from `node_modules/.cache`.

## Decision

- `loadConfig` hashes the config file and every project file it imports through
  a relative specifier (`from`, `import()` and bare `import`), following
  `./x.js` to `./x.ts` and a directory to its index, and records the hash for
  the project root (`cli/cache/config-imports.ts`).
- `renderBlocksCached` adds that hash to the salt next to the CLI version and
  `generatorHash()`. `runGenerators` adds `generatorHash()` and the hash to every
  pure generator's key through a `salt` argument of `generatorKey`.
- Packages are not hashed: the lockfile and the CLI version cover them.

## Alternatives considered

- Parse the imports with `oxc-parser`: a scan over-approximates (a string that
  looks like an import adds a file), which only makes the key coarser, and it
  avoids loading the parser on the startup path.
- Hash the whole project: every unrelated edit would miss the cache.

## Consequences

Editing any file the config imports renders again once. Loading a config from a
temporary copy (the prune codemod does) records the copy's hash for the same
root; the render cache is bypassed there, so it only costs one extra render.
