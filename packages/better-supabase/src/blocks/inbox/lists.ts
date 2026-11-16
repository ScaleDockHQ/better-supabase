import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `conversations.page`, `conversations.facets` and `conversations.count`
 * accept (ADR 0749, 1077). The SQL list function `page_inbox_conversations`
 * implements them. `status` reads open conversations by default and every one
 * with `["all"]`; `assignee` takes one value (`me`, `unassigned` or an id). `q`
 * searches the subject, the preview and the contact's name and email.
 */
export const conversationListSurface: EntityListSurface = {
  sorts: ["lastMessageAt", "createdAt"],
  facets: ["status", "inboxId"],
  filters: ["inboxId", "teamId", "contactId", "status", "assignee"],
  search: ["subject", "preview", "contact"],
};
