import { describe, expect, it } from "vitest";

import type { BlockSqlContext } from "../../../src/sql/context.ts";

import { CONTROLS } from "../../../src/sql/modules/controls.ts";
import { customContracts, renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const BASE = ["versions", "attachments", "notifications", "controls"];

const sqlOf = (
  layout: Layout = {},
  modules: readonly string[] = BASE,
): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === "controls")
    .map((file) => file.contents)
    .join("\n");

describe("controls module", () => {
  it("links evidence to an attachment only when attachments owns its table", () => {
    const sql = sqlOf();
    expect(sql).toMatch(
      /"attachment_id" uuid references "better_supabase"\."attachments"/,
    );
    expect(sql).toContain("the attachment isn''t a file in this organization");

    const bare = sqlOf({}, ["versions", "controls"]);
    expect(bare).not.toMatch(/"attachment_id" uuid references/);
    expect(bare).toContain("evidence files need the attachments module");

    const adopted = sqlOf({ modules: { attachments: { mode: "custom" } } });
    expect(adopted).toContain("evidence files need the attachments module");
  });

  it("notifies the assignee of a missed task only with notifications installed", () => {
    expect(sqlOf()).toContain("'evidence_task.missed:'");
    expect(sqlOf({}, ["versions", "controls"])).not.toContain(
      "'evidence_task.missed:'",
    );
  });

  it("references the policy version only when versions owns its table", () => {
    expect(sqlOf()).toMatch(
      /references "better_supabase"\."versions" \("id"\) on delete restrict/,
    );

    const adopted = sqlOf({
      modules: {
        versions: { mode: "adopt", tables: { versions: "app.revisions" } },
      },
    });

    expect(adopted).not.toContain("on delete restrict");
  });

  it("refuses to build on versions in custom mode", () => {
    expect(() => sqlOf({ modules: { versions: { mode: "custom" } } })).toThrow(
      "blocks.controls needs the versions tables",
    );
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = { modules: { controls: { mode: "custom" } } };
    expect(sqlOf(custom).trim()).toBe("");
    // SAFETY: custom mode returns before reading anything else on the context.
    const context = { mode: "custom" } as unknown as BlockSqlContext;
    expect(CONTROLS.build(context, {})).toBe("");
    const [contract] = customContracts(["controls"], custom);
    expect(contract?.functions.map((fn) => fn.name)).toEqual(
      expect.arrayContaining([
        "save_control",
        "control_posture",
        "acknowledge_policy",
      ]),
    );
  });
});
