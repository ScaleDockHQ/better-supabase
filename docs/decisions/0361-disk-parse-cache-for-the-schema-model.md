# 0361: Keep the parse cache of the schema model on disk

- Status: accepted
- Date: 2026-11-08
- Amends: 0248, 0291

## Context

ADR 0248 gave the schema model a parse cache keyed on the content hash and a
parser version, and ADR 0291 left it in memory because parsing was 10 percent of
a warm `upgrade` once the result memo existed. Every other command (`doctor`,
`sync`, `dev` rebuilding after a change) still parses each file again in a new
process. Measured on all 370 files the 129 modules render (10 MB), a cold parse
takes about 190 ms and the memory cache only helps inside one process.

## Decision

- `createParseCache(store)` reads a `ParseStore` behind its memory map. The
  default store is the one the CLI installs with `setParseStore`, kept on
  `globalThis` because the bundle holds the module twice (as for the memo). A
  stored value is checked for the `ParsedFile` shape before use.
- `src/cli/cache/parse-store.ts` keeps `parse/files.json` under the cache
  folder: `{ salt, entries }` with the key `createParseCache` builds (parser
  version and content hash). The salt is the CLI version and a hash of the
  generator's files, so a changed parser never reads an old entry. The file is
  read once when the store opens and written once, when the process exits, and
  only when the run added an entry.
- The file holds at most 4096 entries. The entries a run used come last, so the
  oldest drop first.
- `--no-cache` installs no store, and `cache purge` removes the file with the
  rest of the folder.

## Measured

On the 370 files above, on one machine (Node 24):

| Case                               | Time   |
| ---------------------------------- | ------ |
| parse with no store                | 190 ms |
| open the store and build the model | 50 ms  |
| write the store after a cold run   | 4 ms   |

Most of the remaining 50 ms is hashing the 10 MB of text, which the key needs.

## Alternatives considered

- **A file per entry.** 370 small files cost more to open than one read of the
  JSON.
- **Writing after every file.** The memo store does that for its 48 entries; at
  hundreds of files it would rewrite the file hundreds of times per run.

## Consequences

A command that follows another in a new process no longer parses unchanged
files. A crashed process loses only the entries of that run.
