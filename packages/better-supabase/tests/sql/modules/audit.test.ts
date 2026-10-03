import { describe, expect, it } from "vitest";

import type { KitModuleConfig } from "../../../src/config/kits.ts";

import {
  moduleBody,
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
      at: "occurred_at",
      impersonatedBy: null,
      impersonationReason: null,
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
      'create table if not exists "better_supabase"."audit_log" (',
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
      'drop policy if exists bs_audit_read on "better_supabase"."audit_log";',
    );
    expect(sql).not.toContain("audit_log_restricted");
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
      'create table if not exists "better_supabase"."audit_log_restricted"',
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
