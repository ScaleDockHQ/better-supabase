---
"better-supabase": minor
---

`expectInstant(page, { during, visible, absent, maxCalls, maxWaves, baseURL })` in `better-supabase/testing` runs a navigation inside `@next/playwright`'s `instant()`, checks that each `visible` locator shows and each `absent` locator matches nothing while the lock holds, and with `maxCalls` or `maxWaves` checks the navigation's database budget as `expectDbBudget` does. `@next/playwright` is a new optional peer that only `expectInstant` loads.

`expectDbBudget` no longer waits out `timeoutMs` for a streamed response the browser aborts, because Playwright's `response.finished()` never settles for one; a failed request now ends the wait. `BudgetPage` takes `requestfailed` listeners for this, which a Playwright `Page` already does.

`autoRefreshOnForeground(supabase, AppState)` in `better-supabase/client/native` starts supabase-js's token refresh while a React Native app is active and stops it in the background, as Supabase asks React Native apps to do. It returns a function that removes the listener and stops refreshing. `AppState` is typed by its shape, so better-supabase still never imports `react-native`. `better-supabase init expo` now writes the call into the native client file.
