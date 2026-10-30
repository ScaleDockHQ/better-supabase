---
"better-supabase": minor
---

Block clients cover more of what apps wrote by hand:

- `webhooks-out` manages endpoints as the user with `createEndpoint`, `updateEndpoint`, `listEndpoints` and `deleteEndpoint`, checked against the module's manage and view permissions. The block SQL adds `create_webhook_endpoint`, `update_webhook_endpoint`, `list_webhook_endpoints` and `delete_webhook_endpoint` (module version 6); run `better-supabase upgrade`.
- Notifications `send` takes `{ email, name? }` recipients for contacts without an account. The email channel sends to them right away through `sendToContact`, with an optional `composeContact`, and the result reports each contact in `contacts`.
- Comments `list` takes `includeDeleted: false` to leave deleted comments out in the database. `list_comments` gains an `include_deleted` argument (module version 9); the upgrade drops the old signature.
- `viewOf` from `better-supabase/blocks/saved-views` and `subscriptionOf` from `better-supabase/blocks/notifications` parse rows from a page payload RPC the way the clients do.
