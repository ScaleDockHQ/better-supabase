import { describe, expect, it } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import { actor } from "../../src/plugins/actor/index.ts";
import { softDelete } from "../../src/plugins/soft-delete/index.ts";
import { tenant } from "../../src/plugins/tenant/index.ts";
import { timestamps } from "../../src/plugins/timestamps/index.ts";
import { validation } from "../../src/plugins/validation/index.ts";
import { capturingClient, query } from "../fixtures/client.ts";
import { schema } from "../fixtures/generated-camel.ts";
import { validators } from "../fixtures/generated-camel.zod.ts";

const NOW = Temporal.Instant.from("2026-09-24T10:00:00Z");
const ORG = "00000000-0000-4000-8000-000000000001";
const USER = "00000000-0000-4000-8000-0000000000aa";

const base = defineSupabase(schema, { now: () => NOW });

describe("timestamps", () => {
  const betterSupabase = base.use(timestamps());

  it("stamps inserts and updates without overriding explicit values", async () => {
    const { client, requests } = capturingClient(() => ({
      status: 201,
      body: [{ id: "c" }],
    }));
    const db = betterSupabase.connect(client);
    await db.customers.create(
      { organizationId: ORG, name: "A", createdAt: "2020-01-01T00:00:00Z" },
      { select: ["id"] },
    );
    await db.customers.update("c", { name: "B" }, { select: ["id"] });
    expect(requests[0]?.body).toEqual({
      organization_id: ORG,
      name: "A",
      created_at: "2020-01-01T00:00:00Z",
      updated_at: NOW.toString(),
    });
    expect(requests[1]?.body).toEqual({
      name: "B",
      updated_at: NOW.toString(),
    });
  });

  it("leaves createdAt alone on upserts that may update", async () => {
    const { client, last } = capturingClient(() => ({
      status: 201,
      body: [{ id: "c" }],
    }));
    await betterSupabase
      .connect(client)
      .customers.upsert(
        { organizationId: ORG, name: "A", kvk: "1" },
        { onConflict: "customers_organization_id_kvk_key", select: ["id"] },
      );
    expect(last().body).toEqual({
      organization_id: ORG,
      name: "A",
      kvk: "1",
      updated_at: NOW.toString(),
    });
  });
});

describe("softDelete", () => {
  const betterSupabase = base.use(softDelete());

  it("hides deleted rows, with opt-outs for the root table", async () => {
    const { client, requests } = capturingClient();
    const db = betterSupabase.connect(client);
    await db.customers.findMany({ select: ["id"] });
    await db.customers.findMany({ select: ["id"], withDeleted: true });
    await db.customers.findMany({ select: ["id"], onlyDeleted: true });
    expect(requests.map(query)).toEqual([
      ["select=id", "archived_at=is.null", "order=id.asc"],
      ["select=id", "order=id.asc"],
      ["select=id", "archived_at=not.is.null", "order=id.asc"],
    ]);
  });

  it("scopes includes and relation filters, keeping every() correct", async () => {
    const { client, last } = capturingClient();
    const db = betterSupabase.connect(client);
    await db.organizations.findMany({
      select: ["id"],
      where: { customers: { every: { status: "active" } } },
      include: { customers: { select: ["id"] } },
    });
    expect(query(last())).toEqual([
      "select=id,customers:customers!customers_organization_id_fkey(id),_bs1:customers!customers_organization_id_fkey()",
      "customers.archived_at=is.null",
      "_bs1.archived_at=is.null",
      "_bs1.status=not.eq.active",
      "_bs1=is.null",
      "order=id.asc",
    ]);
  });

  it("turns delete into an update without RETURNING", async () => {
    const { client, last } = capturingClient(() => ({
      status: 204,
      headers: { "content-range": "*/1" },
    }));
    const result = await betterSupabase.connect(client).customers.delete("c");
    expect(result.ok).toBe(true);
    expect(last().method).toBe("PATCH");
    expect(last().body).toEqual({ archived_at: NOW.toString() });
    expect(query(last())).toEqual(["id=eq.c", "archived_at=is.null"]);
    expect(last().headers.get("prefer")).not.toContain("return=representation");
  });

  it("deletes for real with hard: true and restores", async () => {
    const { client, requests } = capturingClient(() => ({
      status: 204,
      headers: { "content-range": "*/1" },
    }));
    const db = betterSupabase.connect(client);
    await db.customers.delete("c", { hard: true });
    await db.customers.restore("c");
    expect(requests[0]?.method).toBe("DELETE");
    expect(query(requests[0] ?? (undefined as never))).toEqual([
      "id=eq.c",
      "select=id",
    ]);
    expect(requests[1]?.method).toBe("PATCH");
    expect(requests[1]?.body).toEqual({ archived_at: null });
    expect(query(requests[1] ?? (undefined as never))).toEqual(["id=eq.c"]);
  });

  it("leaves tables without the flag alone", async () => {
    const { client, last } = capturingClient(() => ({
      status: 204,
      headers: { "content-range": "*/1" },
    }));
    await betterSupabase.connect(client).tags.delete("t");
    expect(last().method).toBe("DELETE");
  });
});

