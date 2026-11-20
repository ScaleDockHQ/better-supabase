---
"better-supabase": minor
---

Add `strictestApproval(...policies)` to `better-supabase/eve`. It combines approval policy functions and `{ request, response?, prompt? }` configurations for one tool: the strictest request result wins and every `response` must allow the answer. `supabaseTool`, `eveContext` and `approvalPolicy` accept `permission`, a key or keys that join `scopes` in the agent's `scope` claim.
