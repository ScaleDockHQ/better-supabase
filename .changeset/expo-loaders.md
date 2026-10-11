---
"better-supabase": patch
---

`bs.loader()` without a request now names `createStaticLoader` from `expo-server` and the SDK 57 `unstable_useServerRendering` option. The Expo docs say which `app.json` options SDK 57 needs and that SDK 58 needs none, and show how to call `bs.request` inside `createServerLoader` or wrap `bs.loader`, which is an `expo-server` `LoaderFunction`.
