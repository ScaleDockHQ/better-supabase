import { describe, expect, it } from "vitest";

import type { SubjectEventType } from "../../src/core/block-events.ts";

import { SQL_MODULES } from "../../src/sql/registry.ts";

const SUBJECT_EVENTS = [
  "comment.created",
  "comment.mentioned",
  "comment.deleted",
  "subject.tagged",
  "subject.untagged",
  "status.changed",
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
] as const satisfies readonly SubjectEventType[];

type Unlisted = Exclude<SubjectEventType, (typeof SUBJECT_EVENTS)[number]>;
const everyTypeListed: Unlisted extends never ? true : false = true;

/** Events that name a subject only when the row is attached to one. */
const OPTIONAL_SUBJECT = new Set(["attachment.uploaded"]);

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

  it.each(SUBJECT_EVENTS)("%s carries the tenant and the subject", (type) => {
    const entries = catalog.filter((entry) => entry.type === type);
    expect(entries.length).toBeGreaterThan(0);
    for (const entry of entries) {
      expect(entry.payload).toEqual(
        expect.arrayContaining(["organizationId", "subjectType", "subjectId"]),
      );
    }
  });

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
