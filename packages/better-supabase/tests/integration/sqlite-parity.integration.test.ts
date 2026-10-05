import { createClient } from "@supabase/supabase-js";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { Db } from "../../src/core/repository-types.ts";
import type { Result } from "../../src/core/result.ts";
import type { Functions, Models } from "../fixtures/generated-camel.ts";

import { sqliteValue } from "../../src/compile/sqlite.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { defineListQuery } from "../../src/list/index.ts";
import { powersyncExecutor } from "../../src/powersync/index.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { createSqlite } from "../fixtures/sqlite.ts";

const url = process.env["SUPABASE_URL"] ?? "http://127.0.0.1:55421";
const publishableKey =
  process.env["SUPABASE_PUBLISHABLE_KEY"] ??
  "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH";
const secretKey =
  process.env["SUPABASE_SECRET_KEY"] ??
  "sb_secret_N7UND0UgjKTVK-Uodkm0Hg_xSvEMPvz";

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

const ORG = crypto.randomUUID();
const ids = new Map<number, string>();
const id = (n: number): string => {
  const existing = ids.get(n);
  if (existing) return existing;
  const created = crypto.randomUUID();
  ids.set(n, created);
  return created;
};

// Rows on both sides of the local midnights around two DST changes:
// America/New_York springs forward on 2026-03-08 (a 23-hour day) and
// Pacific/Auckland falls back on 2026-04-05 (a 25-hour day).
const CUSTOMERS = [
  ["2026-03-08T04:59:59Z", "Acme", "1001", "active", { tier: "pro" }],
  ["2026-03-08T05:00:00Z", "acme labs", null, "lead", { tier: "free" }],
  ["2026-03-09T03:59:59.999Z", "Bolt 100%", "2002", "active", {}],
  ["2026-03-09T04:00:00Z", "Crate_Co", "1002", "archived", { source: "web" }],
  ["2026-04-04T10:59:59Z", "Delta", null, "lead", { tier: "pro" }],
  ["2026-04-04T11:00:00Z", "echo", "3003", "active", {}],
  ["2026-04-05T11:30:00.123456Z", "Foxtrot", "2003", "lead", { tier: "pro" }],
  ["2026-04-05T12:00:00Z", "Golf", null, "active", {}],
] as const;

