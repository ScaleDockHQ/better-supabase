import { describe, expect, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { defineListQuery, UNSET } from "../../src/list/index.ts";
import {
  type PowerSyncDatabaseLike,
  checkSqlite,
  fromSqliteError,
  postgrestTimestamp,
  powersyncExecutor,
  sqliteTables,
  watch,
} from "../../src/powersync/index.ts";
import { testExecutor } from "../../src/testing/conformance.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { createSqlite } from "../fixtures/sqlite.ts";

const betterSupabase = defineSupabase(schema);
const ORG = "00000000-0000-4000-8000-000000000001";
const OTHER = "00000000-0000-4000-8000-000000000002";

function setup() {
  const sqlite = createSqlite(betterSupabase.meta);
  const db = betterSupabase.connect(powersyncExecutor(sqlite.db));
  return { ...sqlite, client: db };
}

describe("powersyncExecutor", () => {
  it("conforms to the executor contract", () => {
    const { db } = setup();
    return testExecutor(powersyncExecutor(db), {
      betterSupabase,
      table: "tags",
      create: { organizationId: ORG, name: "conformance" },
    });
  });

  it("writes, reads and decodes rows in the PostgREST shape", async () => {
    const { client } = setup();
    const customer = await client.customers
      .create({
        organizationId: ORG,
        name: "Acme",
        metadata: { source: "web", tier: "pro" },
      })
      .orThrow();
    expect(customer.id).toMatch(/^[0-9a-f-]{36}$/);
    expect(customer.metadata).toEqual({ source: "web", tier: "pro" });
    expect(customer.status).toBe("lead");
    expect(typeof customer.createdAt).toBe("string");
    expect(customer.createdAt).toMatch(/\+00:00$/);

    const location = await client.locations
      .create({
        organizationId: ORG,
        customerId: customer.id,
        label: "HQ",
        isPrimary: true,
      })
      .orThrow();
    expect(location.isPrimary).toBe(true);

    const found = await client.customers
      .findMany({
        where: {
          name: { contains: "acm" },
          metadata: { contains: { tier: "pro" } },
          locations: { some: { isPrimary: true } },
        },
        select: ["id", "name"],
      })
      .orThrow();
    expect(found).toEqual([{ id: customer.id, name: "Acme" }]);

    const updated = await client.customers
      .update(customer.id, { status: "active" })
      .orThrow();
    expect(updated.status).toBe("active");
    expect(
      await client.customers
        .updateMany({ where: { status: "archived" }, data: { name: "none" } })
        .orThrow(),
    ).toEqual({ count: 0 });

    expect(await client.locations.delete(location.id)).toMatchObject({
      ok: true,
    });
    expect((await client.locations.delete(location.id)).error?.kind).toBe(
      "not_found",
    );
    expect(await client.locations.count().orThrow()).toBe(0);
  });

  it("upserts on a unique key without crossing tenants", async () => {
    const { client } = setup();
    const first = await client.tags
      .upsert(
        { organizationId: ORG, name: "vip", color: "red" },
        { onConflict: ["organizationId", "name"] },
      )
      .orThrow();
    const second = await client.tags
      .upsert(
        { organizationId: ORG, name: "vip", color: "blue" },
        { onConflict: ["organizationId", "name"] },
      )
      .orThrow();
    expect(second.id).toBe(first.id);
    expect(second.color).toBe("blue");
    const ignored = await client.tags
      .upsertMany(
        [
          { organizationId: ORG, name: "vip", color: "gray" },
          { organizationId: OTHER, name: "vip" },
        ],
        { onConflict: ["organizationId", "name"], ignoreDuplicates: true },
      )
      .orThrow();
    expect(ignored.map((tag) => tag.organizationId)).toEqual([OTHER]);
    expect(
      (await client.tags.findUnique({ where: { id: first.id } }).orThrow())
        ?.color,
    ).toBe("blue");
  });

  it("maps constraint errors to DbError kinds", async () => {
    const { client } = setup();
    await client.tags.create({ organizationId: ORG, name: "a" }).orThrow();
    const conflict = await client.tags.create({
      organizationId: ORG,
      name: "a",
    });
    expect(conflict.error).toMatchObject({
      kind: "conflict",
      code: "23505",
      columns: ["organization_id", "name"],
    });
    expect(
      fromSqliteError(new Error("FOREIGN KEY constraint failed")),
    ).toMatchObject({ code: "23503" });
    expect(
      fromSqliteError(new Error("NOT NULL constraint failed: tags.name")),
    ).toMatchObject({ code: "23502", column: "name" });
    expect(
      fromSqliteError(new Error("CHECK constraint failed: tags_color_check")),
    ).toMatchObject({ code: "23514", constraint: "tags_color_check" });
    expect(fromSqliteError(new Error("no such table: x"))).toBeUndefined();
    expect(fromSqliteError("nope")).toBeUndefined();
  });

  it("returns unsupported for what SQLite can't run, before running it", async () => {
    const { client, statements } = setup();
    const result = await client.customers.findMany({
      include: { locations: true },
    });
    expect(result.error).toMatchObject({
      kind: "unsupported",
      table: "customers",
    });
    expect(statements).toEqual([]);
  });

  it("checks single-row reads", async () => {
    const { client } = setup();
    await client.tags.createMany([
      { organizationId: ORG, name: "a" },
      { organizationId: ORG, name: "b" },
    ]);
    expect(
      (await client.tags.findUnique({ where: { id: "missing" } })).data,
    ).toBeNull();
  });

  it("uses newId for missing keys", async () => {
    const { db } = setup();
    let next = 0;
    const client = betterSupabase.connect(
      powersyncExecutor(db, {
        newId: () => {
          next += 1;
          return `00000000-0000-4000-8000-00000000000${next}`;
        },
      }),
    );
    const tag = await client.tags
      .create({ organizationId: ORG, name: "a" })
      .orThrow();
    expect(tag.id).toBe("00000000-0000-4000-8000-000000000001");
  });
});

describe("lists on SQLite", () => {
  const list = defineListQuery(betterSupabase, "customers", {
    search: ["name", "kvk"],
    facets: { status: "status", kvk: "kvk" },
    sorts: { name: { name: "asc" }, newest: [{ createdAt: "desc" }] },
    defaultSort: "name",
    facetCounts: true,
    pageSize: 2,
  });

  it("pages, searches and counts facets", async () => {
    const { client } = setup();
    await client.customers
      .createMany([
        { organizationId: ORG, name: "Acme", kvk: "1001", status: "active" },
        { organizationId: ORG, name: "Bolt", status: "active" },
        { organizationId: ORG, name: "Crate", kvk: "2002", status: "lead" },
        { organizationId: ORG, name: "Delta 100%", status: "archived" },
      ])
      .orThrow();
    const page = await list
      .run(
        client,
        list.parse({ facets: { status: ["active", "lead"] } }).value!,
        {
          select: ["name"],
        },
      )
      .orThrow();
    expect(page.items).toEqual([{ name: "Acme" }, { name: "Bolt" }]);
    expect(page.page).toMatchObject({ total: 3, pages: 2, hasMore: true });
    expect(page.facetCounts).toEqual({
      status: { active: 2, lead: 1, archived: 1 },
      kvk: { "1001": 1, "2002": 1, [UNSET]: 1 },
    });

    const searched = await list
      .run(client, list.parse({ q: "100%" }).value!, { select: ["name"] })
      .orThrow();
    expect(searched.items).toEqual([{ name: "Delta 100%" }]);
  });

  it("passes the SQLite check", async () => {
    expect((await checkSqlite(betterSupabase, list)).ok).toBe(true);
  });
});

const tick = (): Promise<void> =>
  new Promise((resolve) => {
    setTimeout(resolve, 0);
  });

describe("watch", () => {
  it("reruns the query when a watched table changes", async () => {
    const { db, client } = setup();
    const results: number[] = [];
    const stop = watch(db, () => client.tags.count(), {
      tables: sqliteTables(betterSupabase, ["tags"]),
      onResult: (result) => {
        if (result.ok) results.push(result.data);
      },
    });
    await tick();
    await client.tags.create({ organizationId: ORG, name: "a" });
    await client.customers.create({ organizationId: ORG, name: "A" });
    await tick();
    stop();
    await client.tags.create({ organizationId: ORG, name: "b" });
    await tick();
    expect(results).toEqual([0, 1]);
  });

  it("needs onChange and known tables", () => {
    const { db } = setup();
    const plain: PowerSyncDatabaseLike = { ...db };
    delete plain.onChange;
    expect(() =>
      watch(plain, () => Promise.resolve({ ok: true, data: 1, error: null }), {
        tables: [],
        onResult: () => {},
      }),
    ).toThrow(/onChange/);
    expect(() => sqliteTables(betterSupabase, ["nope"])).toThrow(/nope/);
  });
});

describe("postgrestTimestamp", () => {
  it.each([
    ["2026-01-02 10:00:00Z", "2026-01-02T10:00:00+00:00"],
    ["2026-01-02T10:00:00.500000+00", "2026-01-02T10:00:00.5+00:00"],
    ["2026-01-02T10:00:00.123+0530", "2026-01-02T10:00:00.123+05:30"],
    ["2026-01-02T10:00:00", "2026-01-02T10:00:00+00:00"],
    ["not a date", "not a date"],
  ])("%s", (input, expected) => {
    expect(postgrestTimestamp(input)).toBe(expected);
  });
});
