# Decisions

Architecture decision records for this repository. Each one says what we
decided, why, and what it costs. Copy `0000-template.md` to the next number to
add one, and link it from the code or config it explains.

| ADR                                             | Decision                                                                                     |
| ----------------------------------------------- | -------------------------------------------------------------------------------------------- |
| [0001](0001-library-profile.md)                 | The repo follows the library profile of the repo standard                                    |
| [0002](0002-deviations.md)                      | Where the repo departs from the standard, and the lint backlogs                              |
| [0003](0003-cli-package.md)                     | The CLI runs on citty; MCP keeps its own protocol layer (package split superseded)           |
| [0004](0004-commit-maintainer-skills.md)        | Maintainer skills in `.agents/skills` and `skills-lock.json` are committed                   |
| [0005](0005-temporal.md)                        | Time values in the public API are `Temporal`; the polyfill is an optional peer               |
| [0006](0006-pgdelta-and-native-stack.md)        | The fixture schema diffs with pg-delta; the native local stack stays opt-in                  |
| [0007](0007-cli-in-library.md)                  | The CLI ships inside `better-supabase` with its dependencies inlined                         |
| [0008](0008-middleware-entries.md)              | The server and the adapters run on `@supabase/middleware` entries and bridges                |
| [0009](0009-stripe-peer-and-openfeature.md)     | Stripe is a lazily loaded optional peer; OpenFeature is typed structurally                   |
| [0010](0010-neutral-blocks-and-sdk-adapters.md) | AI blocks stay SDK-neutral; SDK adapters own no tables; tokens sit behind a `credential_ref` |
| [0011](0011-authorization-providers.md)         | Authorization is a neutral, versioned `AuthorizationProvider`; libraries ship adapters       |
| [0012](0012-kits-renamed-to-blocks.md)          | Kits are blocks; feature modules import from `better-supabase/blocks/<name>`                 |
| [0013](0013-node-only-sdk-adapters.md)          | SDK adapters whose SDK needs Node (`workflow-sdk/world`, `eve`) are Node-only entries        |
| [0014](0014-nestjs-create-require.md)           | `better-supabase/nestjs` loads `@nestjs/common` with a synchronous `createRequire`           |
