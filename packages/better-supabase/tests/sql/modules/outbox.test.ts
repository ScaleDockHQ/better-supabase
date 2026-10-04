import { describe, expect, it } from "vitest";

import type { KitsConfig } from "../../../src/config/kits.ts";

import { moduleBody, renderKit } from "../../../src/sql/kit.ts";

const body = (kits: KitsConfig) => moduleBody("outbox", { kits })!;

describe("outbox module", () => {
  it("owns its tables and keeps the functions for the service role", () => {
    const sql = body({});
    expect(sql).toContain(
      'create table if not exists "better_supabase"."outbox_events" (',
    );
    expect(sql).toContain('"xid" xid8 not null default pg_current_xact_id()');
    expect(sql).toContain("nulls not distinct");
    expect(sql).toContain('"xid" < pg_snapshot_xmin(pg_current_snapshot())');
    expect(sql).toContain(
      'grant execute on function "better_supabase"."emit_event"(text, jsonb, text, text, text, text) to service_role;',
    );
    expect(sql).toContain("older_than interval default '30 days'");
    expect(sql).toContain("track_events");
  });

  it("adopts an events table with other names and no xid column", () => {
    const sql = body({
      outbox: {
        mode: "adopt",
        tables: { events: "public.domain_events" },
        columns: {
          events: { type: "kind", position: "seq", xid: null, key: null },
        },
        options: {
          tenantType: "uuid",
          settle: "2 seconds",
          emitRoles: ["authenticated"],
          defaultSource: "domain",
        },
      },
    });
    expect(sql).not.toContain(
      "create table if not exists public.domain_events",
    );
    expect(sql).toContain("coalesce(source, 'domain')");
    expect(sql).toContain(
      'create table if not exists "better_supabase"."outbox_consumers"',
    );
    expect(sql).toContain('insert into "public"."domain_events" ("kind"');
    expect(sql).toContain("tenant::uuid");
    expect(sql).toContain("now() - '2 seconds'::interval");
    expect(sql).toContain('returning "seq" into found_position');
    expect(sql).not.toContain('where e."key"');
    expect(sql).toContain("to service_role, authenticated;");
  });

  it("separates the position from a non-numeric id", () => {
    const sql = body({
      outbox: { columns: { events: { position: "position" } } },
    });
    expect(sql).toContain(
      '"position" bigint generated always as identity unique',
    );
  });

  it("rejects option values it would splice into SQL", () => {
    expect(() =>
      body({ outbox: { options: { tenantType: "uuid; drop" } } }),
    ).toThrow(/tenantType/);
    expect(() => body({ outbox: { options: { emitRoles: ["x y"] } } })).toThrow(
      /emitRoles/,
    );
  });

  it("renders nothing in custom mode", () => {
    expect(moduleBody("outbox", { kits: { outbox: { mode: "custom" } } })).toBe(
      undefined,
    );
  });

  it("lets other modules emit once the outbox is installed", () => {
    const without = renderKit(["organizations"]).at(-1)!.contents;
    expect(without).not.toContain("emit_event");
    const files = renderKit(["organizations", "outbox"]);
    const orgs = files.find((file) => file.path.includes("organizations"))!;
    expect(orgs.contents).toContain(
      `perform "better_supabase".emit_event('org.created'`,
    );
    const silenced = renderKit(["organizations", "outbox"], {
      kits: { organizations: { events: false } },
    }).find((file) => file.path.includes("organizations"))!;
    expect(silenced.contents).not.toContain("emit_event");
  });
});
