---
"better-supabase": minor
---

`sessionStatus` returns `banned` when Auth rejects a token with `error_code: "user_banned"`, a rejected `refreshSession` outcome carries the Auth `code`, and the resolution reports `sessionEndedReason`. `bs.proxy({ endedSession })` redirects banned accounts with `reason=account_banned`; `endedSession.reasons` renames the `reason` values. `SessionStatus` gains `"banned"`, so a switch over it needs a case for the new value.
