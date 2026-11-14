# 0979: Add inbox admin tools and channel webhooks to the example

- Status: accepted
- Date: 2026-11-14

## Context

The example inbox had no screen for broadcasts, webhook replay, mentions in
internal notes or team-queue assignment (EX-403), and no route for a real
WhatsApp or Slack account (EX-404). The Help sheet and `/chat` still rendered
hand-rolled bubbles (EX-030, EX-422). Selecting a chat channel also failed,
because `PresenceAvatars` called `useSession`, which needs a provider the app
shell does not wrap around pages.

## Decision

Two lazy admin sheets under `inbox.manage` cover broadcasts (open conversations
of an inbox, WhatsApp conversations outside the 24 hour window skipped) and
webhook events (a list of `inbox_inbound_events` with a Replay button that sets
the status to failed with no delay, so the next `maintain` run retries it). The
conversation header assigns a team queue, and the note composer mentions
members. The contact name links to the CRM person.

`POST /api/webhooks/channels/[adapter]?inbox=<uuid>` verifies the WhatsApp or
Slack signature with Web Crypto and hands the request to the chat-sdk `webhook`
helper, which stores it for replay. It answers 503 without its secret.
`PresenceAvatars` reads the user from `useAuth`. The Help sheet and `/chat` use
`MessageScroller`, `Message`, `Bubble` and `Marker`. No library or migration
change.

## Alternatives considered

Adding `@chat-adapter/whatsapp` and a Slack adapter now: neither can be run or
verified without accounts, so delivery stays on the simulator.

## Consequences

EX-404 stays deferred. A maintainer sets `WHATSAPP_APP_SECRET`,
`WHATSAPP_VERIFY_TOKEN` and `SLACK_SIGNING_SECRET` in the three Vercel
environments, registers the webhook URL with each provider and adds the adapter
packages for delivery.
