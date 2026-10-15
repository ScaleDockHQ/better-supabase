# 0030: Keep block client state in headless controllers behind ports

- Status: accepted
- Date: 2026-10-15

## Context

Fourteen blocks had a `/react` entry whose hook kept its state in
`useState` and `useEffect`. Vue, Svelte and Solid apps got nothing from
them, and React Native got them only where nothing touched the DOM:
`useCommandSearch` added a `keydown` listener to `window`, and
`useInboxWidget` read `localStorage`. Plan 003 (workstream 4) asks for one
headless controller per block, shared by every binding, with the web and
React Native apps differing only in their markup.

## Decision

Each of those blocks has a `src/blocks/<name>/client.ts` that exports
`create<Name>Controller`. A controller is built with `defineController`
(`src/blocks/controller.ts`) and has `subscribe`, `getSnapshot`, `actions`
and `dispose`. Its work starts with the first subscriber and stops with the
last, so `useSyncExternalStore`, React's StrictMode remount and a Svelte
store need no extra lifecycle. `whileSignedIn` reruns a controller's loads
and realtime joins for each signed-in user.

Controllers reach the platform only through ports (`src/client/ports.ts`):
the realtime topic (`watchTopic` moved to `src/realtime/watch-topic.ts`),
storage, the keyboard, file picking and upload, the push token and deep
links. The client carries them in `bs.ports`: `createClient` from
`better-supabase/client` fills the web defaults (`src/client/web-ports.ts`),
and a React Native app passes `nativePorts()` from
`better-supabase/client/native`, which takes the Expo modules structurally
and imports none of them. Each `/react` hook is a `useSyncExternalStore`
wrapper over its controller, and the `react-server` stubs stay.

Controllers are exported from each block's main entry; no new subpath.
`tests/blocks/platform-neutral.test.ts` walks every controller's and every
`/react` entry's import closure and fails on `window`, `document` or a
`react-native` import, and on React in a controller.

## Alternatives considered

- A `/client` subpath per block. It would add fourteen entries to the
  exports map and size baselines for code that tree-shakes from the block
  entry, which already runs on every runtime.
- Platform checks inside the hooks (`typeof window`). They keep React Native
  working but leave Vue and Svelte without a shared state model, and every
  new platform need becomes another branch in every hook.
- Ports passed to each hook as options. The ports describe the platform,
  not the call, so they belong on the client the provider already holds.

## Consequences

A Vue, Svelte or Solid binding is a few lines over a controller, and a
controller test needs fake ports instead of a renderer. A block hook that
needs a new platform service adds a port, a web default and a native
default. The regex in the static check sees names, not scopes: neutral code
does not name a local `window` or `document`.
