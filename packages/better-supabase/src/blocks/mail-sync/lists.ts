import type { EntityListSurface } from "../../core/entity-list.ts";

/**
 * What `threadPage`, `threadFacets` and `threadCount` accept for a mail thread
 * (ADR 0749, 1077). The manifest declares the same names, and the SQL list
 * function `page_mail_threads` implements them. `subjectType` and `subjectId`
 * are scalar filters (a list of one) for the records a thread is linked to.
 */
export const mailThreadListSurface: EntityListSurface = {
  sorts: ["lastMessageAt", "subject", "messageCount"],
  facets: ["accountId"],
  filters: ["accountId", "subjectType", "subjectId"],
  search: ["subject", "snippet"],
};

/**
 * What `accountPage`, `accountFacets` and `accountCount` accept for a mailbox.
 * The SQL list function is `page_mail_accounts`; it runs as the caller, so a
 * member sees their own mailboxes and `mail_sync.manage` sees every member's.
 */
export const mailAccountListSurface: EntityListSurface = {
  sorts: ["address", "createdAt"],
  facets: ["status", "provider", "share"],
  filters: ["status", "provider", "share", "userId"],
  search: ["address"],
};
