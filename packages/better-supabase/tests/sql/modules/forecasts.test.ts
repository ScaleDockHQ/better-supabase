import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

const sqlOf = (): string =>
  renderBlocks(["forecasts", "deals", "pipelines", "outbox"], {
    modules: { forecasts: {} },
  })
    .filter((file) => file.module === "forecasts")
    .map((file) => file.contents)
    .join("\n");

describe("forecasts module", () => {
  it("keeps the deals of a snapshot and drops them with it", () => {
    const sql = sqlOf();

    expect(sql).toContain(
      '"snapshot_id" uuid not null references "better_supabase"."forecast_snapshots" ("id") on delete cascade',
    );
    expect(sql).toContain('primary key ("snapshot_id", "deal_id")');
    expect(sql).toContain(
      '"pipeline_id" uuid references "better_supabase"."pipelines" ("id") on delete cascade',
    );
  });

  it("stores the deal_forecast totals and records the event", () => {
    const sql = sqlOf();

    expect(sql).toContain('"better_supabase"."deal_forecast"(');
    expect(sql).toContain("'forecast_snapshot.created'");
    expect(sql).toContain("'forecast-snapshots/' ||");
  });

  it("compares two snapshots of one organization and currency", () => {
    const sql = sqlOf();

    expect(sql).toContain("FORECAST_MISMATCH");
    expect(sql).toContain("full join");
    expect(sql).toMatch(/then 'won'/u);
  });
});
