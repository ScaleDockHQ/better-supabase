import { describe, expect, it } from "vitest";

import { renderModules } from "../../../src/sql/registry.ts";

const sqlOf = (
  names: readonly string[],
  options?: Readonly<Record<string, unknown>>,
  extra: Readonly<Record<string, unknown>> = {},
): string =>
  renderModules(names, {
    modules: {
      ...(options ? { "data-lifecycle": { options } } : {}),
      ...extra,
    },
  })
    .filter((file) => file.module === "data-lifecycle")
    .map((file) => file.contents)
    .join("\n");

describe("data-lifecycle module", () => {
  it("lists the tables of installed modules and creates the exports bucket", () => {
    const sql = sqlOf(["data-lifecycle"]);
    expect(sql).toContain(
      `('user', 'better_supabase.memberships', '"better_supabase"."memberships"', 'user_id', true)`,
    );
    expect(sql).not.toContain("better_supabase.profiles");
    expect(sql).toContain("values ('data-exports', 'data-exports', false)");
    expect(sql).toContain("v_disabled := false;");
    expect(sql).toContain("'30 days'::interval");
    expect(sql).not.toContain("emit_event");
    expect(sql).toContain('"public"."on_organization_purge"');
  });

  it("adds every module's tables, keeps the audit trail and disables managed organizations", () => {
    const sql = sqlOf(
      [
        "organizations",
        "outbox",
        "audit",
        "profiles",
        "settings",
        "comments",
        "attachments",
        "api-keys",
        "usage",
        "notifications",
        "data-lifecycle",
      ],
      {
        bucket: "exports",
        grace: "14 days",
        exportTtl: "1 day",
        tables: {
          projects: { tenant: "organization_id", user: "owner_id" },
          "app.notes": { user: "author_id", purge: false },
        },
      },
    );
    for (const table of [
      "better_supabase.profiles",
      "better_supabase.user_settings",
      "better_supabase.activity_entries",
      "better_supabase.attachments",
      "better_supabase.api_keys",
      "better_supabase.usage_quotas",
      "better_supabase.notification_recipients",
    ]) {
      expect(sql).toContain(`'${table}'`);
    }
    expect(sql).toMatch(
      /\('organization', '[a-z_]+\.audit_events', .*, false\)/,
    );
    expect(sql).toContain(
      `('organization', 'public.projects', '"public"."projects"', 'organization_id', true)`,
    );
    expect(sql).toContain(
      `('user', 'public.projects', '"public"."projects"', 'owner_id', true)`,
    );
    expect(sql).toContain(
      `('user', 'app.notes', '"app"."notes"', 'author_id', false)`,
    );
    expect(sql).toContain("values ('exports', 'exports', false)");
    expect(sql).toContain("'14 days'::interval");
    expect(sql).toContain("'1 day'::interval");
    expect(sql).toMatch(
      /update "better_supabase"."organizations" set "disabled_at"/,
    );
    expect(sql).toMatch(/delete from "better_supabase"."organizations"/);
    expect(sql).toMatch(/emit_event\('organization\.purged'/);
    expect(sql).toMatch(/emit_event\('data_export\.ready'/);
  });

  it("disables the tenant through access.disabled.tenant when set", () => {
    const sql = sqlOf(["data-lifecycle"], undefined, {
      access: { disabled: { tenant: "public.teams.archived_at" } },
    });
    expect(sql).toContain(
      `update "public"."teams" set "archived_at" = coalesce("archived_at", now()) where "id" = request_organization_deletion.tenant;`,
    );
    expect(sql).toContain(`update "public"."teams" set "archived_at" = null`);
  });

  it.each([
    [{ bucket: "No" }, /lowercase letters/],
    [{ tables: [] }, /must be an object of table names/],
    [{ tables: { "a.b.c": { tenant: "x" } } }, /"table" or "schema.table"/],
    [{ tables: { projects: "x" } }, /must be an object/],
    [{ tables: { projects: { tenant: "Bad" } } }, /lowercase identifiers/],
    [{ tables: { projects: {} } }, /needs a user or a tenant column/],
  ])("rejects %j", (options, message) => {
    expect(() => sqlOf(["data-lifecycle"], options)).toThrow(message);
  });

  it("finds tables by column with autoTables, minus the explicit and excluded ones", () => {
    const sql = sqlOf(["data-lifecycle"], {
      tables: { "app.notes": { tenant: "team_id" } },
      autoTables: {
        schemas: ["public", "app"],
        user: "owner_id",
        exclude: ["public.*_log"],
      },
    });
    expect(sql).toContain("n.nspname in ('public', 'app')");
    expect(sql).toContain("a.attname = 'organization_id'");
    expect(sql).toContain("a.attname = 'owner_id'");
    expect(sql).toContain(
      "not in ('better_supabase.memberships', 'app.notes')",
    );
    expect(sql).toContain("like 'public.%\\_log'");
    expect(sql).toMatch(/returns table \(subject text[^$]*\nstable\n/);
    expect(sqlOf(["data-lifecycle"])).toMatch(/\nimmutable\n/);
    expect(sqlOf(["data-lifecycle"], { tables: "auto" })).toContain(
      "a.attname = 'organization_id'",
    );
    expect(() =>
      sqlOf(["data-lifecycle"], { autoTables: { schemas: ["Bad Schema"] } }),
    ).toThrow(/is not a schema name/);
    expect(() =>
      sqlOf(["data-lifecycle"], { autoTables: { tenant: 1 } }),
    ).toThrow(/lowercase column name/);
    expect(() => sqlOf(["data-lifecycle"], { autoTables: [] })).toThrow(
      /must be an object/,
    );
    expect(() =>
      sqlOf(["data-lifecycle"], { autoTables: { exclude: "x" } }),
    ).toThrow(/must be a list/);
  });

  it("purges an adopted organization row and lets platform staff request deletion", () => {
    const sql = sqlOf(["organizations", "data-lifecycle"], undefined, {
      organizations: {
        mode: "adopt",
        tables: { organizations: "public.teams" },
      },
      "data-lifecycle": {
        permissions: { deletePlatform: "platform.teams.delete" },
      },
    });
    expect(sql).toContain(
      `delete from "public"."teams" where "id" = purge_organization.tenant;`,
    );
    expect(sql).toContain(
      "not coalesce(better_supabase.is_platform('platform.teams.delete'), false)",
    );
    expect(sql).toContain("ORGANIZATION_PURGE_BLOCKED");
  });
});
