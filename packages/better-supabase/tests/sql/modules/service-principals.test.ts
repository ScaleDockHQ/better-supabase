import { describe, expect, it } from "vitest";

import { SQL_MODULES } from "../../../src/sql/registry.ts";
import { renderModules } from "../../../src/sql/render.ts";

const sqlOf = (module: string, names: readonly string[]): string =>
  renderModules(names, {})
    .filter((file) => file.module === module)
    .map((file) => file.contents)
    .join("\n");

const BASE = ["tenant", "access", "service-principals"];

describe("service-principals module", () => {
  it("is registered before ensure-rls", () => {
    const names = Object.keys(SQL_MODULES);
    expect(names.indexOf("service-principals")).toBe(
      names.indexOf("ensure-rls") - 1,
    );
  });

  it("registers only banned, marked users, as the service", () => {
    const sql = sqlOf("service-principals", BASE);
    expect(sql).toContain(
      "coalesce((u.raw_app_meta_data ->> 'bs_service_principal')::boolean, false)",
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
    const sql = renderModules(BASE, {
      modules: { tenant: { mode: "custom" } },
    })
      .filter((file) => file.module === "service-principals")
      .map((file) => file.contents)
      .join("\n");
    expect(sql).toContain("register_service_principal");
    expect(sql).not.toContain('"memberships"');
  });

  it("runs organization workflow versions as the default principal", () => {
    const sql = sqlOf("workflow-builder", [
      ...BASE,
      "workflows",
      "workflow-builder",
    ]);
    expect(sql).toContain(
      'v_publisher := "better_supabase"."default_service_principal"(v_tenant);',
    );
    expect(sql).toContain("The service principal no longer holds %");
    expect(
      sqlOf("workflow-builder", [
        "tenant",
        "access",
        "workflows",
        "workflow-builder",
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
