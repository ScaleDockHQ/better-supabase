import { describe, expect, it } from "vitest";

import type { ModulesConfig } from "../../../src/config/modules.ts";

import { moduleBody, renderModules } from "../../../src/sql/registry.ts";

const body = (modules: ModulesConfig) => moduleBody("outbox", { modules })!;

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
        idType: "uuid",
        tables: { events: "public.domain_events" },
        columns: {
          events: { type: "kind", position: "seq", xid: null, key: null },
        },
        options: {
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
    expect(sql).toContain('returning "id"::text into found_id');
    expect(sql).toContain('where e."seq" > c."cursor_position"');
    expect(sql).not.toContain('add column if not exists "xid"');
    expect(sql).not.toContain('where e."key"');
    expect(sql).toContain("to service_role, authenticated;");
  });

  it("gives events a uuid id and a separate position", () => {
    const sql = body({});
    expect(sql).toContain('"id" uuid primary key default gen_random_uuid()');
    expect(sql).toContain(
      '"position" bigint generated always as identity unique',
    );
    expect(sql).toContain(
      'create index if not exists outbox_events_xid_idx on "better_supabase"."outbox_events" ("xid", "position");',
    );
    expect(sql).toContain('("cursor_xid", "cursor_position") = (');
    expect(sql).toContain(
      '(e."xid", e."position") > (c."cursor_xid", c."cursor_position")',
    );
    expect(sql).toContain("outbox_unregister");
    expect(sql).toContain("limit coalesce(batch, 10000)");
    const shared = body({
      outbox: { columns: { events: { position: "id" } } },
    });
    expect(shared).toContain(
      '"id" bigint generated always as identity primary key',
    );
  });

  it("adds the xid column to an adopted table and refuses a zero settle", () => {
    const adopted = body({
      outbox: { mode: "adopt", tables: { events: "public.domain_events" } },
    });
    expect(adopted).toContain(
      'alter table "public"."domain_events" add column if not exists "xid" xid8 not null default pg_current_xact_id();',
    );
    expect(() =>
      body({
        outbox: {
          mode: "adopt",
          columns: { events: { xid: null } },
          options: { settle: "0 seconds" },
        },
      }),
    ).toThrow(/settle must be longer than zero/);
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
    expect(
      moduleBody("outbox", { modules: { outbox: { mode: "custom" } } }),
    ).toBe(undefined);
  });

  it("lets other modules emit once the outbox is installed", () => {
    const without = renderModules(["organizations"]).at(-1)!.contents;
    expect(without).not.toContain("emit_event");
    const files = renderModules(["organizations", "outbox"]);
    const organizations = files.find((file) =>
      file.path.includes("organizations"),
    )!;
    expect(organizations.contents).toContain(
      `perform "better_supabase".emit_event('organization.created'`,
    );
    const silenced = renderModules(["organizations", "outbox"], {
      modules: { organizations: { events: false } },
    }).find((file) => file.path.includes("organizations"))!;
    expect(silenced.contents).not.toContain("emit_event");
  });
});
