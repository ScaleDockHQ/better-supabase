import { createClient } from "@supabase/supabase-js";
import { afterAll, describe, expect, it } from "vitest";

import { defineSupabase } from "../core/define.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { defineListQuery, UNSET } from "../list/index.ts";
import { softDelete } from "../plugins/soft-delete/index.ts";
import { tenant } from "../plugins/tenant/index.ts";
import { createPostgres, postgresExecutor } from "../postgres/index.ts";
import { signLocalJwt } from "../testing/local-key.ts";

const url = process.env["SUPABASE_URL"] ?? "http://127.0.0.1:55421";
const dbUrl =
  process.env["SUPABASE_DB_URL"] ??
  "postgresql://postgres:postgres@127.0.0.1:55422/postgres";
const publishableKey =
  process.env["SUPABASE_PUBLISHABLE_KEY"] ??
  "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH";

const ACME = "00000000-0000-4000-8000-000000000001";
const USER = "00000000-0000-4000-8000-0000000000ff";
const ROAD_RUNNER = "00000000-0000-4000-8000-00000000a001";

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

describe.skipIf(!live)("Postgres executor", async () => {
  const postgres = createPostgres({ connectionString: dbUrl, max: 4 });
  afterAll(() => postgres.end());

  const claims = { sub: USER, role: "authenticated", tenant_id: ACME };
  const sb = defineSupabase(schema).use(softDelete()).use(tenant());
  const rest = sb.connect(
    createClient(url, publishableKey, {
      accessToken: () => signLocalJwt(claims),
    }),
    { claims },
  );
  const sql = sb.connect(postgresExecutor(postgres.asUser(claims)), { claims });
  const customerList = defineListQuery(sb, "customers", {
    search: ["name", "kvk"],
    facets: { status: "status", kvk: "kvk" },
    sorts: { name: [{ name: "asc" }, { id: "asc" }] },
    defaultSort: "name",
  });

  const queries: [
    string,
    (db: typeof rest | typeof sql) => Promise<unknown>,
  ][] = [
    [
      "columns and order",
      (db) =>
        db.customers
          .findMany({
            select: ["id", "name", "status", "createdAt"],
            orderBy: { name: "asc" },
          })
          .orThrow(),
    ],
    [
      "text operators",
      (db) =>
        db.customers
          .findMany({
            select: ["id"],
            where: { name: { contains: "run" }, kvk: { not: null } },
          })
          .orThrow(),
    ],
    [
      "OR and NOT",
      (db) =>
        db.customers
          .findMany({
            select: ["id"],
            where: {
              OR: [{ status: "lead" }, { kvk: "1001" }],
              NOT: { name: "x" },
            },
            orderBy: { name: "asc" },
          })
          .orThrow(),
    ],
    [
      "some / none / every",
      (db) =>
        db.customers
          .findMany({
            select: ["id"],
            where: {
              notes: { some: {} },
              locations: { every: { isPrimary: true } },
              customerTags: { none: { tag: { color: "red" } } },
            },
          })
          .orThrow(),
    ],
    [
      "to-one filters",
      (db) =>
        db.customers
          .findMany({
            select: ["id"],
            where: { organization: { slug: "acme" }, primaryContact: null },
          })
          .orThrow(),
    ],
    [
      "relations inside OR",
      (db) =>
        db.customers
          .findMany({
            select: ["id"],
            where: {
              OR: [
                { status: "lead" },
                { notes: { some: { kind: "meeting" } } },
              ],
            },
            orderBy: { name: "asc" },
          })
          .orThrow(),
    ],
    [
      "nested includes",
      (db) =>
        db.customers
          .findMany({
            select: ["id", "metadata"],
            include: {
              organization: { select: ["slug"] },
              primaryContact: { select: ["email"] },
              notes: {
                select: ["id", "kind", "body", "createdAt"],
                orderBy: { createdAt: "desc" },
                limit: 2,
              },
              customerTags: {
                select: ["tagId"],
                include: { tag: { select: ["name", "color"] } },
              },
            },
            orderBy: { name: "asc" },
          })
          .orThrow(),
    ],
    [
      "count",
      (db) => db.customers.count({ where: { status: "active" } }).orThrow(),
    ],
    [
      "relation aggregates",
      (db) =>
        db.customers
          .findMany({
            select: ["id"],
            include: {
              _sum: { notes: { id: true } },
              _max: { notes: { createdAt: true, kind: true } },
              _count: { notes: true },
            },
            orderBy: { name: "asc" },
          })
          .orThrow(),
    ],
    [
      "grouped aggregate",
      (db) =>
        db.customers
          .aggregate({
            groupBy: ["status"],
            _count: true,
            _min: { createdAt: true },
            orderBy: { status: "asc" },
          })
          .orThrow(),
    ],
    [
      "single aggregate",
      (db) =>
        db.notes
          .aggregate({ _count: true, _sum: { id: true }, _avg: { id: true } })
          .orThrow(),
    ],
    [
      "offset page",
      (db) =>
        db.customers
          .paginate({
            select: ["id"],
            page: 1,
            size: 1,
            count: "exact",
            orderBy: { name: "asc" },
          })
          .orThrow(),
    ],
    [
      "cursor page",
      (db) =>
        db.customers
          .paginate({
            select: ["id", "name"],
            after: null,
            size: 1,
            orderBy: { name: "desc" },
          })
          .orThrow(),
    ],
    [
      "findById",
      (db) =>
        db.customers
          .findById(ROAD_RUNNER, { select: ["name", "status"] })
          .orThrow(),
    ],
    [
      "list query with hostile search and unset facet",
      (db) =>
        customerList
          .run(
            db,
            customerList.parse({
              q: 'r%,(a)_"\\',
              facets: { status: ["active", "lead"], kvk: [UNSET, "1001"] },
            }).value!,
            { select: ["id", "name"] },
          )
          .orThrow(),
    ],
    [
      "list query search",
      (db) =>
        customerList
          .run(
            db,
            customerList.parse(new URLSearchParams("q=road&sort=name")).value!,
          )
          .orThrow(),
    ],
  ];

  it("aggregates only the rows RLS and plugins let the caller see", async () => {
    for (const db of [rest, sql]) {
      const groups = await db.customers
        .aggregate({ groupBy: ["status"], _count: true })
        .orThrow();
      const total = groups.reduce((sum, group) => sum + group._count, 0);
      expect(total).toBe(await db.customers.count().orThrow());
      const [roadRunner] = await db.customers
        .findMany({
          select: ["id"],
          where: { id: ROAD_RUNNER },
          include: { _count: { notes: true }, _max: { notes: { id: true } } },
        })
        .orThrow();
      expect(roadRunner?._count.notes).toBeGreaterThan(0);
      expect(roadRunner?._max.notes.id).toEqual(expect.any(Number));
    }
  });

  for (const [name, run] of queries) {
    it(`matches PostgREST: ${name}`, async () => {
      expect(await run(sql)).toEqual(await run(rest));
    });
  }

  it("hides other tenants through RLS", async () => {
    const other = sb.connect(
      postgresExecutor(
        postgres.asUser({
          sub: USER,
          role: "authenticated",
          tenant_id: "00000000-0000-4000-8000-000000000002",
        }),
      ),
      {
        tenant: "00000000-0000-4000-8000-000000000002",
      },
    );
    const rows = await other.customers.findMany({ select: ["name"] }).orThrow();
    expect(rows).toEqual([{ name: "Initech" }]);
  });

  it("writes with RETURNING, maps conflicts and supports relation filters in updateMany", async () => {
    const created = await sql.customers
      .create({ name: "SQL Co", kvk: "sql-1" } as never, {
        select: ["id", "organizationId", "status"],
      })
      .orThrow();
    expect(created).toMatchObject({ organizationId: ACME, status: "lead" });

    const duplicate = await sql.customers.create({
      name: "Dup",
      kvk: "sql-1",
    } as never);
    expect(duplicate.error).toMatchObject({
      kind: "conflict",
      constraint: "customers_organization_id_kvk_key",
    });

    const updated = await sql.customers
      .updateMany({
        where: { id: created.id, notes: { none: {} } },
        data: { status: "active" },
      })
      .orThrow();
    expect(updated).toEqual({ count: 1 });

    const upserted = await sql.customers
      .upsert({ name: "SQL Co 2", kvk: "sql-1" } as never, {
        onConflict: "customers_organization_id_kvk_key",
        select: ["id", "name", "status"],
      })
      .orThrow();
    expect(upserted).toEqual({
      id: created.id,
      name: "SQL Co 2",
      status: "active",
    });

    await sql.customers.delete(created.id, { hard: true }).orThrow();
    expect(
      (await sql.customers.delete(created.id, { hard: true })).error?.kind,
    ).toBe("not_found");
  });

  it("runs several operations in one transaction", async () => {
    await expect(
      postgres.transaction(
        async (tx) => {
          const db = sb.connect(postgresExecutor(tx), { claims });
          await db.tags
            .create({ name: "tx-tag" } as never, { returning: false })
            .orThrow();
          throw new Error("roll back");
        },
        { claims },
      ),
    ).rejects.toThrow("roll back");
    expect(await sql.tags.exists({ where: { name: "tx-tag" } }).orThrow()).toBe(
      false,
    );
  });
});
