# 0646: Pick message namespaces per route and precompile ICU messages

- Status: accepted
- Date: 2026-11-10
- Amends: 0480, 0481

## Context

The Next.js example gave every route the whole message catalog: `NextIntlClientProvider` in the root
layout serialized all 18,000 messages into the RSC payload. The prerendered `/login` page carried
133,027 bytes of RSC (51,198 gzip) and 164,085 bytes of HTML (55,770 gzip), almost all of it
messages the sign-in form never reads. The audit measured this and left it open because a missed
namespace shows a raw key to the visitor.

## Decision

**Per-route namespaces.** The next-intl docs list "providing individual messages" as the way to send a
client subtree only what it reads: wrap it in a `NextIntlClientProvider` and give it a subset of
`useMessages()`. The example does that and nothing more. The root layout renders
`<NextIntlClientProvider messages={null}>`, `(app)` hands its shell `APP_NAMESPACES`, `(auth)` and
`(public)` hand `offline`, and a segment layout exists only where its pages read a namespace the group
lacks (`crm` adds `crm` and `sequences`). Each of those layouts calls the 10-line `pick` in
`src/i18n/namespaces.ts` on `useMessages()`. A nested provider replaces its parent's messages, so a
segment lists the group's namespaces too (`[...APP_NAMESPACES, "crm"]`). Server components keep
reading the full catalog through `getExtracted` and `useExtracted`; only `"use client"` files need a
namespace in a provider. An earlier draft wrapped this in a `RouteMessages` component and a layout
per segment; the docs show neither, and segments with no extra namespace needed no layout.

**A test that fails on a missing namespace.** `tests/i18n/route-namespaces.test.ts` walks the
imports of every route file, follows the ones reached from a `"use client"` file, collects the
`useExtracted("<namespace>")` calls and fails when the nearest `NextIntlClientProvider` at or above
the file omits one. The failure names the file, the namespace and the layout to edit. Dynamic
namespaces are not supported: `useExtracted` takes a string literal.

**ICU precompile.** `experimental.messages.precompile` is on. next-intl compiles each message at
build time, so the browser no longer ships the ICU parser. This pays on every route, unlike the
namespaces, which only help routes that render the catalog.

## Measured

| File                | Before (raw / gzip) | After (raw / gzip) |
| ------------------- | ------------------- | ------------------ |
| `en/login.html`     | 164,085 / 55,770    | 33,238 / 7,661     |
| `en/login.rsc`      | 133,027 / 51,198    | 16,538 / 5,203     |
| `en/customers.html` | 25,289 / 5,253      | 25,219 / 5,241     |
| `en/projects.html`  | 25,104 / 5,296      | 25,034 / 5,287     |

The first load of the routes in `tests/next-build/baseline.json` drops by 30,985 raw bytes (8,108
gzip, 7,744 brotli) each, from the precompile. The `(app)` shells never carried the catalog, so
their HTML moves by 70 bytes. The server baseline moves by the registration code of the new layouts,
inside its slack.

## Consequences

- A new client component that reads a new namespace fails the test until its layout lists it.
- Moving a page to another segment means moving its namespace with it; the test says which.
