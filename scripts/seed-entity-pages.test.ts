import { describe, expect, it } from "vitest";

import {
  FINISHERS,
  TARGETS,
  missingCalls,
  orderedTargets,
  refKey,
  rowResolver,
  seedCalls,
} from "./seed-entity-pages.ts";

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

  it("seeds the CRM pages through their block functions", () => {
    const sqlOf = (entity: string) => targetOf(entity).sql;

    expect(sqlOf("app.pipelines")).toContain("save_pipeline_stage");
    expect(sqlOf("app.deals")).toContain("better_supabase.create_deal");
    expect(sqlOf("app.segments")).toContain("better_supabase.refresh_segment");
    expect(sqlOf("app.queues")).toContain("set_assignment_members");
    expect(sqlOf("app.scores")).toContain("better_supabase.compute_score");
    expect(sqlOf("app.contracts")).toContain("better_supabase.create_contract");
    expect(targetOf("app.deals").after).toContain("stage_entered_at");
    expect(targetOf("app.deals").seed.rows).toHaveLength(6);
    expect(targetOf("app.pipelines").seed.rows).toHaveLength(2);
  });

  it("seeds customers and the inbox, with the inbox ahead of the deals", () => {
    expect(targetOf("app.customers").sql).toContain("public.customers");
    expect(targetOf("app.inbox").sql).toContain("record_inbound");
    expect(targetOf("app.inbox").after).toContain("last_message_at");
    expect(targetOf("app.inbox").seed.rows).toHaveLength(3);

    const order = orderedTargets().map((each) => each.seed.entity);

    expect(order.indexOf("app.inbox")).toBeLessThan(order.indexOf("app.deals"));
  });

  it("inserts the rows another page refers to first", () => {
    const order = orderedTargets().map((each) => each.seed.entity);

    expect(order.indexOf("app.pipelines")).toBeLessThan(
      order.indexOf("app.deals"),
    );

    expect(order.indexOf("app.deals")).toBeLessThan(
      order.indexOf("commissions.commission"),
    );

    expect(order).toHaveLength(TARGETS.length);
  });

  it("resolves refs and dates before it reads the identity", () => {
    const ids = new Map([
      [refKey("app.deals", "Globex add-on"), "deal-5"],
      [refKey("app.deals", "Hooli pilot"), "deal-3"],
    ]);

    const calls = seedCalls(
      targetOf("commissions.commission"),
      "t",
      "demo",
      rowResolver(ids, new Date("2026-11-15T00:00:00Z")),
    );

    expect(calls.map((call) => call.identity[2])).toEqual(["deal-5", "deal-3"]);
    expect(JSON.parse(calls[0]?.values[1] ?? "{}").source_id).toBe("deal-5");
  });

  it("counts a deal's close date from the day the seed runs", () => {
    const ids = new Map([[refKey("app.pipelines", "Sales"), "pipeline-1"]]);

    const [first] = seedCalls(
      targetOf("app.deals"),
      "t",
      "demo",
      rowResolver(ids, new Date("2026-11-15T00:00:00Z")),
    );

    const row = JSON.parse(first?.values[1] ?? "{}");

    expect(row.closeOn).toBe("2026-11-27");
    expect(row.pipelineId).toBe("pipeline-1");
  });

  it("stops on a ref whose row is missing", () => {
    expect(() =>
      seedCalls(
        targetOf("commissions.commission"),
        "t",
        "demo",
        rowResolver(new Map(), new Date()),
      ),
    ).toThrow('No app.deals row named "Globex add-on"');
  });

  it("takes the forecast snapshot once, after every page", () => {
    expect(FINISHERS).toHaveLength(1);
    expect(FINISHERS[0]).toContain("take_forecast_snapshot");
    expect(FINISHERS[0]).toContain("not exists");
  });
});
