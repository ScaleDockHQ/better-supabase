# 0483: Load header dialogs on intent, render the side navigation on the server and load the chat panel after paint

- Status: accepted
- Date: 2026-11-08
- Amends: 0480

## Context

After ADR 0480 every app route still shipped the Help sheet and the search dialog
with the inbox and search hooks (the header), the mobile sidebar drawer, a side
navigation that held about 100 icons and the label switch in a client
component, and the assistant routes shipped `ai`, `@ai-sdk/react`, the gateway
client and zod before a message existed.

## Decision

- The header renders `HelpSheetLazy` and `CommandSearchLazy`, closed triggers
  that load the sheet, the dialog and their hooks through `LazyOnIntent` on the
  first hover, focus or click. `LazyOnIntent` takes a `shortcut` option: Cmd+K
  or Ctrl+K loads the search code and is then sent to it, so the dialog opens.
- `Sidebar` loads its mobile drawer (`sidebar-mobile.tsx`) only on a narrow
  screen.
- `SideNav` is a server component. The icons, labels and groups render on the
  server (`nav-label-server.ts`), and `NavLink` is the client leaf that reads
  the pathname for the current page. The breadcrumbs keep the client label hook
  (`use-nav-label.ts`).
- The chat panel loads behind `AssistantChatLazy` with a skeleton of its height.
  This moves 341 KB raw off the first load of `/assistant`; the code still
  downloads right after, so it is deferral, not removal.
- `tests/first-load.spec.ts` holds the sign-in routes to 850000 decoded bytes
  of script, measured at 824406 (login) and 786462 (sign-up).

## Alternatives considered

- A server `CustomerTable`. Rejected: the row markup is also rendered for search
  results the API returns, so a server copy would duplicate it, and the whole
  customers feature is 4.5 KB raw on `/customers`.
- A chat hook without `@ai-sdk/react`. Not done: `useAssistant` returns
  `UseChatHelpers`, so it would reimplement `AbstractChat` and the UI message
  stream parser (ADR 0010 keeps AI blocks SDK-neutral and bridges each SDK in
  an adapter).
- A `realtime: false` option for `createClient`. Not done: `@supabase/supabase-js`
  imports and constructs `RealtimeClient` eagerly, so no option can drop it. It
  needs a client built from auth-js, postgrest-js, storage-js and functions-js
  with its own cookie storage, or an upstream lazy Realtime. Every `(app)`
  route also renders the live unread badge, so none could use it.
- Splitting `better-supabase/storage`. `lib/buckets.ts` pulls `defineBucket`,
  whose object carries `sql()`, `apply()` and the policy checks, about 28 KB raw
  (storage 21.5, access-sql 4.2, template 2.9) in every client route. A client
  entry without them is a new subpath and a library change; recorded for later.

## Consequences

Each app route drops about 28 KB raw from the side navigation and 5 to 30 KB
from the header and drawer; `/assistant` drops 341 KB raw. The loading-sequence
specs run against the native stack (`pnpm supabase:start`, `pnpm supabase:reset`,
`PLAYWRIGHT_BROWSERS_PATH` set to a directory with Chromium). The customers
sequences fail on `next start`, as they did before this branch: the list throws
`Cannot read properties of undefined (reading 'list')` while rendering
`useCustomerSearch`, because `queries.customers` is not registered.
