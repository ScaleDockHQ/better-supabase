import { describe, expect, it } from "vitest";

import type { SchemaMeta } from "../../src/schema/types.ts";

import { compileSql } from "../../src/compile/sql.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { mapDbError } from "../../src/core/errors.ts";
import { IrBuilder } from "../../src/ir/build.ts";
import { decodeRows } from "../../src/ir/codec.ts";
import { defineSchema } from "../../src/schema/define.ts";
import { capturingClient, query } from "../fixtures/client.ts";
import { schema } from "../fixtures/generated-camel.ts";

const sb = defineSupabase(schema);

const ledgerMeta: SchemaMeta = {
  version: 1,
  casing: "camel",
  enums: {},
  functions: {},
  tables: {
    ledger: {
      key: "ledger",
      name: "ledger",
      schema: "public",
      kind: "table",
      columns: {
        id: {
          db: "id",
          type: "int8",
          nullable: false,
          hasDefault: true,
          codec: "bigint",
        },
        accountCode: {
          db: "account_code",
          type: "text",
          nullable: false,
          hasDefault: false,
        },
        amount: {
          db: "amount",
          type: "numeric",
          nullable: false,
          hasDefault: false,
          codec: "string",
        },
        bookedAt: {
          db: "booked_at",
          type: "timestamptz",
          nullable: false,
          hasDefault: true,
          codec: "instant",
        },
      },
      primaryKey: ["id"],
      uniqueKeys: {},
      relations: {},
      flags: {},
    },
  },
};

const selectOf = (selection: ReturnType<IrBuilder["selection"]>) => ({
  kind: "select" as const,
  table: new IrBuilder(schema.meta).table("customers"),
  selection,
  where: undefined,
  orderBy: [],
  limit: undefined,
  offset: undefined,
  count: undefined,
  head: false,
  single: undefined,
});

describe("relation aggregates", () => {
  it("renders aggregate embeds and folds them into row._max", async () => {
    const { client, last } = capturingClient(() => ({
      body: [
        {
          id: "c1",
          _max_notes: [{ id: 7, createdAt: "2026-01-02T00:00:00+00:00" }],
          _sum_notes: [{ id: 12 }],
        },
        { id: "c2", _max_notes: [{ id: null, createdAt: null }] },
      ],
    }));
    const rows = await sb
      .connect(client)
      .customers.findMany({
        select: ["id"],
        include: {
          _max: { notes: { id: true, createdAt: true } },
          _sum: { notes: { id: true } },
        },
      })
      .orThrow();

    expect(query(last())[0]).toBe(
      "select=id,_max_notes:notes!notes_customer_id_fkey(id:id.max(),createdAt:created_at.max()),_sum_notes:notes!notes_customer_id_fkey(id:id.sum())",
    );
    expect(rows).toEqual([
      {
        id: "c1",
        _max: { notes: { id: 7, createdAt: "2026-01-02T00:00:00+00:00" } },
        _sum: { notes: { id: 12 } },
      },
      { id: "c2", _max: { notes: { id: null, createdAt: null } } },
    ]);
  });

  it("compiles to a single-row subquery in SQL", () => {
    const builder = new IrBuilder(schema.meta);
    const selection = builder.selection(builder.table("customers"), ["id"], {
      _avg: { notes: { id: true } },
    });
    const plan = compileSql(selectOf(selection));
    expect(plan.rows?.text).toContain(
      `'_avg_notes', (select json_build_object('id', avg(t1."id")) from "public"."notes" as t1 where t1."customer_id" = t0."id")`,
    );
    expect(
      decodeRows(selection, [{ id: "c1", _avg_notes: { id: 2.5 } }]),
    ).toEqual([{ id: "c1", _avg: { notes: { id: 2.5 } } }]);
  });

  it("rejects sums of text columns and to-one relations", async () => {
    const { client, requests } = capturingClient();
    const db = sb.connect(client);
    const text = await db.customers.findMany({
      include: { _sum: { notes: { body: true } } },
    });
    expect(text.error?.message).toContain("_sum needs a numeric column");
    const one = await db.customers.findMany({
      include: { _max: { organization: { name: true } } as never },
    });
    expect(one.error?.message).toContain("needs a to-many relation");
    expect(requests).toHaveLength(0);
  });
});

