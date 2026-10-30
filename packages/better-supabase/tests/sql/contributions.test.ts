import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { BlockContributes } from "../../src/sql/contributions.ts";

import { resolveConfig } from "../../src/config/resolve.ts";
import { moduleLayout } from "../../src/sql/layout.ts";
import { SQL_MODULES } from "../../src/sql/registry.ts";
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
      bulk: {},
      tags: {},
      labels: { block: "tags", entities: { tag: "label" } },
    });

    expect(count(sqlOf(files, "bulk"), "when 'tags.set' then")).toBe(1);
  });

  it("sends a renamed instance to the instance its uses names", () => {
    const files = render({
      bulk: {},
      rowActions: { block: "bulk" },
      tags: {},
      labels: {
        block: "tags",
        entities: { tag: "label" },
        uses: { bulk: "rowActions" },
      },
    });

    const bulk = sqlOf(files, "bulk");
    const row = sqlOf(files, "rowActions");

    expect(bulk).toContain("when 'tags.set' then");
    expect(row).toContain("when 'tags.set' then");
    expect(bulk).not.toEqual(row);
  });

  it("binds a renamed record instance to the pipelines its block requires", () => {
    const files = render({
      pipelines: {},
      tasks: {},
      tickets: { block: "tasks", entities: { task: "ticket" } },
    });

    const pipelines = sqlOf(files, "pipelines");

    expect(pipelines).toContain("'task'");
    expect(pipelines).toContain("'ticket'");
  });

  describe("relation kinds", () => {
    const tags = SQL_MODULES["tags"];
    const original = tags?.contributes;

    beforeEach(() => {
      const contributes: BlockContributes = {
        ...original,
        relations: (own) => [
          {
            kind: "tagged_from",
            inverse: "tagged_into",
            types: { source: [own.naming.rename("tag")] },
          },
          { kind: "blocks", symmetric: true },
        ],
      };

      Reflect.set(tags ?? {}, "contributes", contributes);
    });

    afterEach(() => {
      Reflect.set(tags ?? {}, "contributes", original);
    });

    const relations = (options: Record<string, unknown> = {}): string =>
      sqlOf(render({ relations: { options }, tags: {} }), "relations");

    it("adds a contributed kind next to the app's kinds", () => {
      const sql = relations();

      expect(sql).toContain(
        `('tagged_from', 'tagged_from', false, false, false, false, 'tagged_into')`,
      );
      expect(sql).toContain(
        `('tagged_into', 'tagged_from', true, false, false, false, 'tagged_from')`,
      );
      expect(sql).toContain(
        `if v_kind = 'tagged_from' and not (v_source_type in ('tag')) then`,
      );
      expect(sqlOf(render({ relations: {} }), "relations")).not.toContain(
        "tagged_from",
      );
    });

    it("keeps the app's kind of the same name", () => {
      expect(relations()).toContain(
        `('blocks', 'blocks', false, true, false, false, 'blocked_by')`,
      );
      expect(
        relations({ kinds: { tagged_from: { cardinality: "one" } } }),
      ).toContain(
        `('tagged_from', 'tagged_from', false, false, true, false, 'tagged_from')`,
      );
    });
  });

  it("refuses two contributions of one subject type", () => {
    expect(() =>
      render({
        approvals: {},
        "time-tracking": {},
        overtime: {
          block: "time-tracking",
          entities: { entry: "shift" },
          uses: { approvals: "approvals" },
        },
      }),
    ).toThrow(/Two blocks contribute "timesheet" to approvals/);
  });
});
