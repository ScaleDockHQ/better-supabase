import { describe, expect, it } from "vitest";

import type { SubjectEventType } from "../../src/core/block-events.ts";

import { SQL_MODULES } from "../../src/sql/registry.ts";

const SUBJECT_EVENTS = [
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
  "pipeline.stage_changed",
  "comment.created",
  "comment.mentioned",
  "comment.deleted",
  "subject.tagged",
  "subject.untagged",
  "status.changed",
  "status.paused",
  "status.resumed",
  "status.flagged",
  "field_value.set",
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
  "document.created",
  "stock.reorder_point_reached",
  "drive.node_created",
  "drive.node_renamed",
  "drive.node_moved",
  "drive.node_shared",
  "drive.node_unshared",
  "drive.node_purged",
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
] as const satisfies readonly SubjectEventType[];

/** Subject events that only the TypeScript block emits, so no SQL catalog lists them. */
const EMITTED_IN_TS = new Set<string>(["notification.failed"]);

type Unlisted = Exclude<SubjectEventType, (typeof SUBJECT_EVENTS)[number]>;
const everyTypeListed: Unlisted extends never ? true : false = true;

/** Events that name a subject only when the row is attached to one. */
const OPTIONAL_SUBJECT = new Set([
  "attachment.uploaded",
  "time_entry.started",
  "time_entry.recorded",
  "time_entry.updated",
  "time_entry.deleted",
  "workflow_run.completed",
  "workflow_run.failed",
  "workflow_run.cancelled",
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
    payload: spec.payload,
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
