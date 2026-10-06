import { describe, expect, it } from "vitest";

import type { ModulesConfig } from "../../../src/config/modules.ts";

import { renderModules } from "../../../src/sql/registry.ts";

const sqlOf = (names: readonly string[], modules: ModulesConfig = {}): string =>
  renderModules(names, { modules })
    .filter((file) => file.contents.includes("waitlist_entries"))
    .map((file) => file.contents)
    .join("\n");

describe("waitlist module", () => {
  it("writes the tables, the sign-up trigger and the admit check", () => {
    const sql = sqlOf(["waitlist"]);
    expect(sql).toMatch(/create table if not exists \S+waitlist_entries/);
    expect(sql).toMatch(/create table if not exists \S+invite_codes/);
    expect(sql).toMatch(
      /create table if not exists \S+invite_code_redemptions/,
    );
    expect(sql).toContain("'waitlist.manage'");
    expect(sql).toContain("'members.invite'");
    expect(sql).toContain("->> 'invite_code'");
    expect(sql).toContain("array['admin', 'member', 'viewer']::text[]");
    expect(sql).toContain(
      'waitlist_admit"(text, text) to service_role, supabase_auth_admin',
    );
    expect(sql).not.toContain("'waitlist.approved'");
  });

  it("emits waitlist.approved and member_added with the outbox", () => {
    const sql = sqlOf(["outbox", "waitlist"]);
    expect(sql).toContain("'waitlist.approved'");
    expect(sql).toContain("'organization.member_added'");
  });

  it("takes the code field and default role from the options", () => {
    const sql = sqlOf(["waitlist"], {
      waitlist: { options: { codeField: "referral", defaultRole: "viewer" } },
    });
    expect(sql).toContain("->> 'referral'");
    expect(sql).toContain("coalesce(v_code.\"role\", 'viewer')");
  });

  it("rejects a bad code field or an owner default role", () => {
    expect(() =>
      sqlOf(["waitlist"], {
        waitlist: { options: { codeField: "Bad-Field" } },
      }),
    ).toThrow("codeField must be a lowercase identifier");
    expect(() =>
      sqlOf(["waitlist"], { waitlist: { options: { defaultRole: "owner" } } }),
    ).toThrow('defaultRole "owner" must be a role other than the owner');
  });

  it("grants no roles through codes outside the roles and catalog models", () => {
    const sql = sqlOf(["waitlist"], {
      access: {
        model: "custom",
        functions: {
          can: "app.can",
          tenantIdsWith: "app.tenant_ids_with",
          isPlatform: "app.is_platform",
          canAssign: "app.can_assign",
        },
      },
    });
    expect(sql).toContain("array[]::text[]");
  });
});
