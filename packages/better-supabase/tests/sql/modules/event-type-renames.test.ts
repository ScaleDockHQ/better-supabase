import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

/** The data file `module` renders. */
function data(module: string): string {
  const files = renderBlocks([module]).filter(
    (file) =>
      file.module === module && file.contents.includes("@bsb-block-data"),
  );

  return files.map((file) => file.contents).join("\n");
}

describe("event type data steps", () => {
  it("renames the stored outbox types and widens consumer lists", () => {
    const sql = data("outbox");

    expect(sql).toContain(
      "-- Event types renamed by the 0.47 naming convention",
    );
    expect(sql).toContain(
      'update "better_supabase"."outbox_events" t set "type"',
    );
    expect(sql).toContain("('work_item.created', 'task.created')");
    expect(sql).not.toContain("('agent.saved', 'agent.");
    expect(sql).toContain(
      "('agent.saved', array['agent.created', 'agent.updated']::text[])",
    );
    expect(sql).toContain("('drive.*', array['drive_node.*']::text[])");
    expect(sql).toContain(
      "('leave.*', array['leave_request.*', 'leave_balance.*']::text[])",
    );
  });

  it("widens webhook endpoint lists", () => {
    expect(data("webhooks-out")).toContain(
      "('webhook.*', array['webhook_endpoint.*']::text[])",
    );
  });

  it("renames automation triggers and timeline entries", () => {
    expect(data("automations")).toContain(
      "('rule.removed', 'automation.deleted')",
    );
    expect(data("timeline")).toContain(
      "('engagement.logged', 'activity.logged')",
    );
  });
});
