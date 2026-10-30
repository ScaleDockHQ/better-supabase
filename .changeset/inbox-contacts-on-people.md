---
"better-supabase": minor
---

Inbox contacts are now people of the contacts block (ADR 0131). The inbox requires `contacts`, a conversation's `contactId` is a person id, and the inbox `contacts` and `contact_identities` tables and the `person_inbox_contacts` link are gone. A person's addresses on channels live in the new `person_identities` table (`person_id`, `channel`, `address`, `verified_at`), and `people` gains `avatar_url` and `metadata`. `upgrade` renders a data step that turns each inbox contact into a person (the linked one, else the active person with the same email, else a new person with the contact's id), copies the identities, points conversations and identity links at the person, then drops the old tables. Run `better-supabase add contacts` before `upgrade`.

The contacts client gains `identities(personId)`, `addIdentity`, `removeIdentity` and `findByIdentity`, and drops `linkInboxContact`, `unlinkInboxContact` and `personForInboxContact`:

```ts
// Before
const person = await db.contacts
  .personForInboxContact(conversation.contactId, { create: true })
  .orThrow();

// After
const person = await db.contacts
  .findByIdentity(organizationId, "whatsapp", "+31612345678")
  .orThrow();
await db.contacts
  .addIdentity(personId, { channel: "whatsapp", address: "+31612345678" })
  .orThrow();
```

`inbox.contacts.upsert` still finds or creates the person and is deprecated until 0.48. Deleting a user no longer erases their inbox contact; `purgeContact(personId)` erases the person and their conversations. `codemod 0.47` lists the old calls and tables, and doctor reports the removed methods. See the 0.46 to 0.47 guide.
