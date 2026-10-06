import { createClient } from "@supabase/supabase-js";
import { afterAll, describe, expect, it } from "vitest";

import type { AsyncResult } from "../../src/core/result.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { defineListQuery } from "../../src/list/index.ts";
import { actor } from "../../src/plugins/actor/index.ts";
import { softDelete } from "../../src/plugins/soft-delete/index.ts";
import { tenant } from "../../src/plugins/tenant/index.ts";
import { timestamps } from "../../src/plugins/timestamps/index.ts";
import { defineSchema } from "../../src/schema/define.ts";
import { signLocalJwt } from "../../src/testing/local-key.ts";
import { schema } from "../fixtures/generated-camel.ts";

const url = process.env["SUPABASE_URL"] ?? "http://127.0.0.1:55421";
const secretKey =
  process.env["SUPABASE_SECRET_KEY"] ??
  "sb_secret_N7UND0UgjKTVK-Uodkm0Hg_xSvEMPvz";
const publishableKey =
  process.env["SUPABASE_PUBLISHABLE_KEY"] ??
  "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH";

const ACME = "00000000-0000-4000-8000-000000000001";
const GLOBEX = "00000000-0000-4000-8000-000000000002";
const ROAD_RUNNER = "00000000-0000-4000-8000-00000000a001";
const ANVIL = "00000000-0000-4000-8000-00000000a002";
const INITECH = "00000000-0000-4000-8000-00000000a003";

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
const betterSupabase = defineSupabase(schema);
const admin = betterSupabase.connect(
  createClient(url, secretKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  }),
);

async function asOrgMember(orgId: string) {
  const token = await signLocalJwt({
    sub: "00000000-0000-4000-8000-0000000000ff",
    tenant_id: orgId,
  });
  return betterSupabase.connect(
    createClient(url, publishableKey, {
      accessToken: async () => token,
    }),
  );
}

