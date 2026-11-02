import { describe, expect, it } from "vitest";

import { renderBlocks, SQL_MODULES } from "../../src/sql/index.ts";

/**
 * Declared event types whose literal is not in their own module's SQL: the
 * module builds the type from a verb at run time, or another module or the
 * client records it. The list only shrinks. A new declared event that nothing
 * records fails the test, and so does an entry that is recorded now.
 */
const NOT_LITERAL = [
  "audit: audit.revealed",
  "organizations: organization.role_added",
  "organizations: organization.role_removed",
  "attachments: object.uploaded",
  "teams: team.restored",
  "state-machine: status.changed",
  "state-machine: status.paused",
  "state-machine: status.resumed",
  "state-machine: status.flagged",
  "custom-fields: field_value.deleted",
  "custom-fields: field_value.viewed",
  "subjects: subject.accessed",
  "calendar: calendar.updated",
  "bookings: booking.rescheduled",
  "approvals: approval_policy.created",
  "approvals: approval_policy.updated",
  "approvals: approval_policy.deleted",
  "access-requests: access_request.emergency_opened",
  "access-requests: access_request.emergency_reviewed",
  "drive: drive.download_blocked_changed",
  "drive: drive.created",
  "drive: drive.renamed",
  "drive: drive.deleted",
  "drive: drive.shared",
  "drive: drive.unshared",
  "drive: drive.ownership_transferred",
  "drive: drive.connection_created",
  "drive: drive.connection_removed",
  "drive-files: drive_node.purged",
  "drive-files: drive_node.document_saved",
  "drive-files: drive_node.submitted",
  "drive-files: drive_node.released",
  "drive-files: drive_node.obsoleted",
  "drive-files: drive_node.reviewed",
  "drive-files: drive_node.review_requested",
  "orders: order.prepared",
  "orders: order.served",
  "time-tracking: timesheet.rejected",
  "pipelines: pipeline.stage_changed",
  "activities: activity.recorded",
  "activities: activity.transcribed",
  "activities: activity.summarized",
  "leave: leave_request.rejected",
  "passes: pass.credit_used",
  "passes: pass.credit_refunded",
  "expenses: expense_report.rejected",
  "expenses: expense.created",
  "expenses: expense.submitted",
  "expenses: expense.rejected",
  "expenses: expense.withdrawn",
  "expenses: expense.deleted",
  "shipments: shipment.return_received",
  "content: content_entry.publish_requested",
  "care-plans: care_plan.agreed",
  "cases: case_action.created",
  "inspections: inspection_finding.case_raised",
  "dam: dam_usage_right.expiry_notified",
];

function unrecorded(): string[] {
  const missing: string[] = [];

  for (const module of Object.values(SQL_MODULES)) {
    const types = Object.keys(module.names?.events ?? {});

    if (types.length === 0) {
      continue;
    }

    const sql = renderBlocks(["audit", "outbox", module.name], {})
      .filter((file) => file.module === module.name)
      .map((file) => file.contents)
      .join("\n");

    for (const type of types) {
      if (!sql.includes(`'${type}'`)) {
        missing.push(`${module.name}: ${type}`);
      }
    }
  }

  return missing;
}

describe("declared event types", () => {
  it("are recorded by their module's SQL, except the known gaps", () => {
    expect(unrecorded()).toEqual(NOT_LITERAL);
  });
});
