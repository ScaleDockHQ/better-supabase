import { describe, expect, it } from "vitest";

import { TARGETS, missingCalls, seedCalls } from "./seed-entity-pages.ts";

const targetOf = (entity: string) => {
  const found = TARGETS.find((each) => each.seed.entity === entity);

  if (found === undefined) {
    throw new Error(`No target for ${entity}`);
  }

  return found;
};

const target = targetOf("dispatch.work_order");

describe("seed-entity-pages", () => {
  it("calls the create function once per generated row", () => {
    const calls = seedCalls(target, "tenant-1");

    expect(calls).toHaveLength(target.seed.rows.length);
    expect(calls[0]?.sql).toContain("better_supabase.create_work_order");
    expect(calls[0]?.identity).toEqual(["Title 1"]);

    expect(calls[0]?.values).toEqual([
      "tenant-1",
      JSON.stringify(target.seed.rows[0]),
    ]);
  });

  it("opens incidents through open_incident with the row as attrs", () => {
    const [call] = seedCalls(targetOf("incidents.incident"), "tenant-1");

    expect(call?.sql).toContain("better_supabase.open_incident");
    expect(call?.values[1]).toBe(JSON.stringify({ title: "Title 1" }));
  });

  it("creates a risk with the category the page declares", () => {
    const calls = seedCalls(targetOf("risks.risk"), "tenant-1");

    expect(calls[0]?.sql).toContain("better_supabase.create_risk");

    expect(JSON.parse(calls[0]?.values[1] ?? "{}")).toEqual({
      title: "Title 1",
      category: "quality",
    });

    expect(calls.map((call) => JSON.parse(call.values[1])["category"])).toEqual(
      expect.arrayContaining(["safety", "strategic"]),
    );
  });

  it("creates the declared fiscal months through create_period", () => {
    const calls = seedCalls(targetOf("periods.period"), "tenant-1");

    expect(calls).toHaveLength(6);
    expect(calls[0]?.sql).toContain("better_supabase.create_period");
    expect(calls[0]?.identity).toEqual(["fiscal_month", "2026-06-01"]);
  });

  it("accrues, attributes and invites from the rows the pages declare", () => {
    const commissions = seedCalls(targetOf("commissions.commission"), "t");
    const referrals = seedCalls(targetOf("referrals.referral"), "t");
    const invitations = seedCalls(targetOf("organizations.invitation"), "t");

    expect(commissions).toHaveLength(2);
    expect(commissions[0]?.sql).toContain("better_supabase.accrue_commission");
    expect(referrals[0]?.sql).toContain("better_supabase.attribute_referral");
    expect(referrals[0]?.identity).toEqual(["friend@initech.test"]);
    expect(invitations[0]?.sql).toContain("better_supabase.create_invitation");
    expect(invitations).toHaveLength(3);
  });

  it("names every identity column of every target in its rows", () => {
    for (const each of TARGETS) {
      expect(() => seedCalls(each, "t")).not.toThrow();
    }
  });

  it("skips the rows the table already holds", () => {
    const calls = seedCalls(targetOf("periods.period"), "tenant-1");

    expect(missingCalls(calls, [["fiscal_month", "2026-06-01"]])).toHaveLength(
      5,
    );

    expect(missingCalls(calls, [])).toHaveLength(6);
  });

  it("adds nothing for a tier the seed does not belong to", () => {
    expect(seedCalls(target, "tenant-1", "l")).toEqual([]);
  });

  it("refuses a row without a value for an identity column", () => {
    const seed = { ...target.seed, rows: [{ name: "x" }] };

    expect(() => seedCalls({ ...target, seed }, "tenant-1")).toThrow(
      "needs a title",
    );
  });
});
