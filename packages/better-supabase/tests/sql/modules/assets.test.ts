import { describe, expect, it } from "vitest";

import { renderModules } from "../../../src/sql/render.ts";

type Layout = Parameters<typeof renderModules>[1];

const sqlOf = (modules: readonly string[], layout: Layout = {}): string =>
  renderModules(modules, layout)
    .filter((file) => file.module === "assets")
    .map((file) => file.contents)
    .join("\n");

const postgis: Layout = { modules: { assets: { options: { postgis: true } } } };

describe("assets module", () => {
  it("stores plain coordinates and searches by distance without PostGIS", () => {
    const sql = sqlOf(["assets"]);

    expect(sql).not.toContain("create extension");
    expect(sql).not.toContain("extensions.geography");
    expect(sql).toContain("ASSETS_POSTGIS_REQUIRED");
    expect(sql).toContain("2 * 6371008.8 * asin(");
  });

  it("adds geography columns, GiST indexes and area lookups with PostGIS", () => {
    const sql = sqlOf(["assets"], postgis);

    expect(sql).toContain(
      "create extension if not exists postgis with schema extensions;",
    );
    expect(sql).toContain(
      "point extensions.geography(Point, 4326) generated always as",
    );
    expect(sql).toContain("area extensions.geography(MultiPolygon, 4326)");
    expect(sql).toContain("using gist");
    expect(sql).toContain("extensions.st_dwithin(");
    expect(sql).toContain("extensions.st_covers(");
    expect(sql).not.toContain("ASSETS_POSTGIS_REQUIRED");
  });

  it("links booking resources and work items when those modules are installed", () => {
    const alone = sqlOf(["assets"]);
    expect(alone).not.toContain('"booking_resources"');
    expect(alone).not.toContain('"work_items"');

    const linked = sqlOf(["bookings", "work-items", "assets"]);
    expect(linked).toContain(
      'alter table "better_supabase"."booking_resources" add column if not exists asset_id uuid',
    );
    expect(linked).toContain(
      'alter table "better_supabase"."work_items" add column if not exists asset_id uuid',
    );
    expect(linked).toContain("'bookingResources'");
  });

  it("checks the location tree for cycles and other tenants", () => {
    const sql = sqlOf(["assets"]);

    expect(sql).toContain("ASSETS_LOCATION_CYCLE");
    expect(sql).toContain("asset_location_check_parent");
  });
});
