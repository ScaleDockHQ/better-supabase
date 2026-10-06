import { describe, expect, it, vi } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { DbException } from "../../src/core/errors.ts";
import { capturingClient, query } from "../fixtures/client.ts";
import { schema as camel } from "../fixtures/generated-camel.ts";
import { schema as snake } from "../fixtures/generated.ts";

const sbCamel = defineSupabase(camel);
const sbSnake = defineSupabase(snake);

describe("reads", () => {
  it("aliases camel-cased columns inside the select", async () => {
    const { client, last } = capturingClient();
    const db = sbCamel.connect(client);
    await db.customers.findMany({
      select: ["id", "organizationId", "primaryContactId"],
    });
    expect(last().path).toBe("/rest/v1/customers");
    expect(query(last())).toEqual([
      "select=id,organizationId:organization_id,primaryContactId:primary_contact_id",
      "order=id.asc",
    ]);
  });

  it("keeps snake-cased columns unaliased", async () => {
    const { client, last } = capturingClient();
    const db = sbSnake.connect(client);
    await db.customers.findMany({ select: ["id", "organization_id"] });
    expect(query(last())).toEqual([
      "select=id,organization_id",
      "order=id.asc",
    ]);
  });

  it("compiles column filters and escapes LIKE input", async () => {
    const { client, last } = capturingClient();
    const db = sbCamel.connect(client);
    await db.customers.findMany({
      select: ["id"],
      where: {
        status: { in: ["lead", "active"] },
        name: { contains: "50%_off" },
        kvk: null,
        archivedAt: { isNull: true },
        createdAt: { gte: "2026-01-01" },
      },
      orderBy: [
        { name: "asc" },
        { createdAt: { direction: "desc", nulls: "last" } },
      ],
      limit: 10,
      offset: 20,
    });
    expect(query(last())).toEqual([
      "select=id",
      "status=in.(lead,active)",
      "name=ilike.%50\\%\\_off%",
      "kvk=is.null",
      "archived_at=is.null",
      "created_at=gte.2026-01-01",
      "order=name.asc,created_at.desc.nullslast",
      "offset=20",
      "limit=10",
    ]);
  });

  it("compiles OR and NOT into logic trees with quoted values", async () => {
    const { client, last } = capturingClient();
    const db = sbCamel.connect(client);
    await db.customers.findMany({
      select: ["id"],
      where: {
        OR: [{ name: "a,b" }, { status: "lead", kvk: { not: null } }],
        NOT: { status: "archived" },
      },
    });
    expect(query(last())).toEqual([
      "select=id",
      'or=(name.eq."a,b",and(status.eq."lead",kvk.not.is.null))',
      "status=not.eq.archived",
      "order=id.asc",
    ]);
  });

  it("filters through to-many relations with some, none and every", async () => {
    const { client, last } = capturingClient();
    const db = sbCamel.connect(client);
    await db.customers.findMany({
      select: ["id"],
      where: {
        notes: { some: { kind: "call" }, none: { body: { contains: "spam" } } },
        locations: { every: { isPrimary: true } },
      },
    });
    expect(query(last())).toEqual([
      "select=id,_bs1:notes!notes_customer_id_fkey!inner(),_bs2:notes!notes_customer_id_fkey(),_bs3:locations!locations_customer_id_fkey()",
      "_bs1.kind=eq.call",
      "_bs2.body=ilike.%spam%",
      "_bs2=is.null",
      "_bs3.is_primary=not.eq.true",
      "_bs3=is.null",
      "order=id.asc",
    ]);
  });

  it("filters through to-one relations, including null checks", async () => {
    const { client, last } = capturingClient();
    const db = sbCamel.connect(client);
    await db.customers.findMany({
      select: ["id"],
      where: { organization: { slug: "acme" }, primaryContact: null },
    });
    expect(query(last())).toEqual([
      "select=id,_bs1:organizations!customers_organization_id_fkey!inner(),_bs2:contacts!customers_primary_contact_id_fkey()",
      "_bs1.slug=eq.acme",
      "_bs2=is.null",
      "order=id.asc",
    ]);
  });

  it("puts relation filters inside OR as embed null checks", async () => {
    const { client, last } = capturingClient();
    const db = sbCamel.connect(client);
    await db.customers.findMany({
      select: ["id"],
      where: { OR: [{ name: "x" }, { notes: { some: { kind: "email" } } }] },
    });
    expect(query(last())).toEqual([
      "select=id,_bs1:notes!notes_customer_id_fkey()",
      "_bs1.kind=eq.email",
      'or=(name.eq."x",_bs1.not.is.null)',
      "order=id.asc",
    ]);
  });

  it("embeds includes with nested filters, order and limits", async () => {
    const { client, last } = capturingClient();
    const db = sbCamel.connect(client);
    await db.customers.findMany({
      select: ["id", "name"],
      include: {
        organization: { select: ["name"] },
        notes: {
          select: ["id", "body"],
          where: { kind: "call" },
          orderBy: { createdAt: "desc" },
          limit: 3,
        },
        customerTags: {
          select: ["tagId"],
          include: { tag: { select: ["name", "color"] } },
        },
      },
    });
    expect(query(last())).toEqual([
      "select=id,name,organization:organizations!customers_organization_id_fkey(name),notes:notes!notes_customer_id_fkey(id,body),customerTags:customer_tags!customer_tags_customer_id_fkey(tagId:tag_id,tag:tags!customer_tags_tag_id_fkey(name,color))",
      "notes.kind=eq.call",
      "notes.order=created_at.desc",
      "order=id.asc",
      "notes.limit=3",
    ]);
  });

  it("skips the request when a filter can never match", async () => {
    const { client, requests } = capturingClient();
    const db = sbCamel.connect(client);
    const result = await db.customers.findMany({ where: { id: { in: [] } } });
    expect(result).toEqual({ ok: true, data: [], error: null });
    expect(requests).toHaveLength(0);
  });

  it("returns not_found from findById and throws from orThrow", async () => {
    const { client, last } = capturingClient(() => ({ body: [] }));
    const db = sbCamel.connect(client);
    const result = await db.customers.findById(
      "00000000-0000-4000-8000-000000000009",
    );
    expect(result.ok).toBe(false);
    expect(result.error?.kind).toBe("not_found");
    expect(result.error?.table).toBe("customers");
    expect(query(last())).toContain(
      "id=eq.00000000-0000-4000-8000-000000000009",
    );
    await expect(
      db.customers.findById("00000000-0000-4000-8000-000000000009").orThrow(),
    ).rejects.toBeInstanceOf(DbException);
  });

  it("counts with a HEAD request", async () => {
    const { client, last } = capturingClient(() => ({
      body: [],
      headers: { "content-range": "*/42" },
    }));
    const db = sbCamel.connect(client);
    const result = await db.customers.count({ where: { status: "active" } });
    expect(result.data).toBe(42);
    expect(last().method).toBe("HEAD");
    expect(last().headers.get("prefer")).toContain("count=exact");
  });

  it("paginates with a keyset cursor", async () => {
    const rows = [
      { id: "a", name: "Alpha" },
      { id: "b", name: "Beta" },
      { id: "c", name: "Gamma" },
    ];
    const { client, last } = capturingClient(() => ({ body: rows }));
    const db = sbCamel.connect(client);
    const first = await db.customers.paginate({
      select: ["id", "name"],
      orderBy: { name: "asc" },
      size: 2,
      after: null,
    });
    expect(first.data?.items).toEqual(rows.slice(0, 2));
    expect(first.data?.hasMore).toBe(true);
    const cursor = first.data?.nextCursor;
    expect(typeof cursor).toBe("string");

    await db.customers.paginate({
      select: ["id", "name"],
      orderBy: { name: "asc" },
      size: 2,
      after: cursor ?? null,
    });
    expect(query(last())).toEqual([
      "select=id,name",
      'or=(name.gt."Beta",and(name.eq."Beta",id.gt."b"))',
      "order=name.asc,id.asc",
      "limit=3",
    ]);
  });

  it("paginates by page number with a total", async () => {
    const { client, last } = capturingClient(() => ({
      body: [{ id: "a" }],
      headers: { "content-range": "20-20/21" },
    }));
    const db = sbCamel.connect(client);
    const page = await db.customers.paginate({
      select: ["id"],
      page: 3,
      size: 10,
      count: "exact",
    });
    expect(page.data?.page).toEqual({
      number: 3,
      size: 10,
      total: 21,
      pages: 3,
      hasMore: false,
    });
    expect(query(last())).toEqual([
      "select=id",
      "order=id.asc",
      "offset=20",
      "limit=11",
    ]);
  });

  it("returns an empty page with the total past the last row", async () => {
    const pastEnd = (details: string) => () => ({
      status: 416,
      body: {
        code: "PGRST103",
        details,
        hint: null,
        message: "Requested range not satisfiable",
      },
    });
    const db = sbCamel.connect(
      capturingClient(
        pastEnd("An offset of 50 was requested, but there are only 8 rows."),
      ).client,
    );
    expect(
      (await db.customers.paginate({ offset: 50, limit: 5, count: "exact" }))
        .data,
    ).toEqual({
      items: [],
      page: { number: 11, size: 5, total: 8, pages: 2, hasMore: false },
    });
    const unreadable = sbCamel.connect(capturingClient(pastEnd("")).client);
    expect(
      (
        await unreadable.customers.paginate({
          offset: 50,
          limit: 5,
          count: "exact",
        })
      ).ok,
    ).toBe(false);
    expect((await db.customers.paginate({ offset: 50, limit: 5 })).ok).toBe(
      false,
    );
  });

  it("paginates by offset and limit with a total in one request", async () => {
    const { client, requests, last } = capturingClient(() => ({
      body: [{ id: "a" }],
      headers: { "content-range": "7-7/8" },
    }));
    const db = sbCamel.connect(client);
    const page = await db.customers.paginate({
      select: ["id"],
      offset: 7,
      limit: 5,
      count: "exact",
    });
    expect(page.data).toEqual({
      items: [{ id: "a" }],
      page: { number: 2, size: 5, total: 8, pages: 2, hasMore: false },
    });
    expect(requests).toHaveLength(1);
    expect(last().headers.get("prefer")).toContain("count=exact");
    expect(query(last())).toEqual([
      "select=id",
      "order=id.asc",
      "offset=7",
      "limit=6",
    ]);
  });
});

