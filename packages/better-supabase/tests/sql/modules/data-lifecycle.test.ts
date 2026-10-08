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
  it("checks the owner through the tenant module's role lookup", () => {
    const sql = sqlOf(["organizations", "data-lifecycle"]);
    expect(sql).toContain(
      `coalesce(better_supabase.organization_member_role(cancel_organization_deletion.tenant, auth.uid()) = 'owner', false)`,
    );
    const through = renderModules(["data-lifecycle"], {
      modules: {
        tenant: {
          mode: "adopt",
          tables: { memberships: "public.members" },
          columns: { memberships: { role: "role_id" } },
          options: {
            roleThrough: { table: "public.roles", id: "id", column: "name" },
          },
        },
      },
    })
      .filter((file) => file.module === "tenant")
      .map((file) => file.contents)
      .join("\n");
    expect(through).toMatch(
      /organization_member_role[\s\S]*?"public"\."roles"/,
    );
  });

  it("lists the tables of installed modules and creates the exports bucket", () => {
    const sql = sqlOf(["data-lifecycle"]);
    expect(sql).toContain(
      `('user', 'better_supabase.memberships', '"better_supabase"."memberships"', 'user_id', true, '{}'::text[], true)`,
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
      /\('organization', '[a-z_]+\.audit_events', .*, false, '\{\}'::text\[\], true\)/,
    );
    expect(sql).toContain(
      `('organization', 'public.projects', '"public"."projects"', 'organization_id', true, '{}'::text[], true)`,
    );
    expect(sql).toContain(
      `('user', 'public.projects', '"public"."projects"', 'owner_id', true, '{}'::text[], true)`,
    );
    expect(sql).toContain(
      `('user', 'app.notes', '"app"."notes"', 'author_id', false, '{}'::text[], true)`,
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

  it("reads the tables from each module's lifecycle declarations", () => {
    const sql = sqlOf([
      "usage",
      "sso",
      "webhooks-out",
      "notifications",
      "data-lifecycle",
    ]);
    for (const row of [
      `('organization', 'better_supabase.usage_history', '"better_supabase"."usage_history"', 'organization_id', true, '{}'::text[], true)`,
      `('user', 'better_supabase.usage_history', '"better_supabase"."usage_history"', 'actor_id', true, '{}'::text[], true)`,
      `('organization', 'better_supabase.organization_sso_providers', '"better_supabase"."organization_sso_providers"', 'organization_id', true, '{}'::text[], true)`,
      `('organization', 'better_supabase.webhook_endpoints', '"better_supabase"."webhook_endpoints"', 'organization_id', true, '{}'::text[], true)`,
      `('user', 'better_supabase.notification_preferences', '"better_supabase"."notification_preferences"', 'user_id', true, '{}'::text[], true)`,
    ]) {
      expect(sql).toContain(row);
    }
    expect(sql).not.toContain("'better_supabase.webhook_endpoint_secrets'");
    expect(sql).not.toContain("'better_supabase.data_exports'");
    expect(
      renderModules(["usage", "data-lifecycle"], {
        modules: { usage: { tables: { history: "app.usage_log" } } },
      })
        .filter((file) => file.module === "data-lifecycle")
        .map((file) => file.contents)
        .join("\n"),
    ).toContain(`'app.usage_log', '"app"."usage_log"', 'organization_id'`);
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
      "not in ('better_supabase.memberships', 'better_supabase.permission_overrides', 'app.notes')",
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

  it("writes anonymize_due from options.anonymize", () => {
    const empty = sqlOf(["data-lifecycle"]);
    expect(empty).toContain(
      '"better_supabase"."anonymize_due"(max_rows integer default 1000)',
    );
    expect(empty).not.toContain("v_max");
    expect(empty).toContain("hint = 'DATA_ANONYMIZE_FORBIDDEN'");
    const sql = sqlOf(["data-lifecycle"], {
      anonymize: [
        {
          table: "candidates",
          after: "180 days",
          from: "process_ended_at",
          unless: "{row}.pool_consent_until > now()",
          set: {
            first_name: "Anonymized",
            email: null,
            score: 0,
            active: false,
            phone_hash: { sql: "md5({row}.phone)" },
          },
          markedBy: "anonymized_at",
        },
      ],
    });
    expect(sql).toContain(`select r.ctid from "public"."candidates" r
    where r."anonymized_at" is null
      and r."process_ended_at" is not null
      and r."process_ended_at" <= now() - '180 days'::interval
      and not coalesce((r.pool_consent_until > now()), false)
    limit v_max
    for update skip locked`);
    expect(sql).toContain(
      `set "first_name" = 'Anonymized', "email" = null, "score" = 0, "active" = false, "phone_hash" = (md5(r.phone)), "anonymized_at" = now()`,
    );
    expect(sql).toContain(
      "v_done := v_done || jsonb_build_object('public.candidates', v_count);",
    );
  });

  it("checks the shape of options.anonymize", () => {
    const rule = {
      table: "candidates",
      after: "1 year",
      from: "ended_at",
      set: { email: null },
      markedBy: "anonymized_at",
    };
    const fails = (anonymize: unknown) => () =>
      sqlOf(["data-lifecycle"], { anonymize });
    expect(fails(rule)).toThrow(/must be a list/);
    expect(fails([{ ...rule, set: undefined }])).toThrow(/markedBy/);
    expect(fails([{ ...rule, set: {} }])).toThrow(/at least one column/);
    expect(fails([{ ...rule, from: "Ended" }])).toThrow(
      /anonymize\[0\]\.from must be a lowercase column name/,
    );
    expect(fails([{ ...rule, markedBy: undefined }])).toThrow(/markedBy/);
    expect(fails([{ ...rule, unless: "consent" }])).toThrow(
      /unless must be a condition on \{row\}/,
    );
    expect(fails([{ ...rule, set: { email: [1] } }])).toThrow(
      /set\.email must be a string/,
    );
    expect(fails([{ ...rule, set: { email: Number.NaN } }])).toThrow(
      /set\.email/,
    );
  });

  it("exports and purges incoming webhooks without their secrets", () => {
    const sql = sqlOf(["data-lifecycle", "webhooks-in"], {
      tables: { "app.keys": { tenant: "organization_id", omit: ["hash"] } },
    });
    expect(sql).toContain(
      `('organization', 'better_supabase.incoming_webhooks', '"better_supabase"."incoming_webhooks"', 'tenant', true, array['token_hash', 'secret', 'secret_id', 'previous_secret', 'previous_secret_id']::text[], true)`,
    );
    expect(sql).toContain(
      `('organization', 'app.keys', '"app"."keys"', 'organization_id', true, array['hash']::text[], true)`,
    );
    expect(sql).toContain(
      "jsonb_agg((to_jsonb(p.*) - ''_ctid'') - $4::text[] order by p._ctid)",
    );
    expect(sql).toContain("coalesce(v_table.omit, '{}')");
    expect(() =>
      sqlOf(["data-lifecycle"], {
        tables: { "app.keys": { tenant: "organization_id", omit: ["Bad"] } },
      }),
    ).toThrow(/omit must be a list/);
    expect(() =>
      sqlOf(["data-lifecycle"], {
        tables: { "app.keys": { tenant: "organization_id", export: "no" } },
      }),
    ).toThrow(/export must be true or false/);
    expect(() =>
      renderModules(["webhooks-in"], {
        modules: {
          "webhooks-in": { columns: { endpoints: { tenant: "org_id" } } },
        },
      }),
    ).toThrow(/can't be renamed/);
  });

  it("never exports API keys or invitation token hashes, and lets the app keep a table out of exports", () => {
    const sql = sqlOf(["data-lifecycle", "api-keys", "invitations"], {
      tables: {
        "app.secrets": { tenant: "organization_id", export: false },
        "better_supabase.invitations": {
          tenant: "organization_id",
          omit: ["token_hash", "email"],
        },
      },
    });
    expect(sql).toContain(
      `('organization', 'better_supabase.api_keys', '"better_supabase"."api_keys"', 'organization_id', true, '{}'::text[], false)`,
    );
    expect(sql).toContain(
      `('organization', 'app.secrets', '"app"."secrets"', 'organization_id', true, '{}'::text[], false)`,
    );
    expect(sql).toContain(
      `('organization', 'better_supabase.invitations', '"better_supabase"."invitations"', 'organization_id', true, array['token_hash', 'email']::text[], true)`,
    );
    expect(
      sql.match(/\('organization', 'better_supabase\.invitations'/g),
    ).toHaveLength(1);
    expect(sql).toContain(
      'where t.subject = v_row."subject" and t.exported and to_regclass(t.tbl) is not null',
    );
    expect(sql).toContain(
      "t.name = data_export_rows.table_name and t.exported;",
    );
    expect(sql).toContain(
      "t.subject = 'organization' and t.purge and to_regclass(t.tbl) is not null",
    );

    const defaults = sqlOf(["data-lifecycle", "invitations"]);
    expect(defaults).toContain(
      `('organization', 'better_supabase.invitations', '"better_supabase"."invitations"', 'organization_id', true, array['token_hash']::text[], true)`,
    );
  });
});