describe("db.x.aggregate()", () => {
  it("groups, counts and measures in one request", async () => {
    const { client, last } = capturingClient(() => ({
      body: [
        { status: "active", _count: 2, _min_createdAt: "2026-01-01T00:00:00Z" },
        { status: "lead", _count: 1, _min_createdAt: "2026-02-01T00:00:00Z" },
      ],
    }));
    const groups = await sb
      .connect(client)
      .customers.aggregate({
        where: { archivedAt: null },
        groupBy: ["status"],
        _count: true,
        _min: { createdAt: true },
        orderBy: { status: "asc" },
      })
      .orThrow();

    const params = query(last());
    expect(params[0]).toBe(
      "select=status,_count:count(),_min_createdAt:created_at.min()",
    );
    expect(params).toContain("archived_at=is.null");
    expect(params).toContain("order=status.asc");
    expect(groups).toEqual([
      {
        status: "active",
        _count: 2,
        _min: { createdAt: "2026-01-01T00:00:00Z" },
      },
      {
        status: "lead",
        _count: 1,
        _min: { createdAt: "2026-02-01T00:00:00Z" },
      },
    ]);
  });

  it("returns one row without groupBy, also when nothing can match", async () => {
    const { client, requests } = capturingClient(() => ({
      body: [{ _count: 4 }],
    }));
    const db = sb.connect(client);
    expect(await db.notes.aggregate({ _count: true }).orThrow()).toEqual({
      _count: 4,
    });
    const none = await db.notes
      .aggregate({
        where: { id: { in: [] } },
        _count: true,
        _max: { id: true },
      })
      .orThrow();
    expect(none).toEqual({ _count: 0, _max: { id: null } });
    expect(requests).toHaveLength(1);
  });

  it("keeps exact int8 and numeric sums and decodes instants", async () => {
    const { client, last } = capturingClient(() => ({
      body: [
        {
          accountCode: "4000",
          _sum_amount: "12.50",
          _sum_id: "9007199254740993",
          _avg_amount: 6.25,
          _max_bookedAt: "2026-03-01T00:00:00Z",
        },
      ],
    }));
    const db = defineSupabase(defineSchema(ledgerMeta)).connect(
      client,
    ) as never as {
      ledger: {
        aggregate(args: object): PromiseLike<{ data: unknown }>;
      };
    };
    const { data } = await db.ledger.aggregate({
      groupBy: ["accountCode"],
      _sum: { amount: true, id: true },
      _avg: { amount: true },
      _max: { bookedAt: true },
    });
    expect(query(last())[0]).toBe(
      "select=accountCode:account_code,_sum_amount:amount.sum()::text,_sum_id:id.sum()::text,_avg_amount:amount.avg(),_max_bookedAt:booked_at.max()::text",
    );
    expect(data).toEqual([
      {
        accountCode: "4000",
        _sum: { amount: "12.50", id: 9007199254740993n },
        _avg: { amount: 6.25 },
        _max: { bookedAt: Temporal.Instant.from("2026-03-01T00:00:00Z") },
      },
    ]);
  });

  it("compiles to group by in SQL", () => {
    const builder = new IrBuilder(schema.meta);
    const table = builder.table("customers");
    const selection = builder.aggregation(table, {
      groupBy: ["status"],
      _count: true,
      _max: { updatedAt: true },
    });
    const plan = compileSql({ ...selectOf(selection), table });
    expect(plan.rows?.text).toBe(
      `select json_build_object('status', t0."status", '_count', count(*), '_max_updatedAt', max(t0."updated_at")) as row from "public"."customers" as t0 group by t0."status"`,
    );
  });

  it("rejects sorting by a column outside groupBy and empty aggregates", async () => {
    const { client, requests } = capturingClient();
    const db = sb.connect(client);
    const sorted = await db.customers.aggregate({
      groupBy: ["status"],
      _count: true,
      orderBy: { name: "asc" },
    });
    expect(sorted.error?.message).toContain("only sort by groupBy columns");
    const empty = await db.customers.aggregate({ groupBy: ["status"] });
    expect(empty.error?.message).toContain("needs _count, _sum");
    expect(requests).toHaveLength(0);
  });

  it("runs as a spec", async () => {
    const { client } = capturingClient(() => ({ body: [{ _count: 3 }] }));
    const spec = sb.spec.notes.aggregate({ _count: true });
    expect(spec).toEqual({
      v: 1,
      table: "notes",
      method: "aggregate",
      args: [{ _count: true }],
    });
    expect(await sb.connect(client).$run(spec).orThrow()).toEqual({
      _count: 3,
    });
  });
});

describe("aggregates disabled", () => {
  it("maps PGRST123 to invalid_request with the setting to change", () => {
    const error = mapDbError({
      code: "PGRST123",
      message: "Use of aggregate functions is not allowed",
    });
    expect(error.kind).toBe("invalid_request");
    expect(error.hint).toContain("pgrst.db_aggregates_enabled");
  });
});
