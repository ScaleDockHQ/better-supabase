import { describe, expect, it } from "vitest";

import { applyCodemod, CODEMODS } from "../../src/cli/codemod.ts";

const v047 = CODEMODS["0.47"]!;

describe("codemod 0.47", () => {
  it("renames event types and lists the split ones", () => {
    const source = `onBlockEvent("work_item.created", handler);
onBlockEvent("agent.saved", handler);
onBlockEvent("activity.*", handler);
onBlockEvent("leave.*", handler);
onBlockEvent("drive.*", handler);
onBlockEvent("support.*", handler);
onBlockEvent("rule.removed", handler);
// work_item.created stays in prose
`;

    const result = applyCodemod(v047, source, "src/events.ts");

    expect(result.text).toBe(`onBlockEvent("task.created", handler);
onBlockEvent("agent.saved", handler);
onBlockEvent("activity.*", handler);
onBlockEvent("leave.*", handler);
onBlockEvent("drive.*", handler);
onBlockEvent("support.*", handler);
onBlockEvent("automation.deleted", handler);
// work_item.created stays in prose
`);
    expect(result.review.toSorted((a, b) => a.line - b.line)).toEqual([
      { line: 2, message: expect.stringContaining("`agent.created`") },
      { line: 4, message: expect.stringContaining("`leave_request.*`") },
      { line: 5, message: expect.stringContaining("`drive_node.*`") },
      { line: 6, message: expect.stringContaining("`support_session.*`") },
    ]);
  });

  it("renames event types in the app's own SQL", () => {
    const source = `select * from better_supabase.outbox_events where type = 'engagement.logged';
select * from better_supabase.outbox_events where type = 'agent.saved';
`;

    const result = applyCodemod(v047, source, "supabase/schemas/feed.sql");

    expect(result.text).toContain("'activity.logged'");
    expect(result.text).toContain("'agent.saved'");
    expect(result.review).toEqual([
      { line: 2, message: expect.stringContaining("`agent.updated`") },
    ]);
  });
});
