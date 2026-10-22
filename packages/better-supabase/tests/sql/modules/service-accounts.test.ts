import { describe, expect, it } from "vitest";

import { SQL_MODULES } from "../../../src/sql/registry.ts";
import { renderBlocks } from "../../../src/sql/render.ts";

const sqlOf = (module: string, names: readonly string[]): string =>
  renderBlocks(names, {})
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

const BASE = ["memberships", "permissions", "service-accounts"];

describe("service-accounts module", () => {
  it("is registered before rls-guard", () => {
    const names = Object.keys(SQL_MODULES);
    expect(names.indexOf("service-accounts")).toBeLessThan(
      names.indexOf("rls-guard"),
    );
  });

  it("registers only banned, marked users, as the service", () => {
    const sql = sqlOf("service-accounts", BASE);
    expect(sql).toContain(
      "coalesce((u.raw_app_meta_data ->> 'bsb_service_principal')::boolean, false)",
    );
    expect(sql).toContain("u.banned_until > now() + interval '50 years'");
    expect(sql).toContain(
      'revoke execute on function "better_supabase"."register_service_principal"(uuid, uuid, text, text, boolean, uuid) from public, anon, authenticated;',
    );
    expect(sql).toContain(
      "better_supabase.can_assign_as(register_service_principal.created_by",
    );
    expect(sql).toContain('insert into "better_supabase"."memberships"');
  });

  it("writes no membership when the tenant module is custom", () => {
    const sql = renderBlocks(BASE, {
      modules: { memberships: { mode: "custom" } },
    })
      .filter((file) => file.module === "service-accounts")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain("register_service_principal");
    expect(sql).not.toContain('"memberships"');
  });

  it("runs organization workflow versions as the default principal", () => {
    const sql = sqlOf("workflow-editor", [
      ...BASE,
      "workflows",
      "workflow-editor",
    ]);

    expect(sql).toContain(
      'v_publisher := "better_supabase"."default_service_principal"(v_tenant);',
    );
    expect(sql).toContain("The service principal no longer holds %");
    expect(
      sqlOf("workflow-editor", [
        "memberships",
        "permissions",
        "workflows",
        "workflow-editor",
      ]),
    ).not.toContain("default_service_principal");
  });

  it("checks a service webhook endpoint against the default principal", () => {
    const sql = sqlOf("webhooks-out", [...BASE, "webhooks-out"]);
    expect(sql).toContain(
      'better_supabase.can_user("better_supabase"."default_service_principal"(d."organization_id")',
    );
  });
});
