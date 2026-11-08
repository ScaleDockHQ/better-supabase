# 0480: Keep the data client out of the sign-in routes and load heavy UI on first use

- Status: accepted
- Date: 2026-11-08
- Amends: 0232, 0310

## Context

The Next.js example's root layout wrapped every route in `Providers`, which built
the browser client (`clientApp`, the data engine, `@supabase/auth-js`, realtime,
storage, postgrest) and a TanStack `QueryClient`. The sign-in form calls a server
action, so `/login` shipped about 650 KB of JavaScript it never ran. The
assistant route shipped the Markdown renderer, shiki, the HTML parser and
json-render before any answer existed, and every app route shipped Base UI's menu,
the session hooks and sonner for UI the visitor had not opened.

Architecture invariant 1 and ADR 0232 keep block code out of the browser client;
this ADR keeps the client itself out of routes that do not run hooks.

## Decision

- `app/providers.tsx` keeps `NuqsAdapter` and `TooltipProvider`. The client and
  the query cache move to `app/data-providers.tsx`, rendered by the `(app)`
  layout, the OAuth consent page and the islands page.
- A form that calls Auth from the browser awaits `loadBrowserClient()`
  (`lib/supabase/load-client.ts`) on submit: sign-up, forgot-password,
  reset-password and the MFA challenge.
- The toaster mounts after the first paint (`components/ui/lazy-toaster.tsx`),
  and files outside the published recipes call `lib/toast.ts`, which imports
  sonner on the first toast. Recipe files keep `import { toast } from "sonner"`
  because the docs show them as written.
- The account and organization menus render a closed trigger and load Base UI's
  menu, the hooks and the create dialog on the first hover, focus or click
  (`components/lazy-on-intent.tsx`). A click before the code arrives opens the
  menu once it mounts.
- The assistant loads the Markdown renderer behind `MessageTextLazy` (plain text
  until it arrives) and json-render behind `SpecViewLazy`.
- Both lazy wrappers render `<Suspense>` inside a feature, so
  `scripts/app-architecture-allow.json` lists them with the reason.
- `tests/next-build` measures the nomodule polyfill bundle as its own baseline
  entry (it was charged to every route), and two tests keep the data engine out
  of the sign-in routes and the Markdown renderer out of the assistant's first
  load.

## Alternatives considered

- Wrap only the sign-in routes in a lighter provider. Rejected: the exclusion
  list would grow with every public route, while `(app)` is one layout.
- Drop `ai` and `@ai-sdk/gateway` from the chat by replacing the transport. Not
  done: `@ai-sdk/react` imports `ai`, so a slim transport inside
  `better-supabase/ai-sdk/react` would still load it through `useChat`. It needs a
  library API change (a chat hook that does not use `@ai-sdk/react`), recorded
  below.
- Split `better-supabase/blocks/*` so a table page ships fewer block modules.
  Not needed: the manifests are `/* @__PURE__ */` and tree-shake already; the
  remaining block code in `/customers` is `createOrganizations` and the
  transports the hooks call.
- Lazy-load the durable chat panel. Tried and reverted: the analyzer reported a
  larger first load because the chunker moved shared `ai` modules into the
  synchronous chunks.

## Consequences

First load per route is held in `tests/next-build/baseline.json`; login and
sign-up drop 45%, the assistant 34%, other app routes 4% to 12%. A route that
renders a recipe component still carries sonner. Reset-password now creates the
client on submit, so the code exchange waits for that first call.

Left for a library change: a chat hook without `@ai-sdk/react`, and a
`realtime: false` option for `createClient` so `@supabase/realtime-js` and
`@supabase/phoenix` (57 KB raw) stay out of pages with no live data.
