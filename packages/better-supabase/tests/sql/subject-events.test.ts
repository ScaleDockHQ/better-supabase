import { describe, expect, it } from "vitest";

import type { SubjectEventType } from "../../src/core/block-events.ts";
import type { AllBlockEvents } from "../blocks/all-blocks.ts";

import { SQL_MODULES } from "../../src/sql/registry.ts";

const SUBJECT_EVENTS = [
  "employee.created",
  "employee.updated",
  "employee.offboarded",
  "employee.manager_changed",
  "application.created",
  "application.hired",
  "application.rejected",
  "application.retracted",
  "scorecard.submitted",
  "interview.scheduled",
  "sla.warned",
  "sla.breached",
  "sla.completed",
  "quote.created",
  "quote.updated",
  "quote.sent",
  "quote.viewed",
  "quote.accepted",
  "quote.rejected",
  "quote.changes_requested",
  "quote.expired",
  "quote.revised",
  "quote.withdrawn",
  "invoice.created",
  "invoice.updated",
  "invoice.deleted",
  "invoice.issued",
  "invoice.payment_recorded",
  "invoice.paid",
  "invoice.credited",
  "invoice.voided",
  "invoice.uncollected",
  "invoice.charged",
  "invoice.charge_removed",
  "invoice.payment_reversed",
  "work_item.created",
  "work_item.updated",
  "work_item.assigned",
  "work_item.closed",
  "work_item.reopened",
  "work_item.archived",
  "work_item.deleted",
  "deal.created",
  "deal.updated",
  "deal.closed",
  "deal.reopened",
  "deal.archived",
  "deal.deleted",
  "engagement.logged",
  "engagement.updated",
  "engagement.completed",
  "engagement.deleted",
  "engagement.recorded",
  "engagement.transcribed",
  "engagement.summarized",
  "collection.entry_added",
  "collection.entry_removed",
  "saved_item.reminded",
  "pipeline.stage_changed",
  "subject.tagged",
  "subject.untagged",
  "status.changed",
  "status.paused",
  "status.resumed",
  "status.flagged",
  "field_value.set",
  "field_value.deleted",
  "field_value.viewed",
  "share_link.created",
  "subject.viewed",
  "reminder.sent",
  "subject.linked",
  "subject.unlinked",
  "version.created",
  "version.restored",
  "version.deleted",
  "subject.trashed",
  "subject.restored",
  "subject.purged",
  "reaction.added",
  "reaction.removed",
  "approval.requested",
  "approval.approved",
  "approval.rejected",
  "approval.cancelled",
  "approval.expired",
  "approval.delegated",
  "approval.consumed",
  "approval.escalated",
  "document.created",
  "document.suggested",
  "document.suggestion_accepted",
  "document.suggestion_rejected",
  "stock.reorder_point_reached",
  "drive.node_created",
  "drive.node_renamed",
  "drive.node_moved",
  "drive.node_shared",
  "drive.node_unshared",
  "drive.node_purged",
  "drive.node_hold_placed",
  "drive.node_hold_released",
  "drive.node_locked",
  "drive.node_unlocked",
  "drive.node_download_blocked_changed",
  "drive.created",
  "drive.renamed",
  "drive.deleted",
  "drive.shared",
  "drive.unshared",
  "drive.download_blocked_changed",
  "drive.connection_created",
  "drive.connection_removed",
  "order.placed",
  "order.paid",
  "order.cancelled",
  "order.fulfilled",
  "order.completed",
  "order.refunded",
  "fulfillment.shipped",
  "fulfillment.delivered",
  "return.requested",
  "return.received",
  "order.prepared",
  "order.served",
  "form_submission.submitted",
  "form_submission.reviewed",
  "form_submission.deleted",
  "signature.requested",
  "signature.signed",
  "signature.completed",
  "signature.declined",
  "signature.cancelled",
  "notification.delivered",
  "notification.failed",
  "notification.opened",
  "notification.clicked",
  "notification.bounced",
  "notification.complained",
  "notification.delayed",
  "template.applied",
  "review.submitted",
  "review.published",
  "review.rejected",
  "review.replied",
  "review.deleted",
  "rule.matched",
  "score.changed",
  "moderation_report.created",
  "moderation_item.decided",
  "enrollment.created",
  "enrollment.step_completed",
  "enrollment.completed",
  "enrollment.cancelled",
  "guest_grant.created",
  "guest_grant.revoked",
  "conversation.created",
  "conversation.archived",
  "conversation.member_added",
  "conversation.member_removed",
  "message.sent",
  "message.edited",
  "message.deleted",
  "message.pinned",
  "message.resolved",
  "channel.created",
  "channel.updated",
  "segment.entered",
  "segment.left",
  "subject.assigned",
  "party.enriched",
  "sequence_enrollment.created",
  "sequence_enrollment.step_completed",
  "sequence_enrollment.paused",
  "sequence_enrollment.resumed",
  "sequence_enrollment.exited",
  "sequence_enrollment.completed",
  "subject_member.added",
  "subject_member.ended",
  "acknowledgement_assignment.created",
  "acknowledgement_assignment.deleted",
  "acknowledgement.created",
  "acknowledgement.reminded",
  "consent.granted",
  "consent.refused",
  "consent.withdrawn",
  "consent.expired",
] as const satisfies readonly SubjectEventType<AllBlockEvents>[];

