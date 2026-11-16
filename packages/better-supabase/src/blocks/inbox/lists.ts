import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `conversations.page`, `conversations.facets` and `conversations.count`
 * accept (ADR 0749, 1077). The SQL list function `page_inbox_conversations`
 * implements them. `status` reads open conversations by default and every one
 * with `["all"]`; `assignee` takes one value (`me`, `unassigned` or an id).
 * `priority` takes `low`, `normal`, `high` or `urgent`. `sla` takes the first
 * response states `ok`, `due`, `breached` and `met`, judged against
 * `slaMinutes` (one value, 60 by default). `tagId` keeps the conversations
 * tagged with any of the tags and needs the tags block. `q` searches the
 * subject, the preview and the contact's name and email.
 */
export const conversationListSurface: EntityListSurface = {
  sorts: ["lastMessageAt", "createdAt"],
  facets: ["status", "inboxId", "priority", "sla"],
  filters: [
    "inboxId",
    "teamId",
    "contactId",
    "status",
    "assignee",
    "priority",
    "sla",
    "slaMinutes",
    "tagId",
  ],
  search: ["subject", "preview", "contact"],
};

/**
 * What `inboxes.page`, `inboxes.facets` and `inboxes.count` accept. The SQL
 * list function `page_inboxes` implements them. Archived inboxes are hidden
 * unless `archived` is `["true"]` (only the archived ones). `q` searches the
 * name and the address.
 */
export const inboxListSurface: EntityListSurface = {
  sorts: ["name", "createdAt"],
  facets: ["channel", "botMode"],
  filters: ["channel", "botMode", "archived"],
  search: ["name", "address"],
};

/**
 * What `templates.page`, `templates.facets` and `templates.count` accept. The
 * SQL list function `page_message_templates` implements them. `q` searches the
 * name and the body.
 */
export const templateListSurface: EntityListSurface = {
  sorts: ["name", "createdAt"],
  facets: ["channel", "language"],
  filters: ["channel", "language", "inboxId"],
  search: ["name", "body"],
};
