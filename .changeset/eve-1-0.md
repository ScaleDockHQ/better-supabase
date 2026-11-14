---
"better-supabase": minor
---

`better-supabase/eve` follows eve 1.0, and the `eve` peer range is now
`>=1.0.0-rc.0 <2` (`@vercel/connect` starts at 2.5.2). `persistSessions`
handles eve's version 27 session events: `delivery.consumed` stores the
user's text, `content.completed` stores each text part (a part outside the
reply is interim), and `turn.settled` sets the run's status from its outcome,
in place of `message.received`, `message.completed` and the three `turn.*`
endings. `credentialAuth` and `openApiAuth` return `principalType`, which eve
1.0 reads, instead of `credentialOwner`, so a user-owned connection keeps
per-user tokens. `EveApprovalResponseContext` names `request.interactionId`
and the `deny` decision, `EveApprovalStatus` takes the
`{ type: "not-applicable" }` and `{ type: "user-approval" }` forms, and
`EveMemoryTool.inputSchema` is a JSON Schema object. See the 0.66 to 0.67
guide for the renames.
