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

/** `moderation_notice.received`: a member sent a notice of illegal content. */
export interface ModerationNoticeReceivedEventData {
  readonly organizationId: string;
  /** The notice. */
  readonly id: string;
  readonly itemId: string | null;
  readonly subjectType: string;
  readonly subjectId: string;
  /** `true` when a trusted flagger sent it. */
  readonly trusted: boolean;
}

/** `moderation_notice.decided`: a moderator actioned or rejected a notice. */
export interface ModerationNoticeDecidedEventData {
  readonly organizationId: string;
  /** The notice. */
  readonly id: string;
  readonly itemId: string | null;
  readonly status: "actioned" | "rejected";
  readonly decision: "hide" | "remove" | "reject";
  /** The notifier, who is owed the decision (DSA Article 16(5)). */
  readonly notifierId: string | null;
}

/** `moderation_statement.issued`: a statement of reasons (DSA Article 17). */
export interface ModerationStatementIssuedEventData {
  readonly organizationId: string;
  /** The statement. */
  readonly id: string;
  readonly itemId: string;
  readonly restriction: string;
  /** The affected user, who is owed the statement. */
  readonly authorId: string | null;
}

/** `moderation_appeal.filed`: an appeal against a statement or a notice. */
export interface ModerationAppealFiledEventData {
  readonly organizationId: string;
  /** The appeal. */
  readonly id: string;
  readonly statementId: string | null;
  readonly noticeId: string | null;
  readonly appellantId: string | null;
}

/** `moderation_appeal.decided`: a person upheld or reversed the decision. */
export interface ModerationAppealDecidedEventData {
  readonly organizationId: string;
  /** The appeal. */
  readonly id: string;
  readonly statementId: string | null;
  readonly noticeId: string | null;
  readonly status: "upheld" | "reversed";
  readonly appellantId: string | null;
}

/** The events of the `moderation` block: type to data. */
export type ModerationEvents = {
  readonly "moderation_report.created": ModerationReportEventData;
  readonly "moderation_item.decided": ModerationDecisionEventData;
  readonly "moderation_ban.created": ModerationBanEventData;
  readonly "moderation_ban.lifted": ModerationBanEventData;
  readonly "moderation_notice.received": ModerationNoticeReceivedEventData;
  readonly "moderation_notice.decided": ModerationNoticeDecidedEventData;
  readonly "moderation_statement.issued": ModerationStatementIssuedEventData;
  readonly "moderation_appeal.filed": ModerationAppealFiledEventData;
  readonly "moderation_appeal.decided": ModerationAppealDecidedEventData;
};

/** The `moderation` block's event types, for its manifest and `onBlockEvent`. */
export const moderationEvents: Events<ModerationEvents> = defineEvents({
  "moderation_report.created": event<ModerationReportEventData>(),
  "moderation_item.decided": event<ModerationDecisionEventData>(),
  "moderation_ban.created": event<ModerationBanEventData>(),
  "moderation_ban.lifted": event<ModerationBanEventData>(),
  "moderation_notice.received": event<ModerationNoticeReceivedEventData>(),
  "moderation_notice.decided": event<ModerationNoticeDecidedEventData>(),
  "moderation_statement.issued": event<ModerationStatementIssuedEventData>(),
  "moderation_appeal.filed": event<ModerationAppealFiledEventData>(),
  "moderation_appeal.decided": event<ModerationAppealDecidedEventData>(),
});
