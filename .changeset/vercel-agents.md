---
"better-supabase": minor
---

Agents on Supabase with Vercel Sandbox, Connect and the Chat SDK.

- `supabaseAccess` and `supabaseAccessFrom` in `better-supabase/vercel-sandbox` build a sandbox
  network policy that reaches only your Supabase project, as one user. The firewall adds the token,
  so code in the sandbox never holds it. They refuse a service role key.
- `connectEventRoute` and `postgresConnectEventSubscriptions` in `better-supabase/vercel-connect`
  verify Connect and MCP event deliveries and write each one to the outbox once, with
  subscriptions in a `connect_event_subscriptions` table you create.
- `connectAuth` in `better-supabase/eve` wraps `connect` from `@vercel/connect/eve` with the same
  Connect subject as `vercelConnectCredentials`.
- `chatHistory` and `eraseChatHistory` in `better-supabase/chat-sdk` key the Chat SDK's user history
  by the linked app user and erase it by user.

Upgrade: nothing breaks. To receive Connect events, create the table from the Connect events docs
page and mount the route.
