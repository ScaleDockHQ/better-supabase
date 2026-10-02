---
"better-supabase": minor
---

Breaking: the `BetterResultShape` type is now `BetterResultValue`. It is still the type `toBetterResult` returns, with the `status`, `value` and `error` fields of a better-result value; rename the import to upgrade.
