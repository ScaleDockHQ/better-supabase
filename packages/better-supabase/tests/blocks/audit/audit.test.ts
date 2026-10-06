import { describe, expect, it } from "vitest";

import type { AnyModels } from "../../../src/schema/types.ts";

import {
  auditListQuery,
  exportAuditLog,
  purgeAuditLog,
  setAuditRetention,
  toOcsf,
} from "../../../src/blocks/audit/index.ts";
import { defineSupabase } from "../../../src/core/define.ts";
import { SPEC_PINS } from "../../../src/core/spec-pins.ts";
import { defineSchema } from "../../../src/schema/define.ts";
import { fakeSql, pgError } from "../../fixtures/fake-sql.ts";

describe("purgeAuditLog", () => {
  it("makes one purge call without a retention callback", async () => {
    const fake = fakeSql([["purge_audit_log", [{ n: "4" }]]]);
    expect(await purgeAuditLog(fake.sql).orThrow()).toBe(4);
    expect(fake.calls).toEqual([
      {
        text: "select better_supabase.purge_audit_log($1::interval, $2) as n",
        values: ["1 year", 10_000],
      },
    ]);
  });

  it("purges each tenant with the interval the callback returns", async () => {
    const fake = fakeSql([
      ["audit_events_tenants", [{ tenant: "a" }, { tenant: null }]],
      ["purge_audit_log", [{ n: 2 }]],
    ]);
    const purged = await purgeAuditLog(fake.sql, {
      olderThan: 86_400,
      batch: 50,
      retention: (tenant) => (tenant === "a" ? 30 : undefined),
    }).orThrow();
    expect(purged).toBe(4);
    expect(fake.calls.slice(1).map((call) => call.values)).toEqual([
      ["30 days", 50, "a"],
      ["86400 seconds", 50, null],
    ]);
  });

  it("returns a DbError when the module is missing", async () => {
    const fake = fakeSql([
      [
        "purge_audit_log",
        { throws: pgError("42883", "function does not exist") },
      ],
    ]);
    const result = await purgeAuditLog(fake.sql);
    expect(result.ok).toBe(false);
  });
});

describe("setAuditRetention", () => {
  it("reads a tenant's days from a column", async () => {
    const fake = fakeSql([
      [(call) => call.values[0] === "a", [{ days: 30 }]],
      [(call) => call.values[0] === "b", [{ days: null }]],
    ]);
    const retention = setAuditRetention(fake.sql, {
      table: "public.organizations",
      column: "audit_retention_days",
    });
    expect(await retention("a")).toBe(30);
    expect(await retention("b")).toBeUndefined();
    expect(await retention("c")).toBeUndefined();
    expect(await retention(null)).toBeUndefined();
    expect(fake.calls[0]?.text).toBe(
      'select "audit_retention_days"::integer as days from "public"."organizations" where "id"::text = $1',
    );
    const plain = setAuditRetention(fake.sql, {
      table: "plans",
      column: "days",
      key: "organization_id",
    });
    await plain("a");
    expect(fake.calls.at(-1)?.text).toContain(
      'from "public"."plans" where "organization_id"',
    );
  });
});

const ROWS = [
  {
    id: 1,
    occurred_at: "2026-10-06T10:00:00Z",
    op: "update",
    table_name: "public.deals",
    record_id: "d1",
    changed: ["stage"],
    actor_id: "u1",
    actor_role: "authenticated",
    organization_id: "o1",
    event_type: null,
    category: null,
    outcome: null,
    source: null,
    target_type: null,
    metadata: null,
  },
  {
    id: 2,
    occurred_at: "2026-10-06T11:00:00Z",
    op: "event",
    table_name: null,
    record_id: "k1",
    changed: null,
    actor_id: "u1",
    actor_role: null,
    organization_id: "o1",
    event_type: "api_key.revoked",
    category: "security",
    outcome: "success",
    source: "api",
    target_type: "api_key",
    metadata: { reason: "leak" },
  },
  {
    id: 3,
    occurred_at: "2026-10-06T12:00:00Z",
    op: "event",
    table_name: null,
    record_id: null,
    changed: null,
    actor_id: null,
    actor_role: null,
    organization_id: "o1",
    event_type: "sso.enforced",
    category: null,
    outcome: "denied",
    source: null,
    target_type: null,
    metadata: null,
  },
];

async function lines(stream: ReadableStream<Uint8Array>): Promise<unknown[]> {
  const text = await new Response(stream).text();
  return text
    .trim()
    .split("\n")
    .filter(Boolean)
    .map((line) => JSON.parse(line));
}

