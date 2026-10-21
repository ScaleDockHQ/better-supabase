import { describe, expect, it, vi } from "vitest";

import type { OrganizationsEvents } from "../../src/blocks/organizations/events.ts";

import { emitBlockEvent } from "../../src/core/block-events.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { defineTenantSeed, isTenantSeed } from "../../src/testing/seed.ts";
import { seedTenantOnCreate } from "../../src/testing/tenant-seed.ts";
import { fakeSql } from "../fixtures/fake-sql.ts";
import { schema } from "../fixtures/generated-camel.ts";

const betterSupabase = defineSupabase(schema);

const seed = defineTenantSeed(betterSupabase, (tenant) => ({
  customers: {
    demo: { organizationId: tenant.id, name: `Demo for ${tenant.slug ?? "?"}` },
  },
}));

const created = (organizationId: string): void => {
  emitBlockEvent<OrganizationsEvents>(
    betterSupabase.events,
    "organization.created",
    { organizationId },
  );
};

const settle = (): Promise<void> =>
  new Promise((resolve) => {
    setTimeout(resolve, 0);
  });

describe("defineTenantSeed", () => {
  it("renders the fixtures for one tenant", () => {
    expect(isTenantSeed(seed)).toBe(true);
    expect(isTenantSeed({})).toBe(false);
    expect(seed.statements({ id: "o1", slug: "acme" })).toEqual([
      'insert into "public"."customers" ("organization_id", "name") values\n  (\'o1\', \'Demo for acme\')\non conflict do nothing;',
    ]);
  });

  it("rejects unknown tables and inserts through a SQL client", async () => {
    const bad = defineTenantSeed(betterSupabase, () => ({ nope: {} }) as never);
    expect(() => bad.statements({ id: "o1" })).toThrow(
      'tenant seed: unknown table "nope"',
    );

    const db = fakeSql();
    await seed.insert(db.sql, { id: "o2" });
    expect(db.texts()).toEqual(seed.statements({ id: "o2" }));
  });
});

describe("seedTenantOnCreate", () => {
  it("seeds each created organization until it stops listening", async () => {
    const db = fakeSql();

    const stop = seedTenantOnCreate(betterSupabase, seed, {
      sql: db.sql,
      enabled: true,
    });

    created("o1");
    await settle();
    expect(db.texts()).toEqual(seed.statements({ id: "o1" }));

    stop();
    created("o2");
    await settle();
    expect(db.calls).toHaveLength(1);
  });

  it("reports a failed seed without throwing into the emitter", async () => {
    const failure = new Error("duplicate key");
    const db = fakeSql([["customers", { throws: failure }]]);
    const onError = vi.fn();

    const stop = seedTenantOnCreate(betterSupabase, seed, {
      sql: db.sql,
      enabled: true,
      onError,
    });

    expect(() => {
      created("o1");
    }).not.toThrow();
    await settle();
    expect(onError).toHaveBeenCalledWith(failure, "o1");
    stop();

    const error = vi.spyOn(console, "error").mockImplementation(() => {});

    const stopDefault = seedTenantOnCreate(betterSupabase, seed, {
      sql: db.sql,
      enabled: true,
    });

    created("o3");
    await settle();
    expect(error).toHaveBeenCalledWith(
      "better-supabase: the tenant seed failed for o3",
      failure,
    );
    stopDefault();
    error.mockRestore();
  });

  it("does nothing outside development", async () => {
    const db = fakeSql();
    vi.stubEnv("NODE_ENV", "production");
    const stop = seedTenantOnCreate(betterSupabase, seed, { sql: db.sql });
    created("o1");
    await settle();
    expect(db.calls).toEqual([]);
    stop();

    vi.stubEnv("NODE_ENV", "development");
    const stopDev = seedTenantOnCreate(betterSupabase, seed, { sql: db.sql });
    created("o2");
    await settle();
    expect(db.calls).toHaveLength(1);
    stopDev();
    vi.unstubAllEnvs();
  });
});
