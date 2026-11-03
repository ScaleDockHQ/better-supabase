# 0208: Share ai-chat with participants of four kinds and a rotatable live link

- Status: accepted
- Date: 2026-11-03

## Context

A chat with participants was `private` and still readable by them, so
`visibility` didn't say who could read. Sharing with a team, a customer or a
person without an account needed more than a `(chat, user)` key, and the
snapshot links in `ai_chat_shares` freeze one branch, so there was no link that
follows the conversation.

## Decision

- `visibility` is `private` (owner only), `organization` or `shared` (owner,
  participants, teams and the live link). Participants count only on a chat that
  isn't private. Adding a party to a private chat sets `shared`, and the version 6
  upgrade moves private chats that have participants to `shared`.
- `ai_chat_participants` has a surrogate `id` and a `kind` (`user`, `team`,
  `customer`, `external`), with one partial unique index per kind. A team reads
  through the membership function, evaluated at read time, so leaving the team
  ends access. A customer reads through guest access (ADR 0070). An external
  address reads only through the link.
- `ai_chat_links (chat, salt, created_by, rotated_at)` holds one salt per chat.
  The token is `<chat>.<sha256(salt || chat)>`, so rotating the salt invalidates
  every earlier token without storing a token. `get_ai_chat_by_link` is granted to
  `anon` and returns the active branch.
- The `teamMembership` option names an app function `(team uuid, user uuid)
  returns boolean`. It defaults to the teams module and otherwise adding a team
  raises.
- The new actions reuse the `share` permission instead of new permission keys.

## Alternatives considered

Separate tables per party kind: more policies and joins for no gain. Storing
the link token (hashed): rotating would need a new row and a lookup by hash;
the salt keeps one row per chat.

## Consequences

Sharing is one visibility value to reason about. The participant key changes,
which is why version 6 needs an upgrade step. An app that owns its participants
table adds the new columns itself, or it keeps user participants only. The
list `mode` filter and new `OPERATIONS` rows are left for later.
