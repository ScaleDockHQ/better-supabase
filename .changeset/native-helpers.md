---
"better-supabase": minor
---

Add React Native and Expo helpers.

- `better-supabase/client/native`: `syncQueryWithApp` connects TanStack Query's focus and online managers to `AppState` and NetInfo. `largeSecureStorage` stores sessions of any size, encrypted with AES-GCM, with only the key in the keychain. `persistQueryCache` is a throttled TanStack Query persister over MMKV or AsyncStorage. `uploadFromUri` uploads a picked file URI to a typed bucket. `handleAuthDeepLink` and `signInWithOAuthBrowser` finish sign-ins from deep links and `expo-web-browser`.
- `better-supabase/react/native` (new subpath): `useOAuth`, `useAuthDeepLinks`, `useProtectedRoute` and `AuthGate`.
- `escapeLike` moved to its own module, so `better-supabase/query` and `better-supabase/react` no longer bundle the query builder.
