---
"better-supabase": minor
---

`createServer(betterSupabase, { authorization })` takes `AuthorizationHooks` (`defineAuthorizationHooks` from `better-supabase/server`): optional `automation`, `support`, `delivery`, `identities`, `chat`, `approverOf` and `tickets` hooks, so one authorization provider decides publishing, support sessions, fan-out, identity links, chat actions, approvals and run tickets. `testAuthorizationHooks` from `better-supabase/testing` checks that they fail closed.

The `authorization` config gains `functions.isApprover` (`{kind}`, `{subject}`, `{tenant}`), `functions.permitted` for checks on one instance, and `operations`, one table of the permission each workflow node, MCP tool, AI tool and inbox command needs.

Breaking: with `authorization` set, `blocks.access.model` defaults to `provider`, so `can()`, `tenant_ids_with()` and every module check answer from the provider. Set `model: "roles"` to keep the built-in roles; doctor BS414 then reports policies and functions that call the access contract. `functions.canApprove` is deprecated in favour of `isApprover` and still read when `isApprover` is unset; doctor BS415 warns while a provider sets it, and `better-supabase codemod 0.9` lists each use.
