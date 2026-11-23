import { describe, expect, it } from "vitest";

import { renderBlocks } from "../app-columns.ts";

const layout = (approval: unknown, extra: Record<string, unknown> = {}) => ({
  modules: {
    tasks: { options: { hold: { stage: "blocked", approval, ...extra } } },
  },
});

const sql = (
  module: string,
  options: Parameters<typeof renderBlocks>[1],
  extra: readonly string[],
): string =>
  renderBlocks([module, ...extra], options)
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

describe("tasks hold approvals", () => {
  it("opens an approval from hold_task and settles it from the decision", () => {
    const tasks = sql("tasks", layout(true), ["approvals", "outbox"]);
    const approvals = sql("approvals", layout(true), ["tasks"]);

    expect(tasks).toContain("'task_hold'");
    expect(tasks).toContain("'approvalId'");
    expect(tasks).toContain(
      `create or replace function "better_supabase"."settle_task_hold"`,
    );
    expect(tasks).toMatch(
      /revoke execute on function "better_supabase"."settle_task_hold"\(uuid, text\) from public, anon, authenticated/u,
    );
    expect(approvals).toContain("settle_task_hold");
    expect(approvals).toContain("'cancel'");
  });

  it("leaves a rejected hold alone with onReject keep", () => {
    const approvals = sql("approvals", layout({ onReject: "keep" }), ["tasks"]);

    expect(approvals).toContain("'release'");
    expect(approvals).not.toContain("settle_task_hold(");
  });

  it("files each kind with its own policy and decides a rejection by kind", () => {
    const options = layout(
      {
        onReject: "keep",
        kinds: {
          decision: true,
          spend: {
            policy: {
              steps: [{ approvers: { permission: "finance.approve" } }],
            },
            onReject: "cancel",
          },
        },
      },
      { kinds: ["input", "decision", "spend"] },
    );

    const tasks = sql("tasks", options, ["approvals", "outbox"]);
    const approvals = sql("approvals", options, ["tasks"]);

    expect(tasks).toContain("if hold_task.kind = any(array['decision']) then");
    expect(tasks).toContain("elsif hold_task.kind = any(array['spend']) then");
    expect(tasks).toContain("finance.approve");
    expect(tasks).not.toContain("array['input']");
    expect(tasks).toMatch(/"hold_kind" = any \(array\['spend'\]::text\[\]\)/u);
    expect(approvals).toContain("'reject'");
  });

  it("keeps one rejection outcome when every kind shares it", () => {
    const approvals = sql(
      "approvals",
      layout({ kinds: { decision: true, spend: { onReject: "cancel" } } }),
      ["tasks"],
    );

    expect(approvals).toContain("'cancel'");
    expect(approvals).not.toContain("'reject'");
  });

  it("refuses a malformed per-kind rule", () => {
    const render =
      (approval: unknown, extra = {}) =>
      () =>
        sql("tasks", layout(approval, extra), ["approvals"]);

    expect(render({ kinds: {} })).toThrow(/must name at least one hold kind/u);
    expect(render({ kinds: { Spend: true } })).toThrow(
      /not a short lowercase word/u,
    );
    expect(render({ kinds: { spend: "yes" } })).toThrow(
      /kinds\.spend must be true or \{ policy, onReject \}/u,
    );
    expect(render({ kinds: { spend: { when: 1 } } })).toThrow(
      /kinds\.spend has no key "when"/u,
    );
    expect(render({ kinds: { spend: { onReject: "drop" } } })).toThrow(
      /kinds\.spend\.onReject must be/u,
    );
    expect(
      render({ kinds: { spend: { policy: { steps: [], run: 1 } } } }),
    ).toThrow(/run is not allowed|steps/u);
    expect(render({ kinds: { spend: true } }, { kinds: ["input"] })).toThrow(
      /names "spend", which blocks.tasks.options.hold.kinds does not allow/u,
    );
    expect(() =>
      renderBlocks(["tasks", "approvals"], {
        modules: {
          tasks: {
            options: {
              hold: {
                approval: { kinds: { a: true, b: { onReject: "keep" } } },
              },
            },
            columns: { items: { holdKind: null } },
          },
        },
      }),
    ).toThrow(/needs the hold_kind column/u);
  });

  it("changes nothing without the option", () => {
    const tasks = sql("tasks", {}, ["approvals"]);

    expect(tasks).not.toContain("settle_task_hold");
    expect(tasks).not.toContain("'task_hold'");
  });

  it("needs the approvals block and a known onReject", () => {
    expect(() => sql("tasks", layout(true), [])).toThrow(
      /needs the approvals block/u,
    );
    expect(() =>
      sql("tasks", layout({ onReject: "drop" }), ["approvals"]),
    ).toThrow(/onReject must be/u);
    expect(() =>
      sql("tasks", layout({ policy: { steps: [], run: 1 } }), ["approvals"]),
    ).toThrow(/run is not allowed|steps/u);
  });

  it("refuses a malformed option", () => {
    expect(() => sql("tasks", layout("yes"), ["approvals"])).toThrow(
      /must be true or an object/u,
    );
    expect(() => sql("tasks", layout({ when: 1 }), ["approvals"])).toThrow(
      /has no key "when"/u,
    );
    expect(() =>
      sql(
        "tasks",
        layout({
          policy: {
            steps: [{ approvers: { permission: "tasks.manage" } }],
            run: { queue: "jobs" },
          },
        }),
        ["approvals"],
      ),
    ).toThrow(/run is not allowed/u);
    expect(() =>
      renderBlocks(["tasks", "approvals"], {
        modules: {
          tasks: {
            options: { hold: { approval: true } },
            columns: { items: { heldAt: null } },
          },
        },
      }),
    ).toThrow(/needs the held_at column/u);
  });
});
