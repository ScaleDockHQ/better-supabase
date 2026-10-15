# 0030: Keep block client state in headless controllers with thin framework bindings

- Status: accepted
- Date: 2026-10-15

## Context

Fourteen blocks ship a `/react` entry (ai-chat, announcements, bookings,
calendar, forms, inbox, notifications, onboarding, reactions, saved-views,
search, undo, workflows and workflow-builder). Each keeps its state in
`useState` and `useEffect`, so the logic exists only for React: Vue, Svelte
and Solid apps get nothing, React Native gets the hooks by accident, and
`blocks/search/react/index.ts` listens on `window`, which breaks on native.
The package already has framework entries (`src/vue`, `src/svelte`,
`src/solid`) and a realtime topic helper (`watchTopic` in
`src/blocks/react-topic.ts`) that does not need React.

A web app and its React Native app should share everything except markup.

## Decision

Each block with client state gets one framework-agnostic controller in
plain TypeScript, `src/blocks/<name>/client.ts`, created by
`create<Name>Controller(options)`. It holds the state, the actions,
realtime through the topic port, optimistic updates and pagination, and
follows the external-store contract (`subscribe`, `getSnapshot`, `actions`,
`dispose`). It imports no React, no DOM and no React Native. What a
platform provides goes through small injected ports: realtime topic,
storage, keyboard shortcuts, file pick and upload, push token, deep links
and clipboard. The default ports live in `better-supabase/client` (web) and
`better-supabase/client/native` (Expo).

Bindings are thin wrappers over the controller:

| Binding                | Entry                                              |
| ---------------------- | -------------------------------------------------- |
| React (web and native) | `better-supabase/blocks/<name>/react`              |
| React Native extras    | `better-supabase/blocks/<name>/react/native`       |
| Vue, Svelte, Solid     | `better-supabase/blocks/<name>/{vue,svelte,solid}` |

The React binding uses `useSyncExternalStore`, so the same hook runs in
React DOM and React Native, and the `react-server` stub stays. The native
extras entry exists only where a port needs a native default, such as push
or file pick. The Vue, Svelte and Solid bindings are generated wrappers
(`shallowRef`, a readable store, `from`).

The fourteen existing hooks move their state into controllers, and their
signatures change where the controller allows a cleaner API, with the
examples and recipes updated in the same commit. Controllers are unit-tested
once with fake ports; one conformance suite
(`src/testing/kits/controller-binding.ts`) runs against every binding; a
static check like the WinterTC one fails when a controller or a `/react`
entry references `window`, `document` or `react-native`.

## Alternatives considered

- **Keep React hooks and port each one per framework.** Five copies of the
  same state logic drift, and React Native still depends on what a hook
  happens to touch.
- **A state library (XState, Zustand, nanostores) as the controller.** It
  would be a new runtime dependency of the core (invariant 1) or an
  optional peer every block needs. The external-store contract is enough
  for every binding.
- **Ship native components.** We ship no visible UI at all (ADR 0031); the
  controller is what the web and native markup share.

## Consequences

One implementation serves every framework, React Native gets the same
hooks as the web, and the recipes show the same hook call on both
platforms. Each block with client state gains a `client.ts` and up to four
small binding entries, so the subpath list, size baselines and export
snapshot grow. Revisit if a framework's reactivity can't be expressed over
`subscribe` and `getSnapshot` without losing updates.

## Implementation

The controllers are built with `defineController`
(`src/blocks/controller.ts`): the first subscriber starts a controller's
work and the last one to leave stops it, so a StrictMode remount needs no
extra lifecycle. `whileSignedIn` reruns loads and realtime joins for each
signed-in user. Controllers are exported from each block's main entry
rather than from a `/client` subpath, since that entry already runs on every
runtime and tree-shakes.

The ports (`src/client/ports.ts`) travel on the client as `bs.ports`.
`createClient` fills the web defaults (`src/client/web-ports.ts`, typed
structurally so apps without the DOM lib still compile `better-supabase/client`),
and `nativePorts()` from `better-supabase/client/native` builds the React
Native ones from Expo modules the app passes in, importing none of them.
`watchTopic` moved to `src/realtime/watch-topic.ts` and is exported with
`topicPort` from `better-supabase/realtime`; the topic port defaults to
`topicPort(bs.supabase)`. Clipboard has no port yet: no controller needs it.

The static check is `tests/blocks/platform-neutral.test.ts`. It reads names,
not scopes, so neutral code doesn't name a local `window` or `document`.
The Vue, Svelte and Solid bindings and the binding conformance kit come
with workstream 4b.