describe("writes", () => {
  it("inserts with mapped columns and returns the row", async () => {
    const { client, last } = capturingClient(() => ({
      status: 201,
      body: [{ id: "new", name: "Acme" }],
    }));
    const db = sbCamel.connect(client);
    const created = await db.customers
      .create(
        { organizationId: "org", name: "Acme", primaryContactId: null },
        { select: ["id", "name"] },
      )
      .orThrow();
    expect(created).toEqual({ id: "new", name: "Acme" });
    expect(last().method).toBe("POST");
    expect(last().body).toEqual({
      organization_id: "org",
      name: "Acme",
      primary_contact_id: null,
    });
    expect(query(last())).toEqual(["select=id,name"]);
  });

  it("upserts on a named unique key", async () => {
    const { client, last } = capturingClient(() => ({
      status: 201,
      body: [{ id: "x" }],
    }));
    const db = sbCamel.connect(client);
    await db.customers.upsert(
      { organizationId: "org", name: "Acme", kvk: "123" },
      { onConflict: "customers_organization_id_kvk_key", select: ["id"] },
    );
    expect(query(last())).toEqual([
      "on_conflict=organization_id,kvk",
      "select=id",
    ]);
    expect(last().headers.get("prefer")).toContain(
      "resolution=merge-duplicates",
    );
  });

  it("reports a stale row for optimistic concurrency", async () => {
    let call = 0;
    const { client, requests } = capturingClient(() => {
      call += 1;
      return call === 1
        ? { body: [] }
        : { body: [], headers: { "content-range": "*/1" } };
    });
    const db = sbCamel.connect(client);
    const result = await db.customers.update(
      "c1",
      { name: "New" },
      { expect: { updatedAt: "2026-01-01T00:00:00Z" } },
    );
    expect(result.error?.kind).toBe("stale");
    expect(query(requests[0] ?? (undefined as never))).toEqual([
      "id=eq.c1",
      "updated_at=eq.2026-01-01T00:00:00Z",
      "select=id,organizationId:organization_id,name,kvk,status,primaryContactId:primary_contact_id,metadata,createdBy:created_by,updatedBy:updated_by,archivedAt:archived_at,createdAt:created_at,updatedAt:updated_at,logoPath:logo_path",
    ]);
  });

  it("updates with a where condition and returns not_found in one request", async () => {
    const { client, requests } = capturingClient(() => ({ body: [] }));
    const db = sbCamel.connect(client);
    const result = await db.customers.update(
      "c1",
      { name: "New" },
      { where: { organizationId: "t", status: { in: ["lead", "active"] } } },
    );
    expect(result.error?.kind).toBe("not_found");
    expect(requests).toHaveLength(1);
    expect(query(requests[0]!).slice(0, 3)).toEqual([
      "id=eq.c1",
      "organization_id=eq.t",
      "status=in.(lead,active)",
    ]);
    expect(requests[0]!.headers.get("prefer")).toContain(
      "return=representation",
    );
  });

  it("returns the row when the where condition matches", async () => {
    const { client } = capturingClient(() => ({
      body: [{ id: "c1", name: "New" }],
    }));
    const db = sbCamel.connect(client);
    const row = await db.customers
      .update(
        "c1",
        { name: "New" },
        { where: { organizationId: "t" }, select: ["id", "name"] },
      )
      .orThrow();
    expect(row).toEqual({ id: "c1", name: "New" });
  });

  it("probes with the where condition before calling a row stale", async () => {
    let call = 0;
    const { client, requests } = capturingClient(() => {
      call += 1;
      return call === 1
        ? { body: [] }
        : { body: [], headers: { "content-range": "*/0" } };
    });
    const db = sbCamel.connect(client);
    const result = await db.customers.update(
      "c1",
      { name: "New" },
      {
        where: { organizationId: "t" },
        expect: { status: { in: ["lead"] } },
      },
    );
    expect(result.error?.kind).toBe("not_found");
    expect(requests).toHaveLength(2);
    expect(query(requests[0]!).slice(0, 3)).toEqual([
      "id=eq.c1",
      "organization_id=eq.t",
      "status=in.(lead)",
    ]);
    expect(query(requests[1]!)).toEqual([
      "select=*",
      "id=eq.c1",
      "organization_id=eq.t",
    ]);
  });

  it("returns the updated rows from updateMany with returning", async () => {
    const { client, last } = capturingClient(() => ({
      body: [{ id: "c1", createdAt: "2026-01-01T00:00:00Z" }],
    }));
    const db = sbCamel.connect(client);
    const rows = await db.customers
      .updateMany({
        where: { status: "lead" },
        data: { status: "active" },
        returning: true,
        select: ["id", "createdAt"],
      })
      .orThrow();
    expect(rows).toEqual([{ id: "c1", createdAt: "2026-01-01T00:00:00Z" }]);
    expect(query(last())).toEqual([
      "status=eq.lead",
      "select=id,createdAt:created_at",
    ]);
    expect(last().headers.get("prefer")).toContain("return=representation");
  });

  it("counts updateMany and deleteMany without returning", async () => {
    const { client, requests } = capturingClient(() => ({
      status: 204,
      headers: { "content-range": "*/3" },
    }));
    const db = sbCamel.connect(client);
    const updated = await db.customers
      .updateMany({ where: { status: "lead" }, data: { status: "active" } })
      .orThrow();
    const deleted = await db.customers
      .deleteMany({ where: { status: "lead" } })
      .orThrow();
    expect(updated).toEqual({ count: 3 });
    expect(deleted).toEqual({ count: 3 });
    expect(requests.map((request) => request.params.get("select"))).toEqual([
      null,
      null,
    ]);
  });

  it("returns the deleted rows from deleteMany with returning", async () => {
    const { client, last } = capturingClient(() => ({
      body: [{ id: "c1" }, { id: "c2" }],
    }));
    const db = sbCamel.connect(client);
    const rows = await db.customers
      .deleteMany({
        where: { status: "archived" },
        returning: true,
        select: ["id"],
      })
      .orThrow();
    expect(rows).toEqual([{ id: "c1" }, { id: "c2" }]);
    expect(last().method).toBe("DELETE");
    expect(query(last())).toEqual(["status=eq.archived", "select=id"]);
  });

  it("maps unique violations to conflict errors with columns", async () => {
    const { client } = capturingClient(() => ({
      status: 409,
      body: {
        code: "23505",
        message:
          'duplicate key value violates unique constraint "tags_organization_id_name_key"',
        details: "Key (organization_id, name)=(o, vip) already exists.",
        hint: null,
      },
    }));
    const db = sbCamel.connect(client);
    const result = await db.tags.create({ organizationId: "o", name: "vip" });
    expect(result.error).toMatchObject({
      kind: "conflict",
      status: 409,
      constraint: "tags_organization_id_name_key",
      columns: ["organization_id", "name"],
      table: "tags",
    });
  });

  it("hints at missing Data API grants on permission errors", async () => {
    const reply = (message: string) =>
      capturingClient(() => ({
        status: 403,
        body: { code: "42501", message, details: null, hint: null },
      })).client;
    const denied = await sbCamel
      .connect(reply("permission denied for table tags"))
      .tags.findMany();
    expect(denied.error).toMatchObject({
      kind: "forbidden",
      status: 403,
      hint: expect.stringContaining("add tags to `expose`"),
    });
    const rls = await sbCamel
      .connect(
        reply('new row violates row-level security policy for table "tags"'),
      )
      .tags.create({ organizationId: "o", name: "vip" });
    expect(rls.error?.kind).toBe("forbidden");
    expect(rls.error?.hint).toBeUndefined();
  });

  it("deletes by composite key and reports not_found for zero rows", async () => {
    const { client, last } = capturingClient(() => ({
      status: 204,
      headers: { "content-range": "*/0" },
    }));
    const db = sbCamel.connect(client);
    const result = await db.customerTags.delete({
      customerId: "c",
      tagId: "t",
    });
    expect(result.error?.kind).toBe("not_found");
    expect(last().method).toBe("DELETE");
    expect(query(last())).toEqual([
      "customer_id=eq.c",
      "tag_id=eq.t",
      "select=customerId:customer_id,tagId:tag_id",
    ]);
  });

  it("rejects relation filters in updateMany on PostgREST", async () => {
    const { client } = capturingClient();
    const db = sbCamel.connect(client);
    const result = await db.customers.updateMany({
      where: { notes: { some: {} } },
      data: { status: "active" },
    });
    expect(result.error?.kind).toBe("invalid_request");
  });
});

