---
"better-supabase": minor
---

Add `better-supabase/expo` for Expo Router on the web: `createExpo(betterSupabase)` gives server loaders (`bs.loader`), API routes (`bs.handler`) and `+middleware.ts` (`bs.middleware`) the verified caller, reading a bearer token first and the session cookie second, and writes refreshed session cookies with `expo-server`'s `setResponseHeaders`. It verifies tokens locally and never calls `getSession()`. `better-supabase init` adds it for Expo projects, with a native client and `lib/supabase/expo.ts`.

Add `better-supabase/client/native` for React Native: `createNativeClient(betterSupabase, supabase)` binds repositories, query options and the auth store to a supabase-js client you create, without loading `@supabase/ssr`, and `secureStorage(SecureStore)` keeps the session in the device keychain in chunks small enough for `expo-secure-store`. `better-supabase/client` also exports `bindClient` for the same purpose.
