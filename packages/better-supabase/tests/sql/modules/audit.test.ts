import { describe, expect, it } from "vitest";

import type { KitModuleConfig } from "../../../src/config/kits.ts";

import {
  moduleBody,
  renderKit,
  resolveModules,
  upgradePlan,
} from "../../../src/sql/kit.ts";

const audit = (config: KitModuleConfig = {}) =>
  moduleBody("audit", { kits: { audit: config } })!;

/** CentraKit's audit tables: uuid ids, no row snapshots, restricted details apart. */
const CENTRAKIT: KitModuleConfig = {
  mode: "adopt",
  tables: {
    log: "public.audit_logs",
    restricted: "public.audit_log_restricted_details",
  },
  columns: {
    log: {
      table: null,
      record: "target_id",
      op: null,
      old: null,
      new: null,
      changed: null,
      actorRole: null,
      tenant: "organization_id",
      occurredAt: "occurred_at",
      impersonatedBy: null,
      impersonationReason: null,
      supportSession: null,
      metadata: "safe_metadata",
    },
    restricted: {
      entry: "event_id",
      old: null,
      new: null,
      metadata: "restricted_metadata",
    },
  },
  options: { eventSource: "saas" },
};

describe("audit module", () => {
  it("keeps the managed defaults and adds event naming", () => {
    const sql = audit();
    expect(sql).toContain(
      'create table if not exists "better_supabase"."audit_events" (',
    );
    expect(sql).toContain(
      "coalesce(entry.event_prefix, tg_table_name) || '.' || case tg_op",
    );
    expect(sql).toContain(
      "create or replace function better_supabase.audit_event(",
    );
    expect(sql).toContain("coalesce(source, 'app')");
    expect(sql).toContain('drop trigger if exists "bs_audit_append_only"');
    expect(sql).toContain(
      'drop policy if exists bs_audit_read on "better_supabase"."audit_events";',
    );
    expect(sql).not.toContain("audit_events_restricted");
    expect(sql).toContain(
      "execute function better_supabase.audit_row_change()",
    );
    expect(sql).toContain(
      "raise exception 'audit_event got restricted details, and the audit module has no restricted table'",
    );
    expect(sql).toContain(
      "hint = 'Set kits.audit.options.restricted to true.'",
    );
    const [file] = renderKit(["audit"]);
    expect(file!.contents).toContain(
      'create or replace view "better_supabase".audit_log',
    );
    expect(file!.contents).toContain(
      "'deprecated: use better_supabase.audit_events'",
    );
  });

  it("maps onto adopted tables without creating them", () => {
    const sql = audit(CENTRAKIT);
    expect(sql).not.toContain("create table if not exists public");
    expect(sql).not.toContain('create table if not exists "public"');
    expect(sql).toContain(
      'insert into "public"."audit_logs" ("target_id", "actor_id", "organization_id", "event_type"',
    );
    expect(sql).toContain('entry_id "public"."audit_logs"."id"%type;');
    expect(sql).toContain(
      'insert into "public"."audit_log_restricted_details" ("event_id", "ip_address", "user_agent", "restricted_metadata")',
    );
    expect(sql).toContain("coalesce(source, 'saas')");
    expect(sql).not.toContain("audit_event got restricted details");
    expect(sql).not.toContain("old_record");
    expect(sql).not.toContain("drop policy if exists bs_audit_read");
  });

  it("guards, scopes and splits entries by option", () => {
    const sql = audit({
      options: {
        appendOnly: true,
        readPolicy: true,
        impersonators: "hide",
        restricted: true,
        eventRoles: ["service_role", "authenticated"],
      },
      permissions: { view: "audit.read", viewAll: "platform.audit.read" },
    });
    expect(sql).toContain(
      'create trigger "bs_audit_append_only" before update or delete',
    );
    expect(sql).toContain("better_supabase.tenant_ids_with('audit.read')");
    expect(sql).toContain("better_supabase.is_platform('platform.audit.read')");
    expect(sql).toMatch(/grant select \([^)]*"actor_id"[^)]*\) on/);
    expect(sql).not.toMatch(/grant select \([^)]*"impersonated_by"/);
    expect(sql).toContain(
      'create table if not exists "better_supabase"."audit_events_restricted"',
    );
    expect(sql).toContain('to "service_role", "authenticated";');
  });

  it("calls the retention hook the app names", () => {
    const sql = audit({
      hooks: {
        schema: "app",
        functions: { audit_retention: "plan_audit_days" },
      },
    });
    expect(sql).toContain(`to_regprocedure('"app"."plan_audit_days"(uuid)')`);
    expect(sql).toContain(
      `to_regprocedure('"app"."plan_audit_days"(uuid)')::oid::regproc\n    ) into purged using older_than, batch;`,
    );
    expect(sql).not.toMatch(/"app"\."plan_audit_days"\(l\./);
  });

  it("needs the access module only for the read policy", () => {
    const names = (config: KitModuleConfig) =>
      resolveModules(["audit"], { kits: { audit: config } }).map(
        (module) => module.name,
      );
    expect(names({})).toEqual(["audit"]);
    expect(names({ options: { readPolicy: true } })).toContain("access");
  });

  it("rejects an unknown impersonators option", () => {
    expect(() =>
      audit({ options: { readPolicy: true, impersonators: "blur" } }),
    ).toThrow(/impersonators/);
  });

  it("drops the old signatures when upgrading from version 1", () => {
    const [plan] = upgradePlan([{ module: "audit", version: 1 }]);
    expect(plan!.steps[0]!.sql).toContain(
      "drop function if exists better_supabase.audit(regclass, text[], boolean);",
    );
  });
});
