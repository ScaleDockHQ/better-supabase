import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const BASE = ["memberships", "permissions", "ledger", "referrals"];

const sqlOf = (
  modules: readonly string[] = BASE,
  layout: Layout = {},
): string =>
  renderBlocks(modules, layout)
    .filter((file) => file.module === "referrals")
    .map((file) => file.contents)
    .join("\n");

describe("referrals module", () => {
  it("renders the code and referral tables and the reward functions", () => {
    const sql = sqlOf();

    expect(sql).toContain("referral_codes");
    expect(sql).toContain("attribute_referral");
    expect(sql).toContain("qualify_referral");
    expect(sql).toContain("void_referral");
  });

  it("renders nothing in custom mode", () => {
    const custom: Layout = { modules: { referrals: { mode: "custom" } } };

    expect(sqlOf(BASE, custom).trim()).toBe("");
  });
});