describe("exportAuditLog", () => {
  it("pages by id and writes NDJSON", async () => {
    const fake = fakeSql([
      [(call) => call.values[3] === "0", ROWS.slice(0, 2)],
      [(call) => call.values[3] === "2", ROWS.slice(2)],
    ]);
    const out = await lines(
      exportAuditLog(fake.sql, {
        organizationId: "o1",
        from: Temporal.Instant.from("2026-10-01T00:00:00Z"),
        batch: 2,
      }),
    );
    expect(out).toHaveLength(3);
    expect(out[0]).toMatchObject({
      id: "1",
      op: "update",
      table: "public.deals",
      changed: ["stage"],
      organizationId: "o1",
    });
    expect(out[1]).toMatchObject({
      eventType: "api_key.revoked",
      metadata: { reason: "leak" },
    });
    expect(fake.calls.map((call) => call.values)).toEqual([
      ["o1", "2026-10-01T00:00:00Z", null, "0", 2],
      ["o1", "2026-10-01T00:00:00Z", null, "2", 2],
    ]);
  });

  it("maps entries to OCSF", async () => {
    const fake = fakeSql([["audit_events", ROWS]]);
    const [change, revoked, denied] = (await lines(
      exportAuditLog(fake.sql, {
        organizationId: "o1",
        format: "ocsf",
        product: { name: "Acme" },
      }),
    )) as Record<string, unknown>[];
    expect(change).toMatchObject({
      class_uid: 3004,
      activity_id: 3,
      type_uid: 300403,
      entity: { uid: "d1", type: "public.deals" },
      metadata: {
        version: SPEC_PINS.ocsf,
        product: { name: "Acme" },
        tenant_uid: "o1",
      },
    });
    expect(revoked).toMatchObject({
      class_uid: 6003,
      activity_id: 4,
      type_uid: 600304,
      status_id: 1,
      api: { operation: "api_key.revoked" },
      resources: [{ uid: "k1", type: "api_key" }],
    });
    expect(denied).toMatchObject({
      activity_id: 99,
      activity_name: "sso.enforced",
      status_id: 2,
      actor: { user: { uid: "system" } },
    });
    expect(() =>
      exportAuditLog(fake.sql, { organizationId: "o1", format: "ocsf" }),
    ).toThrow(/product/);
  });

  it("maps other outcomes and plain events", () => {
    const entry = {
      id: "9",
      occurredAt: Temporal.Instant.from("2026-10-06T00:00:00Z"),
      op: "event",
      outcome: "partial",
    };
    expect(toOcsf(entry, { name: "Acme" })).toMatchObject({
      status_id: 99,
      status: "partial",
      activity_id: 99,
      api: { operation: "event" },
    });
    expect(
      toOcsf({ ...entry, eventType: "deal.created" }, { name: "Acme" }),
    ).toMatchObject({
      activity_id: 1,
    });
  });
});

describe("auditListQuery", () => {
  const column = (db: string, type: string, nullable = true) => ({
    db,
    type,
    nullable,
    hasDefault: false,
  });
  const betterSupabase = defineSupabase(
    defineSchema<AnyModels>({
      version: 1,
      casing: "camel",
      tables: {
        auditEvents: {
          key: "auditEvents",
          name: "audit_events",
          schema: "better_supabase",
          kind: "table",
          columns: {
            id: column("id", "int8", false),
            tableName: column("table_name", "text"),
            op: column("op", "text", false),
            actorId: column("actor_id", "uuid"),
            eventType: column("event_type", "text"),
            occurredAt: column("occurred_at", "timestamptz", false),
          },
          primaryKey: ["id"],
          uniqueKeys: {},
          relations: {},
          flags: {},
        },
      },
      enums: {},
      functions: {},
    }),
  );

  it("filters by the columns the table has, newest first, with a cursor", () => {
    const list = auditListQuery(betterSupabase, "auditEvents", {
      pageSize: 20,
    });
    expect(list.facets.map((facet) => facet.key)).toEqual([
      "table",
      "op",
      "actor",
      "event",
    ]);
    expect(list.pagination).toBe("cursor");
    const query = list.parse({ facets: { event: ["api_key.revoked"] } });
    expect(query.ok).toBe(true);
    expect(list.args(query.value!)).toMatchObject({
      orderBy: [{ occurredAt: "desc" }, { id: "desc" }],
      size: 20,
    });
    expect(
      list.between(
        Temporal.Instant.from("2026-10-01T00:00:00Z"),
        Temporal.Instant.from("2026-11-01T00:00:00Z"),
      ),
    ).toEqual({
      occurredAt: { gte: "2026-10-01T00:00:00Z", lt: "2026-11-01T00:00:00Z" },
    });
    expect(list.between()).toEqual({});
    expect(() => auditListQuery(betterSupabase, "missing" as never)).toThrow(
      /unknown table/,
    );
  });
});
