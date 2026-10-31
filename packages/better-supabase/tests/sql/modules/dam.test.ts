import { describe, expect, it } from "vitest";

import type { BlockSqlContext } from "../../../src/sql/context.ts";

import { DAM } from "../../../src/sql/modules/dam.ts";
import { customContracts, renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const BASE = ["memberships", "permissions", "subjects", "dam"];

const sqlOf = (
  modules: readonly string[] = BASE,
  layout: Layout = {},
): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === "dam")
    .map((file) => file.contents)
    .join("\n");

describe("dam module", () => {
  it("renders the tables, one rendition per file and kind", () => {
    const sql = sqlOf();

    expect(sql).toContain("dam_renditions");
    expect(sql).toContain("dam_usage_rights");
    expect(sql).toContain('unique ("tenant_id", "node_id", "kind")');
    expect(sql).toContain("'pending', 'ready', 'failed'");
  });

  it("decides usage by status, territory and channel", () => {
    const sql = sqlOf();

    expect(sql).toContain("check_usage");
    expect(sql).toContain("is not null then 'revoked'");
    expect(sql).toContain('is null or x."territory"');
  });

  it("reminds once per expiry date only with notifications installed", () => {
    expect(sqlOf()).toContain("select 0");
    expect(sqlOf([...BASE, "notifications"])).toContain(
      "dam_usage_right.expiry_notified",
    );
  });

  it("renders nothing in custom mode and lists the functions to implement", () => {
    const custom: Layout = { modules: { dam: { mode: "custom" } } };
    expect(sqlOf(BASE, custom).trim()).toBe("");
    // SAFETY: custom mode returns before reading anything else on the context.
    const context = { mode: "custom" } as unknown as BlockSqlContext;
    expect(DAM.build(context, {})).toBe("");
    const [contract] = customContracts(["dam"], custom);
    expect(contract?.functions.map((fn) => fn.name)).toEqual(
      expect.arrayContaining([
        "record_rendition",
        "grant_usage_right",
        "check_usage",
        "notify_expiring_usage_rights",
      ]),
    );
  });
});