/**
 * Subject events that only the TypeScript block emits, so no SQL catalog lists
 * them.
 */
const EMITTED_IN_TS = new Set<string>(["notification.failed"]);

type Unlisted = Exclude<
  SubjectEventType<AllBlockEvents>,
  (typeof SUBJECT_EVENTS)[number]
>;

const everyTypeListed: Unlisted extends never ? true : false = true;

/** Events that name a subject only when the row is attached to one. */
const OPTIONAL_SUBJECT = new Set([
  "attachment.uploaded",
  "attachment.replaced",
  "attachment.restored",
  "time_entry.started",
  "time_entry.recorded",
  "time_entry.updated",
  "time_entry.deleted",
  "workflow_run.completed",
  "workflow_run.failed",
  "workflow_run.cancelled",
  "work_order.created",
  "shipment.created",
  "data_export.requested",
  "data_export.completed",
  "data_export.failed",
]);

interface CatalogEntry {
  readonly module: string;
  readonly type: string;
  readonly payload: readonly string[];
}

const catalog = Object.values(SQL_MODULES).flatMap((module): CatalogEntry[] =>
  Object.entries(module.names?.events ?? {}).map(([type, spec]) => ({
    module: module.name,
    type,
    payload: spec?.payload ?? [],
  })),
);

describe("subject-bound events in the SQL catalogs", () => {
  it("lists every SubjectEventType", () => {
    expect(everyTypeListed).toBe(true);
  });

  it.each(SUBJECT_EVENTS.filter((type) => !EMITTED_IN_TS.has(type)))(
    "%s carries the tenant and the subject",
    (type) => {
      const entries = catalog.filter((entry) => entry.type === type);
      expect(entries.length).toBeGreaterThan(0);

      for (const entry of entries) {
        expect(entry.payload).toEqual(
          expect.arrayContaining([
            "organizationId",
            "subjectType",
            "subjectId",
          ]),
        );
      }
    },
  );

  it("every event with a subject in its payload is a SubjectEventType", () => {
    const listed = new Set<string>(SUBJECT_EVENTS);

    const unlisted = catalog
      .filter(
        (entry) =>
          entry.payload.includes("subjectType") &&
          entry.payload.includes("subjectId") &&
          !listed.has(entry.type) &&
          !OPTIONAL_SUBJECT.has(entry.type),
      )
      .map((entry) => `${entry.module}: ${entry.type}`);

    expect(unlisted).toEqual([]);
  });
});
