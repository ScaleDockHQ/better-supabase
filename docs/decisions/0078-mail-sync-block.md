# 0078: Sync member mailboxes into engagements through a versioned mail provider

- Status: accepted
- Date: 2026-10-22

## Context

A CRM shows the mail a rep exchanged with a contact on the contact's record,
and lets the rep reply from there. Gmail and Outlook grant mailbox access per
person through OAuth, so every member connects their own mailbox, and the
token belongs to that member, not to the organization. Invariant 1 rules out
a provider SDK in the core, and ADR 0036 asks that any SDK a block uses is an
optional peer with a tested range. The engagements block already models a
logged email on one or more records, and the messaging core (ADR 0062) models
conversations between members, not mail with outside parties.

## Decision

Add a `mail-sync` block (`src/sql/modules/mail-sync.ts`,
`src/blocks/mail-sync/`, subpath `better-supabase/blocks/mail-sync`). It owns
four tables: `mail_accounts` (one per member and address, with a
`credential_ref` and a sync cursor), `mail_threads`, `mail_messages` and
`mail_thread_subjects`. Each thread logs one engagement of type `email`
(the `engagementType` option) and links it to the people whose addresses
appear in the thread and, with `matchDomains`, to the companies whose domain
matches. A record's mail is read through `mail_threads_of`, which hides
threads from private mailboxes from everyone but their owner.

Providers implement `MailProvider` at `apiVersion: 1` (list a page of
messages after a cursor, send a draft or a reply). The block ships
`gmailMail()` and `outlookMail()` over `fetch` against the Gmail API and
Microsoft Graph, so there is no SDK and no new optional peer. Tokens come
from the app's `CredentialProvider` (`vercelConnectCredentials()`,
`vaultCredentials()` or its own), called with the mailbox owner as the
subject, so the block never stores a token. `syncDue()` runs from the
service role on a cron, and `send()` records the sent message on its
thread. Data lifecycle purges a member's mailboxes and revokes their
credential reference.

Open and click tracking is opt-in through `tracking: { url }`. `send()`
rewrites the HTML body's links to `<url>/c/<token>/<n>` and adds a pixel at
`<url>/o/<token>`; the token is 32 random bytes, and the database stores only
its SHA-256 (`mail_messages.tracking_hash`) next to the original HTML and the
links (`mail_tracked_links`). The public route calls `track_mail` as the
service role, which counts the hit in `mail_tracking_events`, on the message
and on the link, and writes `mail_message.opened` (first open) or
`mail_message.clicked`. A sent message keeps the `template_version_id` it was
written from, and `mail_template_stats` counts sent, opened, clicked and
replied messages per version over the mailboxes the caller can read.

## Alternatives considered

- Mail as a messaging channel kind. Messaging threads are member
  conversations with read state and membership; outside senders and
  provider ids don't fit them, and the CRM already reads engagements.
- Organization-wide connectors for mailbox access. Gmail and Outlook
  grant one mailbox per user, and an admin-wide grant needs domain-wide
  delegation that most customers won't approve.
- Tracking URLs signed with an app secret, or the message id in the URL.
  A signature needs a key in every runtime that serves the route, and a
  bare id lets anyone count opens for any message; a random token whose
  hash is stored needs neither.
- The Gmail and Graph SDKs as optional peers. Two REST endpoints each don't
  justify an SDK, and `fetch` keeps the block on every WinterTC runtime.

## Consequences

Any app that already logs engagements gets mail on its records without a
new timeline. Another mail host is one more `MailProvider`. The block has no
UI recipe yet, and it isn't in the `crm` preset because it needs OAuth
setup; the `everything` preset includes it. Sequences (the next CRM block)
send through `send()` and stop on a reply that `syncDue()` stores. Open
counts are approximate (blocked images hide opens; image proxies and link
scanners add some), so tracking reports trends per template rather than
proof that one person read a message.
