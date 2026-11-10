import { createLoader, parseAsString, parseAsStringLiteral } from "nuqs/server";

import type { notificationTypes } from "./notification-types";

/** The types the type filter offers. */
const TYPES = [
  "test.sent",
  "workflow.message",
] as const satisfies readonly (keyof typeof notificationTypes)[];

/**
 * The notifications page's URL state. `before` is the keyset cursor of an older
 * page, `createdAt|id`.
 */
export const notificationSearchParams = {
  status: parseAsStringLiteral(["all", "unread"] as const).withDefault("all"),
  type: parseAsStringLiteral(TYPES),
  before: parseAsString,
};

export const loadNotificationFilters = createLoader(notificationSearchParams);

/** Items per page. */
export const NOTIFICATION_PAGE_SIZE = 20;
