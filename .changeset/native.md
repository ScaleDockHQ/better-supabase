---
"better-supabase": minor
---

Expo and React Native get a server adapter, a native client, local SQLite executors and push notifications.

- `better-supabase/expo`: `createExpo(betterSupabase)` gives Expo Router loaders, API routes and `+middleware.ts` the verified caller; `better-supabase init expo` writes it.
- `better-supabase/client/native`: `createNativeClient(betterSupabase, supabase)` binds repositories without `@supabase/ssr`, `secureStorage` and `largeSecureStorage` keep sessions in the keychain, and `autoRefreshOnForeground`, `syncQueryWithApp`, `persistQueryCache`, `uploadFromUri` and `handleAuthDeepLink` cover the app lifecycle. `better-supabase/react/native` adds `useOAuth`, `useAuthDeepLinks`, `useProtectedRoute` and `AuthGate`.
- `better-supabase/powersync`: `powersyncExecutor(db)` runs the same repositories on PowerSync's SQLite, `createUploadConnector` replays queued changes and `syncWithAuth` clears data on a user change; `/powersync/react` adds `useWatch`, `useSyncStatus` and `useConflicts`. `better-supabase/expo-sqlite` adds `expoSqliteExecutor(db)`.
- The `push` module and `better-supabase/blocks/push` store device tokens and send through the Expo Push API (`registerDevice`, `expoPush`, `expoPushChannel`).
