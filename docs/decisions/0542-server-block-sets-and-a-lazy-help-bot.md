# 0542: Build a route's server from a named block set, and load the help bot on demand

- Status: accepted
- Date: 2026-11-08
- Amends: 0451, 0541

## Context

ADR 0541 estimated that a subset of blocks could remove at most 7.5% of a page's server
chunks, from a source-map breakdown that charged block code to the shared library chunks
it lives in. The owner asked for the pilot anyway. Measured by building the Next.js
example with the blocks removed (an upper bound), the sign-in page fell from 2,607,956 to
1,375,298 bytes raw and `/api/customers` from 2,321,615 to 1,080,319, so the estimate was
wrong: block code and what it drags in (the AI SDK, the knowledge base, 800 KB of
library chunks) is about half of each route. Every server module imported
`betterSupabase` from `index.ts`, which composes all installed blocks.

`defineBlocks` already accepts any map of blocks and `createBlocks` already checks that a
required port has a provider in the map, so a subset needed no new runtime. What was
missing was a generated module that imports only the listed blocks.

## Decision

- `gen.serverBlocks` (`{ name: [instances] }`) writes `blocks.<name>.ts` with
  `<name>Instances` and `<name>Blocks`, a `defineBlocks` over only those instances, each
  imported from its own subpath. `gen` fails when a listed block requires a port no listed
  block provides, when an instance is unknown, renamed or has no client. It is the server
  twin of `gen.clientBlocks`.
- The example builds two servers from sets: `core` (permissions) for the sign-in action and
  `/api/customers`, and `shell` (permissions, organizations, profiles, usage, onboarding,
  audit, notifications, inbox) for the layout and the customers page. `server-core.ts` and
  `server-shell.ts` hold the same `createNext` options as `server.ts`. Notifications take
  the app's types in `shell.ts` by spreading `shellInstances`. `customers-queries.ts` and
  `customers-actions.ts` keep the record page and its blocks on the full server; the list
  query and `createCustomer` moved to `features/customers-list` and
  `features/customers-create`.
- The inbox actions load `help-bot.ts` with `import()` inside `after`, because the bot
  imports the AI SDK, the assistant and the knowledge base (about 440 KB raw on the
  server). A member who asks for help pays for it, the page that renders the layout does not.
- A lazy `app.ts` is not built. With the schema cut to two of 19 tables, the sign-in page
  fell 1.3%, `/api/customers` 1.7% and the customers page 0.8%, under the 5% bar.
- `tags.replace` stays as it is. It runs the `attach` and `detach` hooks per tag, which the
  tags client documents, and a SQL function would drop them (ADR 0541).
- `ServerContext<App>` stays reverted (ADR 0541).

## Measured

The server baseline, raw, gzip and brotli, before and after:

| Route                            | Raw                             | Gzip                        | Brotli                      |
| -------------------------------- | ------------------------------- | --------------------------- | --------------------------- |
| `/[locale]/(app)/customers/page` | 3,359,804 to 1,677,488 (-50.1%) | 989,703 to 524,852 (-47.0%) | 807,943 to 444,415 (-45.0%) |
| `/[locale]/(auth)/login/page`    | 2,607,956 to 1,355,560 (-48.0%) | 774,821 to 419,910 (-45.8%) | 624,781 to 352,467 (-43.6%) |
| `/api/customers/route`           | 2,321,615 to 1,060,348 (-54.3%) | 692,337 to 329,701 (-52.4%) | 573,585 to 287,818 (-49.8%) |

Of 173 routes, 116 fall in raw bytes (the pages whose layout is now the shell). 48 rise by
at most 3,701 B raw (0.13%) and 52 rise in brotli by at most 2.5%: those routes still
import the full server, and a third module group splits their shared chunk, so the
chunks compress separately and slightly worse. They are the routes that did not adopt a
set yet, and the baseline records the new numbers. No client route grew in raw bytes
(`tests/next-build` client baseline unchanged).

### Where the bytes were

Source-map breakdown of the three routes before the change (bytes mapped to a source;
generated code that no mapping covers is charged to the neighbouring source, so the
numbers are indicative). Customers page, top contributors: library chunks 865,819 (25.8%),
`next` 603,593 (18.0%), app `lib` 347,394 (10.3%), block modules 254,483 (7.6%), `ai`
153,833, `zod` 130,320, `better-result` 118,982, `@t3-oss/env-core` 116,941,
`@ai-sdk/provider-utils` 97,697, `jose` 71,266. Sign-in page: library chunks 838,080
(32.1%), `next` 541,514, app `lib` 345,693, block modules 254,483, `better-result` 118,982,
`@t3-oss/env-core` 116,941, `env.ts` 99,641, `jose` 38,333, `tailwind-merge` 27,239,
`@formatjs/icu-messageformat-parser` 24,664. `/api/customers`: library chunks 740,706,
app `lib` 363,511, `next` 329,858, block modules 286,021, `better-result` 80,939,
`@supabase/storage-js` 74,537, `temporal-polyfill` 70,190, `@supabase/ssr` 37,323,
`std-env` 36,779, `@supabase/auth-js` 33,505. After the change the customers page is
`next` 646,055, app `lib` 284,834, library chunks 211,484, `jose` 71,285.

## Alternatives considered

- A lazy `app.ts` first. It saves at most 1.7% on these routes.
- One shell set for every route. The sign-in page and the API would carry the inbox and
  notifications for no reason.
- Sharing one session memo across sets. A route imports one server, so each set pays one
  verification, as `server.ts` does.

## Consequences

A route's server bytes follow the blocks it lists. Moving the remaining pages onto sets is
one import change per feature module plus a `gen.serverBlocks` entry, and each move lowers
the baseline. Two servers have two session memos, so a feature module must import one of
them. Revisit if a page needs blocks from two sets.
