import { describe, expect, it } from "vitest";

import { renderModules } from "../../../src/sql/registry.ts";

const sqlOf = (
  names: readonly string[],
  options?: Readonly<Record<string, unknown>>,
  extra: Readonly<Record<string, unknown>> = {},
): string =>
  renderModules(names, {
    modules: {
      ...(options ? { sso: { options } } : {}),
      ...extra,
    },
  })
    .filter((file) => file.module === "sso")
    .map((file) => file.contents)
    .join("\n");

describe("sso module", () => {
  it("creates domains, providers and SCIM tables with role defaults", () => {
    const sql = sqlOf(["sso"]);
    expect(sql).toContain(
      `"auto_join_role" text check ("auto_join_role" = any (array['admin', 'member', 'viewer']::text[]))`,
    );
    expect(sql).toContain("'_better-supabase.' || ");
    expect(sql).toContain("'member') into v_role");
    expect(sql).toContain("if v_current = 'owner' then");
    expect(sql).toContain(
      "after insert or update of email, email_confirmed_at on auth.users",
    );
    expect(sql).toContain(
      "select null::text as name, null::text as role where false",
    );
    expect(sql).toContain("'sso.manage'");
    expect(sql).not.toContain("emit_event");
  });

  it("maps groups to roles and emits membership events with the outbox", () => {
    const sql = sqlOf(["organizations", "outbox", "sso"], {
      txtPrefix: "_acme-verify",
      defaultRole: "viewer",
      roleOrder: ["admin", "viewer"],
      groupRoles: { Engineering: "viewer", "IT Admins": "admin" },
    });
    expect(sql).toContain(
      "values ('engineering', 'viewer'), ('it admins', 'admin')",
    );
    expect(sql).toContain("'_acme-verify.' || ");
    expect(sql).toContain("'viewer') into v_role");
    expect(sql).toMatch(/emit_event\('organization\.member_added'/);
    expect(sql).toMatch(/emit_event\('organization\.domain_verified'/);
  });

  it("assigns catalog role ids", () => {
    const sql = sqlOf(["sso"], undefined, { access: { model: "catalog" } });
    expect(sql).toMatch(/values \(v_tenant, v_user, \(select r\."id"/);
  });

  it("renders nothing in custom mode", () => {
    const sql = renderModules(["sso"], { modules: { sso: { mode: "custom" } } })
      .filter((file) => file.module === "sso")
      .map((file) => file.contents)
      .join("");
    expect(sql.trim()).toBe("");
  });

  it.each([
    [{ txtPrefix: "acme" }, /start with an underscore/],
    [{ roleOrder: ["owner", "member"] }, /must not include the owner role/],
    [{ defaultRole: "guest" }, /defaultRole "guest" must be one of roleOrder/],
    [{ groupRoles: [] }, /must map SCIM group names to roles/],
    [{ groupRoles: { Ops: "owner" } }, /groupRoles\["Ops"\] must be one of/],
  ])("rejects %j", (options, message) => {
    expect(() => sqlOf(["sso"], options)).toThrow(message);
  });

  it("needs a roles or catalog access model", () => {
    expect(() =>
      sqlOf(["sso"], undefined, {
        access: {
          model: "custom",
          functions: {
            can: "app.can",
            tenantIdsWith: "app.tenant_ids_with",
            isPlatform: "app.is_platform",
            canAssign: "app.can_assign",
          },
        },
      }),
    ).toThrow(/needs sql.modules.access.model "roles" or "catalog"/);
  });
});
