---
"better-supabase": minor
---

The invitations block adds `accepting_invitation()`, which returns the invitation that `accept_invitation` or `accept_invitation_by_id` is accepting while it inserts the membership or platform role, and null otherwise. Triggers on the membership table can read the invitation's `prefill` through it instead of matching on an email address.