describe("tenant", () => {
  const betterSupabase = base.use(tenant());

  it("fails closed without a tenant and sends nothing", async () => {
    const { client, requests } = capturingClient();
    const result = await betterSupabase.connect(client).customers.findMany();
    expect(result.error?.kind).toBe("forbidden");
    expect(requests).toHaveLength(0);
  });

  it("scopes reads to the tenant from context or claims", async () => {
    const { client, requests } = capturingClient();
    await betterSupabase
      .connect(client, { tenant: ORG })
      .customers.findMany({ select: ["id"] });
    await betterSupabase
      .connect(client, { claims: { tenant_id: ORG } })
      .tags.findMany({ select: ["id"] });
    expect(query(requests[0] ?? (undefined as never))).toEqual([
      "select=id",
      `organization_id=eq.${ORG}`,
      "order=id.asc",
    ]);
    expect(query(requests[1] ?? (undefined as never))).toEqual([
      "select=id",
      `organization_id=eq.${ORG}`,
      "order=id.asc",
    ]);
  });

  it("never reads the tenant from user_metadata", async () => {
    const { client, requests } = capturingClient();
    const result = await betterSupabase
      .connect(client, {
        claims: { sub: ORG, user_metadata: { tenant_id: ORG } },
      })
      .customers.findMany();
    expect(result.error?.kind).toBe("forbidden");
    expect(requests).toHaveLength(0);
  });

  it("fills the tenant on insert and rejects other tenants", async () => {
    const { client, last, requests } = capturingClient(() => ({
      status: 201,
      body: [{ id: "t" }],
    }));
    const db = betterSupabase.connect(client, { tenant: ORG });
    await db.tags.create({ name: "vip" } as never, { select: ["id"] });
    expect(last().body).toEqual({ name: "vip", organization_id: ORG });
    const other = await db.tags.create({ organizationId: "other", name: "x" });
    expect(other.error?.kind).toBe("forbidden");
    expect(requests).toHaveLength(1);
  });

  it("skips the filter with allTenants", async () => {
    const { client, last } = capturingClient();
    await betterSupabase
      .connect(client)
      .customers.findMany({ select: ["id"], allTenants: true });
    expect(query(last())).toEqual(["select=id", "order=id.asc"]);
  });
});

describe("actor", () => {
  it("stamps createdBy and updatedBy from the context actor", async () => {
    const betterSupabase = base.use(actor());
    const { client, requests } = capturingClient(() => ({
      status: 201,
      body: [{ id: "c" }],
    }));
    const db = betterSupabase.connect(client, {
      actor: { id: USER, kind: "user" },
    });
    await db.customers.create(
      { organizationId: ORG, name: "A" },
      { select: ["id"] },
    );
    await db.customers.update("c", { name: "B" }, { select: ["id"] });
    expect(requests[0]?.body).toEqual({
      organization_id: ORG,
      name: "A",
      created_by: USER,
      updated_by: USER,
    });
    expect(requests[1]?.body).toEqual({ name: "B", updated_by: USER });
  });

  it("records who soft-deleted a row", async () => {
    const betterSupabase = base.use(actor()).use(softDelete());
    const { client, last } = capturingClient(() => ({
      status: 204,
      headers: { "content-range": "*/1" },
    }));
    await betterSupabase
      .connect(client, { actor: { id: USER, kind: "user" } })
      .customers.delete("c");
    expect(last().body).toEqual({
      archived_at: NOW.toString(),
      updated_by: USER,
    });
  });
});

describe("validation", () => {
  const betterSupabase = base
    .use(validation({ schemas: validators }))
    .use(tenant());

  it("rejects invalid writes before sending them", async () => {
    const { client, requests } = capturingClient();
    const db = betterSupabase.connect(client, { tenant: ORG });
    const result = await db.customers.create({
      name: "A",
      status: "deleted",
    } as never);
    expect(result.error).toMatchObject({ kind: "validation", status: 422 });
    expect(
      result.error?.kind === "validation" && result.error.issues[0]?.path,
    ).toEqual(["status"]);
    expect(requests).toHaveLength(0);
  });

  it("runs after other plugins and prefixes bulk issues with the row index", async () => {
    const { client, requests } = capturingClient(() => ({
      status: 201,
      body: [],
    }));
    const db = betterSupabase.connect(client, { tenant: ORG });
    expect(
      (await db.customers.create({ name: "A" } as never, { returning: false }))
        .ok,
    ).toBe(true);
    const bulk = await db.tags.createMany([
      { name: "a" },
      { name: "b", color: "pink" },
    ] as never);
    expect(
      bulk.error?.kind === "validation" && bulk.error.issues[0]?.path,
    ).toEqual([1, "color"]);
    expect(requests).toHaveLength(1);
  });
});
