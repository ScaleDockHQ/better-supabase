---
"better-supabase": minor
---

Chats can be shared with teams, customers and external people, and by a live link that you can rotate. The `ai-chat` SQL module moves from version 5 to 6, so run `better-supabase upgrade`.

- Visibility is now `private` (the owner only), `organization` or `shared` (the owner, participants, members of participating teams and the live link). Adding a participant to a private chat makes it `shared`, and the upgrade moves private chats that have participants to `shared`. An organization member who is not a participant can't read a shared chat.
- `ai_chat_participants` gets a surrogate `id` and a `kind` (`user`, `team`, `customer`, `external`) with the columns `team_id`, `customer_user_id` and `email`; the upgrade backfills `kind = 'user'`. `AiChatParticipant.userId` is now `string | undefined` and `list` returns the owner first with the role `owner`.
- New `participants.addParty` and `removeParty`, `links.create`, `rotate`, `revoke` and `get` (a new `ai_chat_links` table and the SQL functions `add_ai_chat_party`, `remove_ai_chat_party`, `create_ai_chat_link`, `rotate_ai_chat_link`, `revoke_ai_chat_link` and `get_ai_chat_by_link`), and `chats.shareSummaries(ids)`.
- The new `teamMembership` option names the function `(team uuid, user uuid) returns boolean`. It defaults to the teams module's members when that module is installed.
- Chats take an optional `mode` column on `create` and `update`.
