# Decisions

Architecture decision records for this repository. Each one says what we
decided, why, and what it costs. Copy `0000-template.md` to the next number to
add one, and link it from the code or config it explains.

| ADR                                      | Decision                                                                           |
| ---------------------------------------- | ---------------------------------------------------------------------------------- |
| [0001](0001-library-profile.md)          | The repo follows the library profile of the repo standard                          |
| [0002](0002-deviations.md)               | Where the repo departs from the standard, and the lint backlogs                    |
| [0003](0003-cli-package.md)              | The CLI ships as `@better-supabase/cli` on citty; MCP keeps its own protocol layer |
| [0004](0004-commit-maintainer-skills.md) | Maintainer skills in `.agents/skills` and `skills-lock.json` are committed         |
| [0005](0005-temporal.md)                 | Time values in the public API are `Temporal`; the polyfill is an optional peer     |
| [0006](0006-pgdelta-and-native-stack.md) | The fixture schema diffs with pg-delta; the native local stack stays opt-in        |
