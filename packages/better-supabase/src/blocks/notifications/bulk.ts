import type { BulkCallOptions, BulkReport } from "../../core/bulk.ts";
import type { AsyncResult, Result } from "../../core/result.ts";
import type {
  NotificationBulkAction,
  NotificationUpdate,
} from "./api-types.ts";

import { bulkOfSet } from "../../core/bulk.ts";
import { ok } from "../../core/result.ts";

const FUNCTIONS = {
  read: "mark_notifications_read",
  unread: "mark_notifications_unread",
  dismiss: "dismiss_notifications",
} as const satisfies Record<NotificationBulkAction, string>;

/**
 * `notifications.bulk` over the set functions (ADR 1030): an id the function
 * did not return is `not_found`, because it is missing, not the caller's or
 * already in that state.
 */
export function notificationsBulk(
  update: (
    fn: string,
    args: Readonly<Record<string, unknown>>,
  ) => PromiseLike<Result<NotificationUpdate>>,
  ids: readonly string[],
  action: NotificationBulkAction,
  options: BulkCallOptions & { readonly tenant?: string } = {},
): AsyncResult<BulkReport> {
  return bulkOfSet(
    ids,
    async (unique) => {
      const result = await update(FUNCTIONS[action], {
        ids: [...unique],
        ...(action === "dismiss" ? {} : { tenant: options.tenant ?? null }),
      });

      if (!result.ok) {
        return result;
      }

      const changed = new Set(result.data.items.map((item) => item.id));

      return ok({
        ids: unique.filter((id) => changed.has(id)),
        skipped: unique.filter((id) => !changed.has(id)),
      });
    },
    options,
  );
}
