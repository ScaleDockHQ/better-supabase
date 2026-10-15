---
"better-supabase": minor
---

Block hooks now wrap headless controllers, so they run in React DOM and React Native alike. Each block with a `/react` entry exports `create<Name>Controller` from its main entry (`createNotificationsController`, `createCommandSearchController` and the rest), with `subscribe`, `getSnapshot`, `actions` and `dispose`; the hooks are `useSyncExternalStore` wrappers over them.

Controllers reach the platform only through ports on the client, `bs.ports`: realtime topics (`topicPort` from `better-supabase/realtime`), storage, the keyboard, file picking and upload, push tokens and deep links. `createClient` from `better-supabase/client` fills the web ports (`webStorage`, `webKeyboard`, `webFilePicker`, `webDeepLinks`, `storageUpload`, and `webPushToken` on request), and `nativePorts()` from `better-supabase/client/native` builds the React Native ones from the Expo modules you pass to `createNativeClient(betterSupabase, supabase, { ports })`.

Breaking changes: `useCommandSearch` listens for Cmd+K through the client's keyboard port instead of `window`, so React Native has no shortcut. `useInboxWidget` keeps the conversation id in the storage port instead of `localStorage`, and reads it after the first render. `groupHits` and its types moved from `blocks/search/react/groups.ts` to `blocks/search/groups.ts` (still exported from `better-supabase/blocks/search/react`).
