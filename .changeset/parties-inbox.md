---
"better-supabase": minor
---

With the inbox module installed, the parties module links inbox contacts to people. `personForInboxContact(contactId)` returns the linked person, links the person with the contact's email when there is none, and with `create: true` saves an unknown contact as a new lead. `linkInboxContact` and `unlinkInboxContact` change the link by hand.
