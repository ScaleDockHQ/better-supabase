import type { CloudEvent, EventSink } from "../../events/cloud-event.ts";
import type { DriveAccess } from "./ownership.ts";

import { stripTypePrefix } from "../../events/cloud-event.ts";
import { isRecord, optionalText } from "../shared.ts";

const OFFBOARDING = new Set([
  "employee.offboarded",
  "organization.member_removed",
]);

export interface DriveOffboardingSinkOptions {
  /**
   * The member who takes over the leaving member's items, such as their manager
   * or the organization owner. Return `undefined` to leave the items where they
   * are.
   */
  readonly transferTo: (
    event: CloudEvent,
  ) => string | undefined | PromiseLike<string | undefined>;
  /** Stripped from each event type. Defaults to `dev.better-supabase`. */
  readonly typePrefix?: string;
  /**
   * Called with the drives that stayed with the leaving member because the new
   * owner can't own them, such as a second personal drive. Archive or reassign
   * them here. Without it the sink logs a warning.
   */
  readonly onKept?: (
    event: CloudEvent,
    keptDriveIds: readonly string[],
  ) => void | PromiseLike<void>;
}

/**
 * An outbox sink that hands a leaving member's drive items to another member
 * when an employee is offboarded or a member is removed: `outbox.relay('drive',
 * driveOffboardingSink(drive, { transferTo }))`. Build `drive` with a service
 * transport. A redelivered event moves nothing, since the leaving member no
 * longer holds the items.
 */
export function driveOffboardingSink(
  drive: Pick<DriveAccess, "transferOwnership">,
  options: DriveOffboardingSinkOptions,
): EventSink {
  return {
    async send(events) {
      for (const event of events) {
        if (
          !OFFBOARDING.has(stripTypePrefix(event.type, options.typePrefix)) ||
          !isRecord(event.data)
        ) {
          continue;
        }

        const organizationId = optionalText(event.data["organizationId"]);
        const userId = optionalText(event.data["userId"]);

        if (organizationId === undefined || userId === undefined) {
          continue;
        }

        const toUserId = await options.transferTo(event);

        if (toUserId === undefined || toUserId === userId) {
          continue;
        }

        const moved = await drive.transferOwnership({
          organizationId,
          fromUserId: userId,
          toUserId,
        });

        if (!moved.ok) {
          throw new Error(
            `driveOffboardingSink: moving ${userId}'s items failed: ${moved.error.message}`,
          );
        }

        const kept = moved.data.keptDriveIds ?? [];

        if (kept.length > 0 && options.onKept !== undefined) {
          await options.onKept(event, kept);
        } else if (kept.length > 0) {
          console.warn(
            `driveOffboardingSink: ${userId} keeps drives ${kept.join(", ")} that ${toUserId} can't own`,
          );
        }
      }
    },
  };
}
