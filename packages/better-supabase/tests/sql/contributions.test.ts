import { describe, expect, it } from "vitest";

import { resolveConfig } from "../../src/config/resolve.ts";
import { moduleLayout } from "../../src/sql/layout.ts";
import { renderBlocks } from "../../src/sql/render.ts";

type Blocks = NonNullable<Parameters<typeof resolveConfig>[0]["blocks"]>;

const render = (blocks: Blocks) => {
  const config = resolveConfig({ blocks }, "/app");

  return renderBlocks(config.blockNames, moduleLayout(config));
};

const sqlOf = (
  files: ReturnType<typeof renderBlocks>,
  instance: string,
): string =>
  files
    .filter((file) => (file.instance ?? file.module) === instance)
    .map((file) => file.contents)
    .join("\n");

const count = (text: string, part: string): number =>
  text.split(part).length - 1;

describe("block contributions", () => {
  it("adds a consumer's request type to approvals", () => {
    const approvals = sqlOf(
      render({ approvals: {}, "time-tracking": {} }),
      "approvals",
    );

    expect(approvals).toContain(`= 'timesheet'`);
    expect(approvals).toContain(`"better_supabase"."approve_timesheet"`);

    const alone = sqlOf(render({ approvals: {} }), "approvals");

    expect(alone).not.toContain("timesheet");
  });

  it("keeps a renamed instance out unless its uses names the target", () => {
    const files = render({
      "bulk-actions": {},
      tags: {},
      labels: { block: "tags", entities: { tag: "label" } },
    });

    expect(count(sqlOf(files, "bulk-actions"), "when 'tags.set' then")).toBe(1);
  });

  it("sends a renamed instance to the instance its uses names", () => {
    const files = render({
      "bulk-actions": {},
      rowActions: { block: "bulk-actions" },
      tags: {},
      labels: {
        block: "tags",
        entities: { tag: "label" },
        uses: { "bulk-actions": "rowActions" },
      },
    });

    const bulk = sqlOf(files, "bulk-actions");
    const row = sqlOf(files, "rowActions");

    expect(bulk).toContain("when 'tags.set' then");
    expect(row).toContain("when 'tags.set' then");
    expect(bulk).not.toEqual(row);
  });

  it("binds a renamed record instance to the pipelines its block requires", () => {
    const files = render({
      pipelines: {},
      tasks: {},
      tickets: { block: "tasks", entities: { work_item: "ticket" } },
    });

    const pipelines = sqlOf(files, "pipelines");

    expect(pipelines).toContain("'work_item'");
    expect(pipelines).toContain("'ticket'");
  });

  it("refuses two contributions of one subject type", () => {
    expect(() =>
      render({
        approvals: {},
        "time-tracking": {},
        shifts: {
          block: "time-tracking",
          entities: { entry: "shift" },
          uses: { approvals: "approvals" },
        },
      }),
    ).toThrow(/Two blocks contribute "timesheet" to approvals/);
  });
});
