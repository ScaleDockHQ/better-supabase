import { afterAll, describe, expect, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { createPostgres } from "../../src/postgres/index.ts";
import { asUser } from "../../src/testing/as-user.ts";
import { scopedSeed, withRollback } from "../../src/testing/scope.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { stackDbUrl, stackUrl } from "./stack-env.ts";

const url = stackUrl();

const publishableKey =
  process.env["SUPABASE_PUBLISHABLE_KEY"] ??
  "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH";

const USER = "00000000-0000-4000-8000-0000000000ff";

async function reachable(): Promise<boolean> {
  try {
    const response = await fetch(`${url}/rest/v1/`, {
      headers: { apikey: publishableKey },
      signal: AbortSignal.timeout(1000),
    });

    return response.status < 500;
  } catch {
    return false;
  }
}

const live = await reachable();

describe.skipIf(!live)("scopedSeed and withRollback", () => {
  const postgres = createPostgres({ connectionString: stackDbUrl(), max: 4 });
  afterAll(() => postgres.end());

  const betterSupabase = defineSupabase(schema);

  const organization = {
    table: "organizations",
    row: (id: string) => ({ id, name: `scope-${id}`, slug: `scope-${id}` }),
  } as const;

  const seed = (name: string) =>
    scopedSeed(
      betterSupabase,
      ({ tenant }) => ({
        customers: { first: { organizationId: tenant, name } },
      }),
      { tenant: organization },
    );

  it("gives concurrent tests their own tenant and rows, and cleans up", async () => {
    const [one, two] = await Promise.all([seed("one"), seed("two")]);
    const admin = postgres.admin;

    try {
      expect(one.tenant).not.toBe(two.tenant);
      expect(one.rows.customers.first.organizationId).toBe(one.tenant);

      const alice = await asUser(
        betterSupabase,
        { sub: USER, tenant_id: one.tenant },
        { postgres },
      );

      const names = await alice
        .sql!.customers.findMany({ select: ["name"] })
        .orThrow();

      expect(names).toEqual([{ name: "one" }]);
    } finally {
      await Promise.all([one.cleanup(), two.cleanup()]);
    }

    const left = await admin.queryRaw(
      "select 1 from public.organizations where id = any($1)",
      [[one.tenant, two.tenant]],
    );

    expect(left).toEqual([]);
  });

  it("rolls back what the callback wrote and returns its value", async () => {
    await using scope = await scopedSeed(betterSupabase, () => ({}), {
      tenant: organization,
    });

    const alice = await asUser(
      betterSupabase,
      { sub: USER, tenant_id: scope.tenant },
      { postgres },
    );

    const inside = await withRollback(alice, async (db) => {
      await db.customers
        .create({ organizationId: scope.tenant, name: "temp" })
        .orThrow();

      return db.customers.count().orThrow();
    });

    expect(inside).toBe(1);
    expect(await alice.sql!.customers.count().orThrow()).toBe(0);
  });

  it("rethrows an error from the callback", async () => {
    const alice = await asUser(betterSupabase, { sub: USER }, { postgres });

    await expect(
      withRollback(alice, () => Promise.reject(new Error("boom"))),
    ).rejects.toThrow("boom");
  });
});
