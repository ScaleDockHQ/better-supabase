import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** `moderation_report.created`: a member reported a subject. */
export interface ModerationReportEventData {
  readonly organizationId: string;
  /** The report. */
  readonly id: string;
  readonly itemId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly reason: string;
}

/** `moderation_item.decided`: a moderator, or the auto-hide threshold, decided. */
export interface ModerationDecisionEventData {
  readonly organizationId: string;
  /** The moderation item. */
  readonly id: string;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly authorId: string | null;
  readonly action:
    | "approve"
    | "hide"
    | "remove"
    | "restore"
    | "ban"
    | "auto_hide";
  readonly status: "visible" | "hidden" | "removed";
  readonly previousStatus: "pending" | "visible" | "hidden" | "removed";
  /** `true` when the auto-hide threshold hid it. */
  readonly automatic: boolean;
}

/** `moderation_ban.created` and `moderation_ban.lifted`. */
export interface ModerationBanEventData {
  readonly organizationId: string;
  /** The ban. */
  readonly id: string;
  readonly userId: string;
  readonly expiresAt: string | null;
}

/** The events of the `moderation` block: type to data. */
export type ModerationEvents = {
  readonly "moderation_report.created": ModerationReportEventData;
  readonly "moderation_item.decided": ModerationDecisionEventData;
  readonly "moderation_ban.created": ModerationBanEventData;
  readonly "moderation_ban.lifted": ModerationBanEventData;
};

/** The `moderation` block's event types, for its manifest and `onBlockEvent`. */
export const moderationEvents: Events<ModerationEvents> = defineEvents({
  "moderation_report.created": event<ModerationReportEventData>(),
  "moderation_item.decided": event<ModerationDecisionEventData>(),
  "moderation_ban.created": event<ModerationBanEventData>(),
  "moderation_ban.lifted": event<ModerationBanEventData>(),
});
