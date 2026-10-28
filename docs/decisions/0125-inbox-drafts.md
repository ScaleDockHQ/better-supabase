# 0125: Inbox reply drafts per staff member, and AI drafts for the whole team

- Status: accepted
- Date: 2026-10-28

## Context

An inbox reply lived only in the composer's state, so a reload or a switch
to another device lost it. Apps that let a model propose replies stored the
proposal in their own table and copied it into the composer, with no shared
way to show it to the staff who can answer or to record that it was sent.

## Decision

`inbox_drafts` keeps a draft per conversation with a source (`user` or
`ai`), a status (`draft`, `sent`, `discarded`), the message input as jsonb
and the draft's own metadata. A staff member has at most one open `user`
draft per conversation (a partial unique index), which `upsert` replaces.
The service role files `ai` drafts without an author through `suggest`;
every staff member who can reply on the conversation sees them. `send` posts
the draft through `send_inbox_message` as the caller, with edits over its
input, and marks it sent in the same transaction. The inbox block moves to
version 6.

## Alternatives considered

- Drafts in browser storage. Rejected: they don't follow the user across
  devices and the team can't see AI drafts.
- AI drafts as internal notes. Rejected: a note is a sent message in the
  thread; a proposal must stay out of the thread until someone sends it.

## Consequences

Sent and discarded drafts stay as rows; the data-lifecycle block's retention
covers them like other inbox rows.