describe.skipIf(!live)("SQLite and PostgREST return the same results", () => {
  const betterSupabase = defineSupabase(schema);
  const admin = createClient(url, secretKey, {
    auth: { persistSession: false },
  });
  const rest = betterSupabase.connect(admin);
  const local = createSqlite(betterSupabase.meta);
  const sqlite = betterSupabase.connect(powersyncExecutor(local.db));

  beforeAll(async () => {
    await rest.organizations
      .create({ id: ORG, name: "Parity", slug: `parity-${ORG}` })
      .orThrow();
    await rest.customers
      .createMany(
        CUSTOMERS.map(([createdAt, name, kvk, status, metadata], index) => ({
          id: id(index + 1),
          organizationId: ORG,
          name,
          kvk,
          status,
          metadata,
          createdAt,
        })),
        { returning: false },
      )
      .orThrow();
    await rest.tags
      .createMany(
        [
          { id: id(101), organizationId: ORG, name: "vip", color: "red" },
          { id: id(102), organizationId: ORG, name: "new", color: "blue" },
        ],
        { returning: false },
      )
      .orThrow();
    await rest.customerTags
      .createMany(
        [
          { customerId: id(1), tagId: id(101), organizationId: ORG },
          { customerId: id(3), tagId: id(101), organizationId: ORG },
          { customerId: id(3), tagId: id(102), organizationId: ORG },
        ],
        { returning: false },
      )
      .orThrow();
    for (const table of [
      "organizations",
      "customers",
      "tags",
      "customer_tags",
    ]) {
      const column = table === "organizations" ? "id" : "organization_id";
      const { data, error } = await admin
        .from(table)
        .select("*")
        .eq(column, ORG);
      if (error) throw new Error(error.message);
      for (const row of data as Record<string, unknown>[]) {
        const columns = Object.keys(row);
        local.sqlite
          .prepare(
            `insert into "${table}" (${columns.map((name) => `"${name}"`).join(", ")}) values (${columns.map(() => "?").join(", ")})`,
          )
          .run(...columns.map((name) => sqliteValue(row[name]) as never));
      }
    }
  });

  afterAll(async () => {
    await rest.organizations.deleteMany({ where: { id: ORG } });
  });

  const both = async <T>(
    run: (
      db: Db<Models, Functions, unknown, unknown>,
    ) => PromiseLike<Result<T>>,
  ): Promise<T> => {
    const [fromRest, fromSqlite] = await Promise.all([run(rest), run(sqlite)]);
    if (!fromRest.ok) throw new Error(fromRest.error.message);
    expect(fromSqlite).toEqual(fromRest);
    return fromRest.data;
  };

  const scoped = { organizationId: ORG };

  it("filters text like Postgres", async () => {
    const names = (rows: readonly { name: string }[]) =>
      rows.map((row) => row.name);
    const select = ["name"] as const;
    const orderBy = [{ name: "asc" }, { id: "asc" }] as const;
    expect(
      names(
        await both((db) =>
          db.customers.findMany({
            where: { ...scoped, name: { contains: "acme" } },
            select,
            orderBy,
          }),
        ),
      ),
    ).toEqual(["Acme", "acme labs"]);
    await both((db) =>
      db.customers.findMany({
        where: { ...scoped, name: { startsWith: "Crate_" } },
        select,
        orderBy,
      }),
    );
    await both((db) =>
      db.customers.findMany({
        where: { ...scoped, name: { endsWith: "0%" } },
        select,
        orderBy,
      }),
    );
    await both((db) =>
      db.customers.findMany({
        where: {
          ...scoped,
          OR: [{ kvk: null }, { status: { in: ["archived"] } }],
          NOT: { name: "Golf" },
        },
        select,
        orderBy,
      }),
    );
  });

  it("filters JSON and relations like Postgres", async () => {
    const select = ["id"] as const;
    const orderBy = [{ id: "asc" }] as const;
    await both((db) =>
      db.customers.findMany({
        where: { ...scoped, metadata: { contains: { tier: "pro" } } },
        select,
        orderBy,
      }),
    );
    await both((db) =>
      db.customers.findMany({
        where: { ...scoped, customerTags: { some: { tagId: id(102) } } },
        select,
        orderBy,
      }),
    );
    await both((db) =>
      db.customers.findMany({
        where: { ...scoped, customerTags: { none: {} } },
        select,
        orderBy,
      }),
    );
  });

  it.each([
    ["America/New_York", "2026-03-08", 2],
    ["Pacific/Auckland", "2026-04-05", 2],
    ["Europe/Amsterdam", "2026-03-29", 0],
  ])("selects the local day %s %s", async (timeZone, date, expected) => {
    const day = Temporal.PlainDate.from(date);
    const start = day.toZonedDateTime({ timeZone }).toInstant();
    const end = day.add({ days: 1 }).toZonedDateTime({ timeZone }).toInstant();
    const rows = await both((db) =>
      db.customers.findMany({
        where: {
          ...scoped,
          createdAt: { gte: start.toString(), lt: end.toString() },
        },
        select: ["id", "createdAt"],
        orderBy: [{ createdAt: "asc" }],
      }),
    );
    expect(rows).toHaveLength(expected);
  });

  it("orders, counts and aggregates like Postgres", async () => {
    await both((db) =>
      db.customers.findMany({
        where: scoped,
        select: ["id", "kvk", "createdAt"],
        orderBy: [{ kvk: "desc" }, { createdAt: "desc" }],
        limit: 5,
        offset: 1,
      }),
    );
    await both((db) => db.customers.count({ where: scoped }));
    await both((db) =>
      db.customers.aggregate({
        where: scoped,
        _count: true,
        _min: { createdAt: true, name: true },
        _max: { createdAt: true },
      }),
    );
  });

  it("runs the same list definition", async () => {
    const list = defineListQuery(betterSupabase, "customers", {
      search: ["name", "kvk"],
      facets: { status: "status", kvk: "kvk" },
      sorts: {
        name: [{ name: "asc" }, { id: "asc" }],
        newest: [{ createdAt: "desc" }, { id: "asc" }],
      },
      defaultSort: "newest",
      facetCounts: true,
      pageSize: 3,
    });
    for (const input of [
      {},
      { q: "acme" },
      { q: "100%" },
      { sort: "name", page: 2 },
      { facets: { status: ["active", "lead"], kvk: ["__unset__"] } },
    ] as const) {
      const query = list.parse(input).value!;
      await both((db) =>
        list.run(db, query, { where: scoped, select: ["id", "name"] }),
      );
    }
  });
});