describe.skipIf(!live)("PostgREST integration", () => {
  const created: string[] = [];

  afterAll(async () => {
    if (created.length > 0)
      await admin.customers.deleteMany({ where: { id: { in: created } } });
  });

  it("decodes timestamptz to Temporal.Instant and filters with it exactly", async () => {
    const customers = schema.meta.tables["customers"]!;
    const instants = defineSupabase(
      defineSchema({
        ...schema.meta,
        tables: {
          ...schema.meta.tables,
          customers: {
            ...customers,
            columns: {
              ...customers.columns,
              createdAt: {
                ...customers.columns["createdAt"]!,
                codec: "instant",
              },
            },
          },
        },
      }),
    ).connect(
      createClient(url, secretKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      }),
    ) as unknown as {
      customers: {
        findMany(
          args: object,
        ): AsyncResult<{ id: string; createdAt: unknown }[]>;
      };
    };
    const [first] = await instants.customers
      .findMany({ select: ["id", "createdAt"], limit: 1 })
      .orThrow();
    expect(first?.createdAt).toBeInstanceOf(Temporal.Instant);
    const same = await instants.customers
      .findMany({
        select: ["id"],
        where: { id: first?.id, createdAt: first?.createdAt },
      })
      .orThrow();
    expect(same.map((row) => row.id)).toEqual([first?.id]);

    const endless = await admin.customers
      .create(
        {
          organizationId: ACME,
          name: "Endless Co",
          kvk: "it-infinity",
          createdAt: "infinity",
        },
        { select: ["id"] },
      )
      .orThrow();
    const infinite = await instants.customers.findMany({
      select: ["id", "createdAt"],
      where: { id: endless.id },
    });
    await admin.customers.delete(endless.id).orThrow();
    expect(infinite.error).toMatchObject({
      kind: "invalid_value",
      column: "createdAt",
    });
  });

  it("filters with some, none and every against real data", async () => {
    const withNotes = await admin.customers
      .findMany({ select: ["id"], where: { notes: { some: {} } } })
      .orThrow();
    expect(withNotes.map((row) => row.id)).toEqual([ROAD_RUNNER]);

    const withoutMeetings = await admin.customers
      .findMany({
        select: ["id"],
        where: { notes: { none: { kind: "meeting" } } },
        orderBy: { name: "asc" },
      })
      .orThrow();
    expect(withoutMeetings.map((row) => row.id)).toEqual([ANVIL, INITECH]);

    const allPrimary = await admin.customers
      .findMany({
        select: ["id"],
        where: { locations: { every: { isPrimary: true } } },
        orderBy: { name: "asc" },
      })
      .orThrow();
    expect(allPrimary.map((row) => row.id)).toEqual([
      ANVIL,
      INITECH,
      ROAD_RUNNER,
    ]);
  });

  it("combines relation filters inside OR", async () => {
    const rows = await admin.customers
      .findMany({
        select: ["id"],
        where: {
          OR: [
            { status: "lead" },
            { customerTags: { some: { tag: { name: "VIP" } } } },
          ],
        },
        orderBy: { name: "asc" },
      })
      .orThrow();
    expect(rows.map((row) => row.id)).toEqual([ANVIL, ROAD_RUNNER]);
  });

  it("filters by to-one relations and null relations", async () => {
    const acme = await admin.customers
      .findMany({ select: ["id"], where: { organization: { slug: "globex" } } })
      .orThrow();
    expect(acme.map((row) => row.id)).toEqual([INITECH]);

    const noContact = await admin.customers
      .findMany({
        select: ["id"],
        where: { primaryContact: null },
        orderBy: { name: "asc" },
      })
      .orThrow();
    expect(noContact.map((row) => row.id)).toEqual([ANVIL, INITECH]);
  });

  it("loads nested includes with camel-cased keys", async () => {
    const customer = await admin.customers
      .findById(ROAD_RUNNER, {
        select: ["name"],
        include: {
          organization: { select: ["slug"] },
          customerTags: {
            select: ["tagId"],
            include: { tag: { select: ["name", "color"] } },
          },
          notes: { select: ["kind", "body"], limit: 1 },
        },
      })
      .orThrow();
    expect(customer).toEqual({
      name: "Road Runner Inc",
      organization: { slug: "acme" },
      customerTags: [
        {
          tagId: "00000000-0000-4000-8000-00000000b001",
          tag: { name: "VIP", color: "green" },
        },
      ],
      notes: [{ kind: "meeting", body: "Kickoff" }],
    });
  });

  it("counts, checks existence and paginates by cursor", async () => {
    expect(await admin.customers.count().orThrow()).toBeGreaterThanOrEqual(3);
    expect(
      await admin.customers.exists({ where: { kvk: "2001" } }).orThrow(),
    ).toBe(true);

    const first = await admin.customers
      .paginate({
        select: ["id", "name"],
        orderBy: { name: "asc" },
        size: 2,
        after: null,
        where: { id: { in: [ROAD_RUNNER, ANVIL, INITECH] } },
      })
      .orThrow();
    expect(first.items.map((row) => row.id)).toEqual([ANVIL, INITECH]);
    expect(first.hasMore).toBe(true);
    const second = await admin.customers
      .paginate({
        select: ["id", "name"],
        orderBy: { name: "asc" },
        size: 2,
        after: first.nextCursor,
        where: { id: { in: [ROAD_RUNNER, ANVIL, INITECH] } },
      })
      .orThrow();
    expect(second.items.map((row) => row.id)).toEqual([ROAD_RUNNER]);
    expect(second.hasMore).toBe(false);
  });

  it("pages by offset and limit with an exact total", async () => {
    const where = { id: { in: [ROAD_RUNNER, ANVIL, INITECH] } };
    const page = await admin.customers
      .paginate({
        select: ["id"],
        orderBy: { name: "asc" },
        offset: 1,
        limit: 1,
        count: "exact",
        where,
      })
      .orThrow();
    expect(page.items.map((row) => row.id)).toEqual([INITECH]);
    expect(page.page).toEqual({
      number: 2,
      size: 1,
      total: 3,
      pages: 3,
      hasMore: true,
    });
  });

  it("writes, detects conflicts and deletes", async () => {
    const customer = await admin.customers
      .create(
        { organizationId: ACME, name: "Integration Co", kvk: "it-1" },
        { select: ["id", "status", "updatedAt"] },
      )
      .orThrow();
    created.push(customer.id);
    expect(customer.status).toBe("lead");

    const duplicate = await admin.customers.create({
      organizationId: ACME,
      name: "Dup",
      kvk: "it-1",
    });
    expect(duplicate.error).toMatchObject({
      kind: "conflict",
      constraint: "customers_organization_id_kvk_key",
      columns: ["organization_id", "kvk"],
    });

    const invalid = await admin.customers.update(customer.id, {
      status: "bogus" as "lead",
    });
    expect(invalid.error?.kind).toBe("check");

    const stale = await admin.customers.update(
      customer.id,
      { name: "X" },
      { expect: { updatedAt: "2000-01-01T00:00:00Z" } },
    );
    expect(stale.error?.kind).toBe("stale");

    const updated = await admin.customers
      .update(
        customer.id,
        { status: "active" },
        { expect: { updatedAt: customer.updatedAt }, select: ["status"] },
      )
      .orThrow();
    expect(updated.status).toBe("active");

    const upserted = await admin.customers
      .upsert(
        { organizationId: ACME, name: "Integration Co 2", kvk: "it-1" },
        {
          onConflict: "customers_organization_id_kvk_key",
          select: ["id", "name"],
        },
      )
      .orThrow();
    expect(upserted).toEqual({ id: customer.id, name: "Integration Co 2" });

    await admin.customers.delete(customer.id).orThrow();
    const gone = await admin.customers.delete(customer.id);
    expect(gone.error?.kind).toBe("not_found");
  });

  it("updates with where and returns rows from updateMany and deleteMany", async () => {
    const rows = await admin.customers
      .createMany(
        [
          { organizationId: ACME, name: "Cond A", kvk: "cond-a" },
          { organizationId: ACME, name: "Cond B", kvk: "cond-b" },
        ],
        { select: ["id"] },
      )
      .orThrow();
    const ids = rows.map((row) => row.id);

    const wrongTenant = await admin.customers.update(
      ids[0]!,
      { name: "Moved" },
      { where: { organizationId: GLOBEX } },
    );
    expect(wrongTenant.error?.kind).toBe("not_found");

    const moved = await admin.customers
      .update(
        ids[0]!,
        { name: "Moved" },
        { where: { organizationId: ACME }, select: ["name"] },
      )
      .orThrow();
    expect(moved).toEqual({ name: "Moved" });

    const activated = await admin.customers
      .updateMany({
        where: { id: { in: ids }, status: "lead" },
        data: { status: "active" },
        returning: true,
        select: ["id", "status"],
      })
      .orThrow();
    expect(activated.map((row) => row.status)).toEqual(["active", "active"]);

    const deleted = await admin.customers
      .deleteMany({
        where: { id: { in: ids } },
        returning: true,
        select: ["id"],
      })
      .orThrow();
    expect(deleted.map((row) => row.id).sort()).toEqual([...ids].sort());
  });

  it("sorts by a column of a to-one relation", async () => {
    const seeded = { id: { in: [ROAD_RUNNER, ANVIL, INITECH] } };
    const byOrganization = await admin.customers
      .findMany({
        where: seeded,
        select: ["id"],
        orderBy: [{ organization: { name: "desc" } }, { name: "asc" }],
      })
      .orThrow();
    expect(byOrganization.map((row) => row.id)).toEqual([
      INITECH,
      ANVIL,
      ROAD_RUNNER,
    ]);
    const included = await admin.customers
      .findMany({
        where: seeded,
        select: ["id"],
        include: { organization: { select: ["name"] } },
        orderBy: [{ organization: { name: "asc" } }, { name: "desc" }],
      })
      .orThrow();
    expect(included.map((row) => [row.id, row.organization.name])).toEqual([
      [ROAD_RUNNER, "Acme"],
      [ANVIL, "Acme"],
      [INITECH, "Globex"],
    ]);
  });

  it("matches a JSON array inside a jsonb column with contains", async () => {
    const note = await admin.notes
      .create(
        {
          organizationId: ACME,
          customerId: ROAD_RUNNER,
          body: "Json containment",
          attachments: [{ type: "image", id: 1 }, { type: "text" }],
        },
        { select: ["id"] },
      )
      .orThrow();

    const found = await admin.notes
      .findMany({
        where: { id: note.id, attachments: { contains: [{ type: "image" }] } },
        select: ["id"],
      })
      .orThrow();
    expect(found).toEqual([{ id: note.id }]);

    const inOr = await admin.notes
      .findMany({
        where: {
          id: note.id,
          OR: [
            { attachments: { contains: [{ type: "video" }] } },
            { attachments: { contains: [{ type: "text" }] } },
          ],
        },
        select: ["id"],
      })
      .orThrow();
    expect(inOr).toEqual([{ id: note.id }]);

    const none = await admin.notes
      .findMany({
        where: { id: note.id, attachments: { contains: [{ type: "video" }] } },
        select: ["id"],
      })
      .orThrow();
    expect(none).toEqual([]);
    await admin.notes.delete(note.id).orThrow();
  });

  it("filters by the text at a json path", async () => {
    const note = await admin.notes
      .create(
        {
          organizationId: ACME,
          customerId: ROAD_RUNNER,
          body: "Json path",
          attachments: { owner: { id: "u1", rank: 2 }, replacedBy: null },
        },
        { select: ["id"] },
      )
      .orThrow();
    const find = (where: object) =>
      admin.notes
        .findMany({ where: { id: note.id, ...where }, select: ["id"] })
        .orThrow();

    expect(
      await find({ attachments: { path: ["owner", "id"], eq: "u1" } }),
    ).toHaveLength(1);
    expect(
      await find({ attachments: { path: ["owner", "rank"], in: [1, 2] } }),
    ).toHaveLength(1);
    expect(
      await find({ attachments: { path: ["replacedBy"], isNull: true } }),
    ).toHaveLength(1);
    expect(
      await find({ attachments: { path: ["owner"], isNull: false } }),
    ).toHaveLength(1);
    expect(
      await find({
        OR: [
          { attachments: { path: ["owner", "id"], eq: "u2" } },
          { attachments: { path: ["missing"], isNull: false } },
        ],
      }),
    ).toHaveLength(0);
    await admin.notes.delete(note.id).orThrow();
  });

  it("runs the plugin stack as a tenant user under RLS", async () => {
    const token = await signLocalJwt({
      sub: "00000000-0000-4000-8000-0000000000ff",
      tenant_id: ACME,
    });
    const user = betterSupabase
      .use(timestamps())
      .use(softDelete())
      .use(tenant())
      .use(actor())
      .connect(
        createClient(url, publishableKey, { accessToken: async () => token }),
        {
          claims: { tenant_id: ACME },
          actor: { id: "00000000-0000-4000-8000-0000000000ff", kind: "user" },
        },
      );

    const row = await user.customers
      .create({ name: "Plugin Co" } as never, {
        select: ["id", "organizationId", "createdBy"],
      })
      .orThrow();
    created.push(row.id);
    expect(row.organizationId).toBe(ACME);
    expect(row.createdBy).toBe("00000000-0000-4000-8000-0000000000ff");

    await user.customers.delete(row.id).orThrow();
    expect((await user.customers.findById(row.id)).error?.kind).toBe(
      "not_found",
    );
    const archived = await user.customers
      .findById(row.id, {
        withDeleted: true,
        select: ["archivedAt", "updatedBy"],
      })
      .orThrow();
    expect(archived.archivedAt).not.toBeNull();
    expect(archived.updatedBy).toBe("00000000-0000-4000-8000-0000000000ff");
    expect((await user.customers.delete(row.id)).error?.kind).toBe("not_found");

    await user.customers.restore(row.id).orThrow();
    expect((await user.customers.findById(row.id)).ok).toBe(true);

    await user.customers.delete(row.id, { hard: true }).orThrow();
    expect((await admin.customers.findById(row.id)).error?.kind).toBe(
      "not_found",
    );
  });

  it("respects RLS for the caller and hides other tenants", async () => {
    const db = await asOrgMember(GLOBEX);
    const rows = await db.customers.findMany({ select: ["id"] }).orThrow();
    expect(rows.map((row) => row.id)).toEqual([INITECH]);

    const denied = await db.customers.findById(ROAD_RUNNER);
    expect(denied.error?.kind).toBe("not_found");

    const blocked = await db.customers.create(
      { organizationId: ACME, name: "Cross tenant" },
      { returning: false },
    );
    expect(blocked.error?.kind).toBe("forbidden");
  });

  it("lists with facet counts in two calls and one wave under RLS", async () => {
    const list = defineListQuery(betterSupabase, "customers", {
      facets: { status: "status" },
      sorts: { name: { name: "asc" } },
      defaultSort: "name",
      facetCounts: true,
    });
    const acme = await asOrgMember(ACME);
    const query = list.parse({ facets: { status: ["active"] } }).value!;
    const page = await list.run(acme, query, { select: ["id"] }).orThrow();
    expect(acme.$stats()).toMatchObject({ calls: 2, waves: 1 });

    const all = await acme.customers.findMany({ select: ["status"] }).orThrow();
    const expected: Record<string, number> = {};
    for (const row of all)
      expected[row.status] = (expected[row.status] ?? 0) + 1;
    expect(
      Object.fromEntries(
        Object.entries(page.facetCounts.status).filter(([, n]) => n > 0),
      ),
    ).toEqual(expected);
    expect(page.page.total).toBe(expected["active"] ?? 0);
  });

  it("db.$many runs ad-hoc specs in one wave as an authenticated member", async () => {
    const acme = await asOrgMember(ACME);
    const globex = await asOrgMember(GLOBEX);
    const specs = [
      betterSupabase.spec.customers.findMany({
        select: ["id"],
        orderBy: { name: "asc" },
      }),
      betterSupabase.spec.notes.count(),
      betterSupabase.spec.customers.exists({ where: { id: INITECH } }),
    ] as const;
    const [customers, notes, initech] = await acme.$many(specs).orThrow();
    expect(customers.map((row) => row.id).sort()).toEqual(
      [ROAD_RUNNER, ANVIL].sort(),
    );
    expect(notes).toBeGreaterThan(0);
    expect(initech).toBe(false);
    expect(acme.$stats()).toMatchObject({ calls: 3, waves: 1 });

    const [theirs] = await globex.$many(specs).orThrow();
    expect(theirs.map((row) => row.id)).toEqual([INITECH]);
  });
});
