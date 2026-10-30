import { describe, expect, it } from "vitest";

import { renderBlocks } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderBlocks>[1];

const BASE = ["memberships", "permissions", "subjects", "outbox"];
const ACCOUNTING = ["ledger", "numbering", "accounting"];
const TIME = ["time-tracking", "tasks", "invoices", "billable-time"];

const sqlOf = (
  module: string,
  modules: readonly string[],
  layout: Layout = {},
): string =>
  renderBlocks([...BASE, ...modules], layout)
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

const body = (sql: string, fn: string): string => {
  const start = sql.indexOf(`function "better_supabase"."${fn}"`);

  return start === -1 ? "" : sql.slice(start, sql.indexOf("$$;", start));
};

describe("asset depreciation", () => {
  it("books depreciation and disposals in the ledger when accounting is installed", () => {
    const alone = sqlOf("assets", ["assets"]);
    const booked = sqlOf("assets", [...ACCOUNTING, "assets"]);

    expect(alone).toContain("asset_depreciations");
    expect(body(alone, "run_asset_depreciation")).not.toBe("");
    expect(body(alone, "dispose_asset")).not.toContain(
      "accounting_post_source",
    );
    expect(body(booked, "asset_depreciate")).toContain(
      "accounting_post_source\"('asset_depreciation'",
    );
    expect(body(booked, "dispose_asset")).toContain(
      "accounting_post_source\"('asset_disposal'",
    );
    expect(alone).toContain("'asset.depreciated'");
    expect(alone).toContain("'asset.disposed'");
  });

  it("leaves the book values out when the app's assets table lacks a column", () => {
    const sql = sqlOf("assets", ["assets"], {
      modules: {
        assets: {
          tables: { assets: "public.equipment" },
          columns: { assets: { acquisitionCost: null } },
        },
      },
      ownTables: { "public.equipment": "app.sql" },
    });

    expect(sql).not.toContain("asset_depreciations");
    expect(sql).not.toContain("run_asset_depreciation");
  });
});

describe("project costing", () => {
  it("sums the project's accounting lines when accounting is installed", () => {
    const alone = body(sqlOf("billable-time", TIME), "project_costs");

    const booked = body(
      sqlOf("billable-time", [...ACCOUNTING, ...TIME]),
      "project_costs",
    );

    expect(alone).toContain("where false");
    expect(booked).not.toContain("where false");
    expect(booked).toContain("'project'");
    expect(alone).toContain("WORK_ITEM_PROJECT_NOT_FOUND");
  });

  it("counts work item time only when work items have a project column", () => {
    const linked = body(sqlOf("billable-time", TIME), "project_costs");

    const unlinked = body(
      sqlOf("billable-time", TIME, {
        modules: { tasks: { columns: { items: { project: null } } } },
      }),
      "project_costs",
    );

    expect(linked).toContain("select y.");
    expect(unlinked).not.toBe("");
    expect(unlinked).not.toContain("select y.");
  });

  it("renders no project costs without tasks", () => {
    const sql = sqlOf("billable-time", [
      "time-tracking",
      "invoices",
      "billable-time",
    ]);

    expect(body(sql, "project_costs")).toBe("");
    expect(sql).toContain("cost_amount");
  });

  it("keeps each project a value of the accounting project dimension", () => {
    const alone = sqlOf("tasks", ["tasks"]);
    const booked = sqlOf("tasks", [...ACCOUNTING, "tasks"]);

    expect(alone).toContain("budget_amount");
    expect(alone).not.toContain("accounting_sync_dimension_value");
    expect(booked).toContain("accounting_sync_dimension_value");
  });
});