describe("events", () => {
  it("reports queries and mutations without affecting results", async () => {
    const { client } = capturingClient(() => ({
      status: 201,
      body: [{ id: "x" }],
    }));
    const betterSupabase = defineSupabase(camel);
    const seen: string[] = [];
    const off = betterSupabase.on("mutation", (event) => {
      seen.push(`${event.table}:${event.kind}`);
      throw new Error("ignored");
    });
    betterSupabase.on("query", (event) =>
      seen.push(`query:${event.operation}`),
    );
    const original = console.error;
    console.error = () => {};
    const result = await betterSupabase
      .connect(client)
      .tags.create({ organizationId: "o", name: "n" });
    console.error = original;
    off();
    expect(result.ok).toBe(true);
    expect(seen).toEqual(["query:insert", "tags:insert"]);
  });
});

describe("row caps and default order", () => {
  it("orders findMany by the primary key unless orderBy is given", async () => {
    const { client, requests } = capturingClient();
    const db = sbCamel.connect(client);
    await db.customers.findMany({ select: ["id"] });
    await db.customers.findMany({ select: ["id"], orderBy: { name: "desc" } });
    await db.customers.findFirst({ select: ["id"] });
    expect(requests.map(query)).toEqual([
      ["select=id", "order=id.asc"],
      ["select=id", "order=name.desc"],
      ["select=id", "limit=1"],
    ]);
  });

  it("orders by the database names of a camel-cased primary key", async () => {
    const { client, last } = capturingClient();
    const db = sbCamel.connect(client);
    await db.customerTags.findMany({ select: ["customerId"] });
    await db.customerTags.findMany({ select: ["customerId"] });
    expect(query(last())).toEqual([
      "select=customerId:customer_id",
      "order=customer_id.asc,tag_id.asc",
    ]);
  });

  it("flags unbounded reads that hit maxRows and warns once per table", async () => {
    const rows = [{ id: "a" }, { id: "b" }];
    const { client } = capturingClient(() => ({ body: rows }));
    const warn = vi.fn();
    const logger = { debug() {}, info() {}, warn, error() {} };
    const betterSupabase = defineSupabase(camel, { maxRows: 2, logger });
    const truncated: boolean[] = [];
    betterSupabase.on("query", (event) => truncated.push(event.truncated));
    const db = betterSupabase.connect(client);

    const all = await db.customers.findMany({ select: ["id"] });
    await db.customers.findMany({ select: ["id"] });
    await db.customers.findMany({ select: ["id"], limit: 2 });

    expect(all.data).toEqual(rows);
    expect(truncated).toEqual([true, true, false]);
    expect(warn).toHaveBeenCalledTimes(1);
    expect(warn).toHaveBeenCalledWith(
      expect.stringContaining("customers returned 2 rows"),
      { table: "customers", maxRows: 2 },
    );
  });
});
