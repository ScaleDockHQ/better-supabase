import { describe, expect, it } from "vitest";

import type { ModuleConfig } from "../../../src/config/modules.ts";

import {
  moduleBody,
  renderModules,
  resolveModules,
} from "../../../src/sql/registry.ts";

const support = (config: ModuleConfig = {}) =>
  moduleBody("support-sessions", { modules: { "support-sessions": config } })!;

describe("support-sessions module", () => {
  it("owns its table and gates starts with is_platform", () => {
    const sql = support({
      permissions: { start: "system.users.manage", view: "system.audit.read" },
    });
    expect(sql).toContain(
      'create table if not exists "better_supabase"."support_sessions" (',
    );
    expect(sql).toContain(`"is_platform"('system.users.manage')`);
    expect(sql).toContain(`"is_platform"('system.audit.read')`);
    expect(sql).toContain("hint = 'SUPPORT_REASON_REQUIRED'");
    expect(sql).toContain("ttl > '4 hours'::interval");
    expect(sql).toContain("return base -> 'claims';");
    expect(sql).toContain(
      "event_type => 'support.started',\n    category => 'support',",
    );
    expect(sql).toContain(
      'revoke execute on function "better_supabase"."support_target_claims"(uuid) from public, anon, authenticated;',
    );
  });

  it("calls the app's hooks and its access token hook", () => {
    const sql = support({
      hooks: {
        schema: "app",
        functions: { before_support_start: "check_ticket" },
      },
      options: {
        claimsHook: "public.custom_access_token_hook",
        requireReason: false,
        maxTtl: "1 hour",
        auditCategory: "users",
      },
    });
    expect(sql).toContain(
      `to_regprocedure('"app"."check_ticket"(uuid, uuid, text, jsonb)')`,
    );
    expect(sql).toContain(`to_regprocedure('"app"."after_support_end"(uuid)')`);
    expect(sql).toContain(
      "coalesce(public.custom_access_token_hook(base) -> 'claims', base -> 'claims')",
    );
    expect(sql).not.toContain("SUPPORT_REASON_REQUIRED'");
    expect(sql).toContain("'1 hour'::interval");
    expect(sql).toContain("category => 'users'");
  });

  it("adopts a table without the optional columns", () => {
    const sql = support({
      mode: "adopt",
      tables: { sessions: "public.impersonation_sessions" },
      columns: {
        sessions: {
          admin: "impersonator_id",
          tenant: null,
          readOnly: null,
          endedBy: null,
          metadata: null,
        },
      },
    });
    expect(sql).not.toContain("create table if not exists");
    expect(sql).toContain(
      'insert into "public"."impersonation_sessions" ("impersonator_id", "target_user_id", "reason", "expires_at")',
    );
    expect(sql).toContain("'read_only', true,");
    expect(sql).toContain("'metadata', '{}'::jsonb");
    expect(sql).toContain('set "ended_at" = now()\n');
  });

  it("writes nothing in custom mode and checks claimsHook", () => {
    expect(
      moduleBody("support-sessions", {
        modules: { "support-sessions": { mode: "custom" } },
      }),
    ).toBeUndefined();
    expect(() =>
      support({ options: { claimsHook: "drop table x; --" } }),
    ).toThrow(/claimsHook must be schema.function/);
  });

  it("brings access and audit along", () => {
    const names = resolveModules(["support-sessions"]).map(
      (module) => module.name,
    );
    expect(names).toEqual(
      expect.arrayContaining(["access", "audit", "support-sessions"]),
    );
    expect(names.indexOf("support-sessions")).toBe(names.length - 1);
  });
});

describe("support-sessions next to permdock platform roles", () => {
  it("counts a row in the platform role table as a platform target", () => {
    const files = renderModules(["support-sessions", "invitations"], {
      modules: {
        access: {
          model: "permdock",
          permdock: { schema: "authz", scope: "organization" },
        },
        invitations: {
          options: {
            platformRoles: {
              table: "public.user_roles",
              user: "user_id",
              role: "role_id",
            },
          },
        },
      },
    });
    const sql = files.find(
      (file) => file.module === "support-sessions" && file.kind === "schema",
    )!.contents;
    expect(sql).toContain(
      'select 1 from "public"."user_roles" a where a."user_id" = target',
    );
  });
});
