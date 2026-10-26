import { toStandardJsonSchema } from "@valibot/to-json-schema";
import * as v from "valibot";
import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../src/config/blocks.ts";

import { withBlockSubjects } from "../../src/config/block-subjects.ts";
import { resolveConfig, resolveJsonSchema } from "../../src/config/index.ts";
import { eventTriggersOf } from "../../src/sql/event-triggers.ts";
import {
  moduleEventTriggers,
  modulePermissionKeys,
} from "../../src/sql/introspect.ts";
import { moduleLayout } from "../../src/sql/layout.ts";
import { sameBlockFile } from "../../src/sql/markers.ts";
import { resolveBlocks, SQL_MODULES } from "../../src/sql/registry.ts";
import { moduleTopics, renderBlocks } from "../../src/sql/render.ts";
import { stubProvider } from "../fixtures/authorization-provider.ts";

describe("resolveBlocks", () => {
  it("adds dependencies and keeps registry order", () => {
    expect(
      resolveBlocks(["invitations", "updated-at"]).map((module) => module.name),
    ).toEqual(["updated-at", "memberships", "invitations", "permissions"]);
  });

  it("deduplicates and rejects unknown modules", () => {
    expect(
      resolveBlocks(["memberships", "memberships", "invitations"]),
    ).toHaveLength(4);
    expect(() => resolveBlocks(["nope"])).toThrow(/Unknown SQL module "nope"/);
  });
});

describe("pg-safeupdate", () => {
  it("gives every delete in the modules a where clause", () => {
    const sql = renderBlocks(
      Object.keys(SQL_MODULES).filter((name) => name !== "pgtap"),
      { modules: { usage: { options: { history: true } } } },
    )
      .map((file) => file.contents.replaceAll(/--.*$/gm, ""))
      .join("\n");

    const deletes = [...sql.matchAll(/\bdelete\s+from\s+[^;]*;/gi)].map(
      (match) => match[0],
    );

    expect(deletes.length).toBeGreaterThan(10);
    expect(
      deletes.filter((statement) => !/\bwhere\b/i.test(statement)),
    ).toEqual([]);
  });
});

describe("plpgsql_check", () => {
  it("creates no temporary tables that supabase db lint cannot see", () => {
    const sql = renderBlocks(
      Object.keys(SQL_MODULES).filter((name) => name !== "pgtap"),
      { modules: { usage: { options: { history: true } } } },
    )
      .map((file) => file.contents.replaceAll(/--.*$/gm, ""))
      .join("\n");

    expect(sql).not.toMatch(/\bcreate\s+(?:temporary|temp)\s+table\b/i);
  });
});

describe("moduleTopics", () => {
  it("lists the topics whose policies the modules write", () => {
    expect(
      moduleTopics(["notifications", "announcements", "realtime-tables"]),
    ).toEqual([
      { module: "realtime-tables", topic: "bsb:t:*" },
      { module: "notifications", topic: "notifications:{userId}" },
      { module: "announcements", topic: "announcements" },
    ]);
    expect(
      moduleTopics(["notifications", "announcements"], {
        modules: {
          notifications: {
            options: { realtime: "changes", topic: "inbox:{userId}" },
          },
          announcements: { mode: "custom" },
        },
      }),
    ).toEqual([]);
    expect(
      moduleTopics(["notifications"], {
        modules: { notifications: { options: { topic: "inbox:{userId}" } } },
      }),
    ).toEqual([{ module: "notifications", topic: "inbox:{userId}" }]);
  });
});

describe("renderBlocks", () => {
  it("numbers files by registry position so paths stay stable", () => {
    const all = renderBlocks(Object.keys(SQL_MODULES));
    const jobs = renderBlocks(["queue"]);
    expect(jobs[0]!.path).toBe(
      all.find((file) => file.module === "queue")!.path,
    );
    expect(jobs[0]!.path).toMatch(
      /^supabase\/schemas\/900_better_supabase_\d{3}_queue\.sql$/,
    );
  });

  it("writes pgtap to the tests directory with a managed header", () => {
    const [file] = renderBlocks(["pgtap"], { testsDir: "db/tests/" });

    expect(file!.path).toBe("db/tests/000_better_supabase_pgtap.test.sql");
    expect(file!.contents).toMatch(/^-- better-supabase module: pgtap\n/);
    expect(file!.contents).toContain("Managed by `better-supabase add`");
    expect(file!.contents.endsWith("\n")).toBe(true);
  });

  it("honours dir and prefix", () => {
    const [file] = renderBlocks(["audit"], { dir: "schemas/", prefix: "zz" });
    expect(file!.path).toMatch(/^schemas\/zz_\d{3}_audit\.sql$/);
  });

  it("renders the audit log's tenant column from config and keys rows by their primary key", () => {
    const [plain] = renderBlocks(["audit"]);
    expect(plain!.contents).toContain(
      "row_data ->> coalesce(entry.tenant_column, 'organization_id')",
    );
    const [file] = renderBlocks(["audit"], { tenantColumn: "team_id" });
    expect(file!.contents).toContain(
      "row_data ->> coalesce(entry.tenant_column, 'team_id')",
    );
    expect(file!.contents).not.toContain("'organization_id'");
    expect(file!.contents).toContain("i.indisprimary");
    expect(file!.contents).not.toContain("row_data ->> 'id'");
  });

  it("keeps every schema module in the better_supabase schema", () => {
    for (const module of Object.values(SQL_MODULES)) {
      if (module.target !== "schema") {
        continue;
      }

      const functions = [
        ...module.sql.matchAll(/create or replace function ([\w.]+)\(/g),
      ];

      for (const [, name] of functions) {
        expect(name).toMatch(/^better_supabase\./);
      }

      expect(module.sql).not.toMatch(/create table (?!if not exists)/);
    }
  });

  it("keeps statements a schema diff skips out of the schema files", () => {
    const layouts = [
      {},
      { modules: { queue: { options: { backend: "table" } } } },
    ];

    for (const layout of layouts) {
      const files = renderBlocks(Object.keys(SQL_MODULES), layout);

      for (const file of files.filter((entry) => entry.kind === "schema")) {
        expect(file.contents).not.toMatch(
          /^(insert|update|delete|select|truncate|notify|alter role|call)\b/im,
        );
      }

      for (const file of files.filter((entry) => entry.kind === "data")) {
        expect(file.path).toMatch(/\/better-supabase-data\/[^/]+\.sql$/);
        expect(file.contents).not.toMatch(
          /^(create(?! extension if not exists "\w+"( with schema "\w+")?;$| event trigger )|drop(?! event trigger if exists \w+;$)|alter table)\b/im,
        );
      }
    }
  });

  it("shapes the features claim with entitlements.claim", () => {
    const entitlements = (claim: unknown) =>
      renderBlocks(["entitlements"], {
        entitlements: {
          key: "id",
          source: "custom",
          ...(claim === undefined ? {} : { claim }),
        },
      } as never).find((file) => file.module === "entitlements")!.contents;

    expect(entitlements(undefined)).toContain(
      "jsonb_object_agg(r.tenant, to_jsonb(r.keys))",
    );
    expect(entitlements(false)).toMatch(
      /feature_claims\(user_id uuid\)[\s\S]*?as \$\$\n {2}select '\{\}'::jsonb\n\$\$/,
    );
    const compact = entitlements({ maxTenants: 20, keys: { exports: "x" } });
    expect(compact).toContain(
      `coalesce('{"exports":"x"}'::jsonb ->> k, k) from unnest(r.keys) as k`,
    );
    expect(compact).toContain("order by 1\n    limit 20");
    expect(() => entitlements({ maxTenants: 0 })).toThrow(/maxTenants/);
  });

  it("wraps auth calls in policies so Postgres evaluates them once", () => {
    const names = Object.values(SQL_MODULES)
      .filter((module) => module.target === "schema")
      .map((module) => module.name);

    const unwrapped = renderBlocks(names).flatMap((file) =>
      [...file.contents.matchAll(/create policy[\s\S]*?;/g)]
        .map((match) => match[0])
        .filter((policy) => /(?<!select )auth\.(uid|jwt|role)\(\)/.test(policy))
        .map((policy) => `${file.module}: ${policy.slice(0, 80)}`),
    );

    expect(unwrapped).toEqual([]);
  });

  it("checks tenant permissions in read policies with a set, not can() per row", () => {
    const layouts = [
      {},
      {
        subjects: {
          deal: {
            table: "public.deals",
            idType: "uuid",
            permissions: { read: "deals.read", moderate: "deals.moderate" },
          },
        },
      },
    ];

    for (const layout of layouts) {
      const perRow = renderBlocks(Object.keys(SQL_MODULES), layout).flatMap(
        (file) =>
          [...file.contents.matchAll(/create policy[\s\S]*?;\n/g)]
            .map((match) => match[0].split(/\bwith check\b/)[0]!)
            .filter((using) =>
              /\busing \([\s\S]*better_supabase\.can\('tenant', "/.test(using),
            )
            .map((policy) => `${file.module}: ${policy.slice(0, 100)}`),
      );

      expect(perRow).toEqual([]);
    }
  });

  it("compares subject ids on the id column's type when idType is set", () => {
    const reactions = (subject: { table: string; idType?: string }) =>
      renderBlocks(["reactions"], { subjects: { deal: subject } }).find(
        (file) => file.module === "reactions",
      )!.contents;

    expect(reactions({ table: "deals", idType: "uuid" })).toContain(
      `s."id" = (reaction_subject_visible.subject_id)::uuid`,
    );
    expect(reactions({ table: "deals" })).toContain(
      `s."id"::text = reaction_subject_visible.subject_id`,
    );
    expect(() => reactions({ table: "deals", idType: "uuid; drop" })).toThrow(
      /idType/,
    );
  });

  it("creates the extensions a module's schema file creates in its data file", () => {
    const data = (name: string, layout = {}) =>
      renderBlocks([name], layout).find(
        (file) => file.kind === "data" && file.module === name,
      )!.contents;

    expect(data("queue")).toContain('create extension if not exists "pgmq";');
    expect(
      data("queue", { modules: { queue: { options: { backend: "table" } } } }),
    ).not.toContain("create extension");
    expect(data("jsonb-schemas")).toContain(
      'create extension if not exists "pg_jsonschema" with schema "extensions";',
    );
    expect(data("flags")).toContain(
      'create extension if not exists "pgcrypto" with schema "extensions";',
    );
  });
});

describe("module order", () => {
  it("binds a later module's tables late in sql functions", () => {
    const all = Object.keys(SQL_MODULES);
    const order = [...all];

    const later = ["messages", "conversations", "conversation_members"].map(
      (table) => `"better_supabase"."${table}"`,
    );

    const early = renderBlocks(all, {
      subjects: withBlockSubjects({}, all, {}),
    })
      .filter(
        (file) =>
          file.kind !== "data" &&
          order.indexOf(file.module) < order.indexOf("messaging"),
      )
      .flatMap((file) =>
        [
          ...file.contents.matchAll(
            /create or replace function ([^\s(]+)[\s\S]*?language sql[\s\S]*?\$\$([\s\S]*?)\$\$/g,
          ),
        ]
          .filter((match) =>
            later.some((table) =>
              (match[2] ?? "").replaceAll(/'[^']*'/g, "").includes(table),
            ),
          )
          .map((match) => `${file.module}: ${match[1]}`),
      );

    expect(early).toEqual([]);
  });
});

describe("module event triggers", () => {
  it("repeats a module's event triggers in its data file", () => {
    const data = (name: string) =>
      renderBlocks([name]).find(
        (file) => file.kind === "data" && file.module === name,
      )!.contents;

    expect(data("audit")).toContain(
      "drop event trigger if exists bsb_audit_forget_dropped;\ncreate event trigger bsb_audit_forget_dropped on sql_drop\n  when tag in ('DROP TABLE', 'DROP SCHEMA')\n  execute function better_supabase.audit_forget_dropped();",
    );
    expect(data("rls-guard")).toContain(
      "drop event trigger if exists bsb_ensure_rls;\ncreate event trigger bsb_ensure_rls on ddl_command_end",
    );
    expect(data("memberships")).not.toContain("event trigger");
  });

  it("names the event triggers of the installed modules", () => {
    expect(moduleEventTriggers(["audit", "rls-guard", "memberships"])).toEqual([
      { module: "audit", name: "bsb_audit_forget_dropped" },
      { module: "rls-guard", name: "bsb_ensure_rls" },
    ]);
    expect(
      moduleEventTriggers(["broken", "missing"], {
        broken: {
          ...SQL_MODULES["memberships"]!,
          get sql(): string {
            throw new Error("no default layout");
          },
        },
      }),
    ).toEqual([]);
  });

  it("reads quoted names once", () => {
    expect(
      eventTriggersOf(
        'create event trigger "Bs_Quoted" on sql_drop execute function f();\ncreate event trigger "Bs_Quoted" on sql_drop execute function f();',
      ),
    ).toEqual([
      {
        name: "Bs_Quoted",
        statement:
          'drop event trigger if exists "Bs_Quoted";\ncreate event trigger "Bs_Quoted" on sql_drop execute function f();',
      },
    ]);
  });
});

describe("rls-guard", () => {
  it("installs a replaceable event trigger that skips managed schemas", () => {
    const [file] = renderBlocks(["rls-guard"]);
    expect(file!.path).toMatch(/_rls_guard\.sql$/);
    expect(file!.contents).toContain(
      "drop event trigger if exists bsb_ensure_rls;",
    );
    expect(file!.contents).toContain(
      "create event trigger bsb_ensure_rls on ddl_command_end",
    );
    expect(file!.contents).toContain(
      "when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO', 'ALTER TABLE')",
    );

    for (const schema of ["auth", "storage", "realtime", "extensions"]) {
      expect(file!.contents).toContain(`'${schema}'`);
    }

    expect(file!.contents).toContain(String.raw`like 'pg\_%'`);
  });
});

describe("sameBlockFile", () => {
  it("ignores a version in the header only", () => {
    const [file] = renderBlocks(["updated-at"]);

    const older = file!.contents.replace(
      "-- better-supabase module: updated-at\n",
      "-- better-supabase module: updated-at (0.12.0)\n",
    );

    expect(older).not.toBe(file!.contents);
    expect(sameBlockFile(older, file!.contents)).toBe(true);
    expect(sameBlockFile(`${file!.contents}-- edited\n`, file!.contents)).toBe(
      false,
    );
    expect(sameBlockFile(undefined, file!.contents)).toBe(false);
  });

  it("keeps the package version out of the header", () => {
    for (const file of renderBlocks(["audit", "updated-at"])) {
      expect(file.contents.split("\n", 1)[0]).toMatch(
        /^-- better-supabase module: [a-z-]+$/,
      );
    }
  });

  it("checks tenant topics against live membership, not the token claim", () => {
    const contents = renderBlocks(["memberships", "realtime-tables"]).find(
      (file) => file.contents.includes("bsb_realtime_tables_receive"),
    )!.contents;

    expect(contents).toContain("member_organization_ids() as m");
    expect(contents).not.toContain("app_metadata");
    expect(renderBlocks(["realtime-tables"])[0]!.contents).not.toContain(
      "member_organization_ids",
    );
  });

  it("registers realtime tables with the tenant column", () => {
    const [file] = renderBlocks(["realtime-tables"], {
      realtimeTables: ["customers", "billing.invoices", "plans"],
      realtimeGlobal: ["public.plans"],
      tenantColumn: "organization_id",
    });

    expect(file!.contents).toContain(
      "select better_supabase.track_realtime('public.customers', tenant_column => 'organization_id');",
    );
    expect(file!.contents).toContain(
      "select better_supabase.track_realtime('billing.invoices', tenant_column => 'organization_id');",
    );
    expect(file!.contents).toContain(
      "select better_supabase.track_realtime('public.plans', tenant_column => null);",
    );
    expect(file!.contents).toContain("raise exception '% has no column %'");
    expect(renderBlocks(["realtime-tables"])[0]!.contents).not.toContain(
      "config.realtime.tables",
    );
  });

  it("registers realtime.users tables per user, and lets only that user receive them", () => {
    const [file] = renderBlocks(["realtime-tables"], {
      realtimeTables: ["notifications", "customers"],
      realtimeUsers: { notifications: "user_id" },
      tenantColumn: "organization_id",
    });

    expect(file!.contents).toContain(
      "select better_supabase.track_realtime('public.notifications', tenant_column => null, user_column => 'user_id');",
    );
    expect(file!.contents).toContain(
      "select better_supabase.track_realtime('public.customers', tenant_column => 'organization_id');",
    );
    expect(file!.contents).toContain(
      "split_part((select realtime.topic()), ':', 5) = (select auth.uid())::text",
    );
  });

  it("adds pg_jsonschema checks for json config schemas", () => {
    const schema = resolveJsonSchema(
      toStandardJsonSchema(v.object({ source: v.string() })),
    );

    expect(schema).toMatchObject({ type: "object", required: ["source"] });
    expect(resolveJsonSchema({ type: "array" })).toEqual({ type: "array" });

    const [file] = renderBlocks(["jsonb-schemas"], {
      jsonSchemas: [
        { table: "customers", column: "metadata", schema: { type: "object" } },
        {
          table: "billing.invoices",
          column: "lines",
          schema: { type: "array" },
        },
      ],
    });

    expect(file!.contents).toContain(
      "create extension if not exists pg_jsonschema with schema extensions;",
    );
    expect(file!.contents).toContain(
      `alter table "public"."customers" add constraint "bsb_json_metadata"\n  check (extensions.jsonb_matches_schema('{"type":"object"}'::json, "metadata")) not valid;\nalter table "public"."customers" validate constraint "bsb_json_metadata";`,
    );
    expect(file!.contents).toContain(
      'alter table "billing"."invoices" drop constraint if exists "bsb_json_lines";',
    );
  });

  it("writes the complete Data API grants from the expose config", () => {
    const config = resolveConfig(
      {
        database: {
          expose: {
            customers: ["select", "insert", "update", "delete"],
            "billing.invoices": {
              anon: ["select"],
              authenticated: ["select"],
              serviceRole: ["select", "insert"],
            },
            "search_notes(text, integer)": { execute: ["authenticated"] },
            "billing.reprice(uuid)": { execute: [], serviceRole: false },
          },
        },
      },
      "/project",
    );

    const [file] = renderBlocks(["grants"], moduleLayout(config));
    expect(file!.path).toBe(
      "supabase/schemas/900_better_supabase_013_grants.sql",
    );
    expect(file!.contents).toContain(
      [
        "-- config.expose",
        'revoke all on table "public"."customers" from public, anon, authenticated, service_role;',
        'grant select, insert, update, delete on table "public"."customers" to authenticated;',
        'grant select, insert, update, delete on table "public"."customers" to service_role;',
        'revoke all on table "billing"."invoices" from public, anon, authenticated, service_role;',
        'grant select on table "billing"."invoices" to anon;',
        'grant select on table "billing"."invoices" to authenticated;',
        'grant select, insert on table "billing"."invoices" to service_role;',
        'revoke execute on function "public"."search_notes"(text, integer) from public, anon, authenticated, service_role;',
        'grant execute on function "public"."search_notes"(text, integer) to authenticated, service_role;',
        'revoke execute on function "billing"."reprice"(uuid) from public, anon, authenticated, service_role;',
      ].join("\n"),
    );
    expect(file!.contents).not.toContain('"reprice"(uuid) to');
    expect(renderBlocks(["grants"])[0]!.contents).not.toContain(
      "config.expose",
    );
  });

  it("checks slug lengths and lets service_role read the reserved slugs", () => {
    const [file] = renderBlocks(["reserved-slugs"], {
      modules: {
        "reserved-slugs": { options: { minLength: 3, maxLength: 40 } },
      },
    });

    expect(file!.contents).toContain(
      'grant select on "better_supabase"."reserved_slugs" to anon, authenticated, service_role;',
    );
    expect(file!.contents).toContain(
      "when length(slug) < 3 or length(slug) > 40 then 'invalid'",
    );
    expect(renderBlocks(["reserved-slugs"])[0]!.contents).toContain(
      "when length(slug) < 1 or length(slug) > 63 then 'invalid'",
    );
    expect(() =>
      renderBlocks(["reserved-slugs"], {
        modules: {
          "reserved-slugs": { options: { minLength: 5, maxLength: 4 } },
        },
      }),
    ).toThrow(/minLength and maxLength must be whole numbers/);
  });

  it("points the pre-request hook at check_request unless preRequest is false", () => {
    const data = (layout = {}) =>
      renderBlocks(["rate-limit"], layout).find((file) => file.kind === "data")!
        .contents;

    expect(data()).toContain(
      "alter role authenticator set pgrst.db_pre_request = 'better_supabase.check_request';",
    );

    const off = data({
      modules: { "rate-limit": { options: { preRequest: false } } },
    });

    expect(off).not.toContain("authenticator set pgrst.db_pre_request");
    expect(off).toContain(
      "alter role authenticator reset pgrst.db_pre_request;",
    );
    expect(renderBlocks(["rate-limit"])[0]!.contents).toContain(
      "if current_setting('transaction_read_only', true) = 'on' then",
    );
  });

  it("writes the session policy on the declared tables except the excluded ones", () => {
    const layout = {
      modules: {
        sessions: { options: { policies: true, exclude: ["public.audit_*"] } },
      },
      declaredTables: ["public.invoices", "public.audit_log"],
    };

    const [file] = renderBlocks(["sessions"], layout);
    expect(file!.contents).toContain(
      [
        'drop policy if exists bsb_session_active on "public"."invoices";',
        'create policy bsb_session_active on "public"."invoices" as restrictive',
        "  for all to authenticated",
        "  using ((select better_supabase.session_active()))",
        "  with check ((select better_supabase.session_active()));",
      ].join("\n"),
    );
    expect(file!.contents).not.toContain("audit_log");
    expect(
      renderBlocks(["sessions"], { declaredTables: ["public.invoices"] })[0]!
        .contents,
    ).not.toContain("bsb_session_active");
  });

  it("writes a service-only last_sign_ins in the sessions module", () => {
    const [file] = renderBlocks(["sessions"], {});
    expect(file!.contents).toContain(
      "create or replace function better_supabase.last_sign_ins(p_users uuid[])\nreturns table (user_id uuid, last_sign_in_at timestamptz)",
    );
    expect(file!.contents).toContain(
      [
        "revoke execute on function better_supabase.last_sign_ins(uuid[]) from public, anon, authenticated;",
        "grant execute on function better_supabase.last_sign_ins(uuid[]) to service_role;",
      ].join("\n"),
    );
    expect(file!.contents).toMatch(
      /last_sign_ins[\s\S]*security definer\s+set search_path = ''/,
    );
  });

  it("derives table grants from policies for tables expose doesn't list", () => {
    const config = resolveConfig(
      {
        database: { expose: { customers: ["select"] } },
        blocks: { grants: { options: { fromPolicies: true } } },
      },
      "/project",
    );

    const [file] = renderBlocks(["grants"], {
      ...moduleLayout(config),
      policyGrants: [
        {
          table: "public.customers",
          role: "authenticated",
          privileges: ["select", "delete"],
        },
        {
          table: "public.notes",
          role: "authenticated",
          privileges: ["select", "insert"],
        },
      ],
    });

    expect(file!.contents).toContain(
      "-- config.expose and the policies (blocks['grants'].options.fromPolicies)",
    );
    expect(file!.contents).toContain(
      'grant select on table "public"."customers" to authenticated;',
    );
    expect(file!.contents).not.toContain(
      'grant select, delete on table "public"."customers"',
    );
    expect(file!.contents).toContain(
      [
        'revoke all on table "public"."notes" from public, anon, authenticated, service_role;',
        'grant select, insert on table "public"."notes" to authenticated;',
        'grant select, insert, update, delete on table "public"."notes" to service_role;',
      ].join("\n"),
    );
  });

  it("makes declared tables without a policy or expose entry service-only under fromPolicies", () => {
    const config = resolveConfig(
      {
        database: { expose: { customers: ["select"] } },
        blocks: { grants: { options: { fromPolicies: true } } },
      },
      "/project",
    );

    const layout = {
      ...moduleLayout(config),
      policyGrants: [
        {
          table: "public.notes",
          role: "authenticated" as const,
          privileges: ["select"],
        },
      ],
      declaredTables: [
        "public.customers",
        "public.notes",
        "public.jobs",
        "audit.entries",
      ],
      rlsTables: [
        "public.customers",
        "public.notes",
        "public.jobs",
        "audit.entries",
      ],
    };

    const [file] = renderBlocks(["grants"], layout);
    expect(file!.contents).toContain(
      [
        'revoke all on table "public"."jobs" from public, anon, authenticated, service_role;',
        'grant select, insert, update, delete on table "public"."jobs" to service_role;',
        'revoke all on table "audit"."entries" from public, anon, authenticated, service_role;',
        'grant select, insert, update, delete on table "audit"."entries" to service_role;',
      ].join("\n"),
    );
    expect(file!.contents).not.toContain(
      'grant select, insert, update, delete on table "public"."notes" to authenticated',
    );

    const [rlsOff] = renderBlocks(["grants"], {
      ...layout,
      rlsTables: ["audit.entries"],
    });

    expect(rlsOff!.contents).not.toContain('"public"."jobs"');
    expect(rlsOff!.contents).toContain('"audit"."entries"');

    const [without] = renderBlocks(["grants"], {
      ...moduleLayout(config),
      declaredTables: layout.declaredTables,
    });

    expect(without!.contents).not.toContain('"public"."jobs"');
  });

  it("rejects a function entry without a signature and table privileges on a function", () => {
    expect(() =>
      resolveConfig(
        { database: { expose: { "search_notes(text)": ["select"] } } },
        "/project",
      ),
    ).toThrow(/a function takes \{ execute/);
    expect(() =>
      resolveConfig(
        { database: { expose: { notes: { execute: ["authenticated"] } } } },
        "/project",
      ),
    ).toThrow(/key it by its signature/);

    const config = resolveConfig(
      { database: { expose: { "bad name()x)": { execute: ["anon"] } } } },
      "/project",
    );

    expect(() => renderBlocks(["grants"], moduleLayout(config))).toThrow(
      /is not a function signature/,
    );
  });

  it("writes a search function per vectorSearch table", () => {
    const config = resolveConfig(
      {
        database: {
          vectorSearch: {
            chunks: "embedding",
            "docs.pages": { column: "vec", distance: "inner_product" },
          },
        },
      },
      "/project",
    );

    const [file] = renderBlocks(["vector-search"], moduleLayout(config));
    expect(file!.path).toBe(
      "supabase/schemas/900_better_supabase_018_vector_search.sql",
    );
    expect(file!.contents).toContain(
      [
        'create or replace function "public"."search_chunks"(query extensions.vector, k integer default 10)',
        'returns setof "public"."chunks"',
        "language plpgsql",
        "stable",
        "security invoker",
        "set search_path = ''",
        "as $$",
        "#variable_conflict use_column",
        "declare",
        "  previous_scan text := current_setting('hnsw.iterative_scan', true);",
        "begin",
        "  perform set_config('hnsw.iterative_scan', 'strict_order', true);",
      ].join("\n"),
    );
    expect(file!.contents).not.toContain("set hnsw.iterative_scan");
    expect(file!.contents).toContain(
      "  perform set_config('hnsw.iterative_scan', coalesce(previous_scan, 'off'), true);",
    );
    expect(file!.contents).toContain(
      'order by t."embedding" operator(extensions.<=>) query',
    );
    expect(file!.contents).toContain(
      'order by t."vec" operator(extensions.<#>) query',
    );
    expect(file!.contents).toContain(
      'grant execute on function "docs"."search_pages"(extensions.vector, integer) to authenticated, service_role;',
    );
    expect(renderBlocks(["vector-search"])[0]!.contents).not.toContain(
      "config.vectorSearch",
    );

    const elsewhere = (layout: Record<string, unknown>) =>
      renderBlocks(["vector-search"], {
        ...moduleLayout(config),
        ...layout,
      })[0]!.contents;

    const found = elsewhere({ vectorSchema: "public" });
    expect(found).toContain(
      "create extension if not exists vector with schema public;",
    );
    expect(found).toContain(
      '"public"."search_chunks"(query public.vector, k integer default 10)',
    );
    expect(found).toContain("operator(public.<=>) query");
    expect(found).not.toContain("extensions.");
    expect(
      elsewhere({
        vectorSchema: "public",
        modules: { "vector-search": { options: { schema: "vec" } } },
      }),
    ).toContain("query vec.vector");
    expect(() =>
      elsewhere({
        modules: { "vector-search": { options: { schema: "Bad" } } },
      }),
    ).toThrow(/options\.schema must be the lowercase name/);
  });
});

describe("vector search options", () => {
  const render = (entry: Record<string, unknown>) =>
    renderBlocks(
      ["vector-search"],
      moduleLayout(
        resolveConfig(
          {
            database: {
              vectorSearch: { chunks: { column: "embedding", ...entry } },
            },
          },
          "/project",
        ),
      ),
    )[0]!.contents;

  it("writes a scores function next to every search function", () => {
    const sql = render({});
    expect(sql).toContain(
      'create or replace function "public"."search_chunks_scores"(query extensions.vector, k integer default 10)',
    );
    expect(sql).toContain("returns table (id jsonb, score double precision)");
    expect(sql).toContain(
      'select t."id" as id, t."embedding" operator(extensions.<=>) query as distance',
    );
    expect(sql).toContain("1 - v.distance as score");
    expect(sql).toContain(
      'drop function if exists "public"."search_chunks"(extensions.vector, integer, jsonb, text);',
    );
  });

  it("ranks halfvec columns with hybrid RRF, a boost and prefilters", () => {
    const sql = render({
      type: "halfvec",
      key: "chunk_id",
      distance: "l2",
      hybrid: { tsvector: "content_tsv", config: "english", k: 50 },
      boost: "t.priority",
      prefilter: ["collection_id", "organization_id"],
    });

    expect(sql).toContain(
      'create or replace function "public"."search_chunks"(query extensions.halfvec, k integer default 10, filter jsonb default \'{}\', text_query text default null)',
    );
    expect(sql).toContain(
      "websearch_to_tsquery('english'::regconfig, text_query) q",
    );
    expect(sql).toContain(
      "coalesce(1.0 / (50 + v.rank), 0) + coalesce(1.0 / (50 + x.rank), 0) as score",
    );
    expect(sql).toContain("coalesce((t.priority)::double precision, 1)");
    expect(sql).toContain(
      `and (not filter ? 'organization_id' or t."organization_id" = any (array(`,
    );
    expect(sql).toContain(
      `(jsonb_populate_record(null::"public"."chunks", jsonb_build_object('organization_id', f.v)))."organization_id"`,
    );
    expect(sql).toContain("least(greatest(k, 1) * 4, 1000)");
    expect(sql).toContain('join "public"."chunks" t on t."chunk_id" = r.id');
    expect(sql).toContain(
      'drop function if exists "public"."search_chunks"(extensions.halfvec, integer);',
    );
  });

  it("filters with a predicate, adds the boost, breaks ties and allows text alone", () => {
    const sql = render({
      hybrid: { tsvector: "tsv" },
      boost: "t.bonus",
      boostMode: "add",
      predicate: "t.expires_at > now()",
      order: "t.created_at desc",
    });

    expect(sql.match(/and \(t\.expires_at > now\(\)\)/g)).toHaveLength(4);
    expect(sql).toContain("and query is not null");
    expect(sql).toContain(
      "(f.score + coalesce((t.bonus)::double precision, 0))",
    );
    expect(sql).toContain(
      "row_number() over (order by (f.score + coalesce((t.bonus)::double precision, 0))::double precision desc, t.created_at desc) as ord",
    );
    expect(sql).toContain("order by r.ord");
    expect(render({ order: "t.id" })).toContain("text_query text default null");
    expect(() => render({ predicate: "true; drop table x" })).toThrow(
      /predicate must be one SQL expression/,
    );
    expect(() => render({ boost: "1", boostMode: "max" })).toThrow(/boostMode/);
  });

  it("scores each distance and checks the options", () => {
    expect(render({ distance: "inner_product" })).toContain(
      "-v.distance as score",
    );
    expect(render({ prefilter: ["kind"] })).toContain(
      "least(greatest(k, 1), 1000)",
    );
    expect(() =>
      render({ hybrid: { tsvector: "tsv", config: "english; drop" } }),
    ).toThrow(/text search configuration/);
    expect(() => render({ hybrid: { tsvector: "tsv", k: 0 } })).toThrow(
      /positive integer/,
    );
    expect(() => render({ boost: "1; drop table x" })).toThrow(
      /one SQL expression/,
    );
  });
});

describe("entitlements with provider memberships", () => {
  const entitlementsProvider = {
    name: "stub",
    scope: "organization",
    idType: "uuid",
    memberIds: stubProvider.functions.memberIds,
    memberIdsFor: stubProvider.functions.memberIdsFor,
    memberships: [
      {
        table: "public.memberships",
        userColumn: "user_id",
        scope: { column: "scope" },
        idColumn: "scope_id",
      },
      {
        table: "public.contacts",
        userColumn: "user_id",
        scope: { value: "customer" },
        idColumn: "customer_id",
      },
    ],
  } as const;

  const entitlements = {
    table: "organizations",
    column: "stripe_customer_id",
    key: "id",
  };

  it("drops the tenant dependency", () => {
    expect(
      resolveBlocks(["entitlements"]).map((module) => module.name),
    ).toEqual(["updated-at", "memberships", "entitlements"]);
    expect(
      resolveBlocks(["entitlements"], { entitlementsProvider }).map(
        (module) => module.name,
      ),
    ).toEqual(["entitlements"]);
  });

  it("reads member_<scope>_ids and member_<scope>_ids_for", () => {
    const [file] = renderBlocks(["entitlements"], {
      entitlementsProvider,
      entitlements,
    });

    const sql = file!.contents;
    expect(sql).toContain(
      "select tenant::text in (select t.id::text from authz.member_organization_ids() as t(id))",
    );
    expect(sql).toContain(
      "from authz.member_organization_ids_for(feature_claims.user_id) as t(id)",
    );
    expect(sql).toContain("Register it with the provider's access token hook");
    expect(sql).not.toContain("has_organization_role");
    expect(sql).not.toContain("better_supabase.memberships");
    // entitlement_members reads the organization-scoped source only.
    expect(sql).toContain(
      `from "public"."memberships" m\n  where m."scope_id"::text in (select t::text from better_supabase.stripe_customer_tenants(customer) t)\n    and m."scope"::text = 'organization'`,
    );
    expect(sql).not.toContain('"public"."contacts"');
  });

  it.each(["uuid", "text", "bigint", "integer"] as const)(
    "renders the %s scope id type in every tenant signature",
    (idType) => {
      const file = renderBlocks(["entitlements"], {
        entitlementsProvider: { ...entitlementsProvider, idType },
        entitlements,
      }).find((entry) => entry.module === "entitlements");

      const sql = file!.contents;

      for (const signature of [
        `has_entitlement(tenant ${idType}, key text)`,
        `has_entitlement(${idType}, text)`,
        `tenant_entitlements(tenant ${idType})`,
        `tenant_entitlements(${idType})`,
        `tenant_stripe_customer(tenant ${idType})`,
        `tenant_stripe_customer(${idType})`,
      ]) {
        expect(sql).toContain(signature);
      }

      expect(sql).toContain(`returns setof ${idType}`);
      expect(sql).toContain("feature_claims(user_id uuid)");
      expect(
        sql.match(/\(tenant (\w+)/g)?.map((match) => match.slice(8)),
      ).toEqual([idType, idType, idType, idType, idType]);
      expect(sql).toMatchSnapshot();
    },
  );

  it("keeps the tenant-mode functions without a provider", () => {
    const file = renderBlocks(["entitlements"], { entitlements }).find(
      (entry) => entry.module === "entitlements",
    );

    expect(file!.contents).toContain(
      "select better_supabase.has_organization_role(tenant)",
    );
    expect(file!.contents).toContain('from "better_supabase"."memberships" m');
  });

  it("needs a customer column unless the block's own organizations table gets one", () => {
    expect(() => renderBlocks(["entitlements"])).toThrow(
      "The entitlements module needs auth.entitlements.customer",
    );
    expect(() =>
      renderBlocks(["entitlements", "organizations"], {
        modules: {
          organizations: { tables: { organizations: "public.organizations" } },
        },
        ownTables: { "public.organizations": "supabase/schemas/app.sql" },
      }),
    ).toThrow("The entitlements module needs auth.entitlements.customer");
    const files = renderBlocks(["entitlements", "organizations"]);

    const sql = (name: string) =>
      files.find((file) => file.module === name && file.kind === "schema")!
        .contents;

    expect(sql("entitlements")).toContain(
      'select t."stripe_customer_id" from "better_supabase"."organizations" t where t."id" = tenant',
    );
    expect(sql("organizations")).toContain(
      "add column if not exists stripe_customer_id text unique;",
    );
    expect(sql("entitlements")).toContain("returns text\nlanguage plpgsql");
    expect(
      renderBlocks(["entitlements"], {
        entitlements: {
          table: "billing",
          column: "customer",
          key: "organization",
        },
      }).find(
        (file) => file.module === "entitlements" && file.kind === "schema",
      )!.contents,
    ).toContain("returns text\nlanguage sql");
    expect(
      renderBlocks(["organizations"]).find(
        (file) => file.module === "organizations",
      )!.contents,
    ).not.toContain("stripe_customer_id");
  });
});

describe("modulePermissionKeys", () => {
  it("lists every key the installed modules check, with its scope", () => {
    const keys = modulePermissionKeys({}, ["organizations", "impersonation"]);

    expect(keys).toContainEqual({
      module: "organizations",
      action: "update",
      key: "organization.update",
      scope: "tenant",
    });
    expect(keys).toContainEqual({
      module: "impersonation",
      action: "start",
      key: "support.start",
      scope: "platform",
    });
    expect(keys.map((entry) => entry.module)).not.toContain("notifications");
  });

  it("lists a numbering entity's own assign key", () => {
    const keys = modulePermissionKeys(
      {
        numbering: {
          options: {
            entities: {
              invoice: {
                period: "year",
                format: "{n}",
                permission: "invoices.write",
              },
              quote: { period: "year", format: "{n}" },
            },
          },
        },
      },
      ["numbering"],
    );

    expect(keys.filter((entry) => entry.module === "numbering")).toEqual([
      {
        module: "numbering",
        action: "assign",
        key: "number_sequences.assign",
        scope: "tenant",
      },
      {
        module: "numbering",
        action: "assign",
        key: "invoices.write",
        scope: "tenant",
        setting: "blocks.numbering.options.entities.invoice.permission",
      },
    ]);
  });

  it("lists the access-requests approve key the default policy checks", () => {
    const approve = (options: Record<string, unknown>) =>
      modulePermissionKeys(
        {
          "access-requests": {
            options,
            permissions: { approve: "roles.grant" },
          },
        },
        ["access-requests"],
      ).filter((entry) => entry.action === "approve");

    expect(approve({})).toEqual([
      {
        module: "access-requests",
        action: "approve",
        key: "roles.grant",
        scope: "tenant",
        setting: "blocks.access-requests.permissions.approve",
      },
    ]);
    expect(
      approve({
        policy: { steps: [{ approvers: { permission: "owners.approve" } }] },
      }),
    ).toEqual([]);
  });

  it("defaults suspendMember to the removeMember key", () => {
    const suspend = (permissions: Record<string, string>) =>
      modulePermissionKeys({ organizations: { permissions } }, [
        "organizations",
      ]).find((entry) => entry.action === "suspendMember")?.key;

    expect(suspend({})).toBe("members.remove");
    expect(suspend({ removeMember: "member.remove" })).toBe("member.remove");
    expect(
      suspend({
        removeMember: "member.remove",
        suspendMember: "member.suspend",
      }),
    ).toBe("member.suspend");
  });

  it("defaults sibling actions to the key they follow", () => {
    const key = (modules: AnyBlocksConfig, module: string, action: string) =>
      modulePermissionKeys(modules, [module]).find(
        (entry) => entry.module === module && entry.action === action,
      )?.key;

    const invite = {
      invitations: { permissions: { invite: "member.invite" } },
    };

    expect(key(invite, "invitations", "revoke")).toBe("member.invite");
    expect(key(invite, "invitations", "view")).toBe("member.invite");
    expect(key(invite, "waitlist", "invite")).toBe("member.invite");
    expect(
      key(
        { billing: { permissions: { read: "billing.view" } } },
        "billing",
        "viewAll",
      ),
    ).toBe("billing.view");
    expect(
      key(
        { audit: { permissions: { view: "audit.view" } } },
        "audit",
        "viewAll",
      ),
    ).toBe("audit.view");
    expect(
      key(
        {
          invitations: {
            permissions: { invite: "member.invite", view: "member.view" },
          },
        },
        "invitations",
        "view",
      ),
    ).toBe("member.view");
    expect(key({}, "waitlist", "invite")).toBe("members.invite");
  });

  it("applies blocks.<module>.permissions and skips custom modules", () => {
    expect(
      modulePermissionKeys(
        { notifications: { permissions: { send: "alerts.send" } } },
        ["notifications"],
      ).filter((entry) => entry.module === "notifications"),
    ).toEqual([
      {
        module: "notifications",
        action: "send",
        key: "alerts.send",
        scope: "tenant",
      },
      {
        module: "notifications",
        action: "read",
        key: "notifications.read",
        scope: "tenant",
      },
    ]);
    expect(
      modulePermissionKeys({ "webhooks-out": { mode: "custom" } }, [
        "webhooks-out",
      ]).filter((entry) => entry.module === "webhooks-out"),
    ).toEqual([]);
  });

  it("lists invitations.invitePlatform only with platform roles", () => {
    const platform = (modules: Parameters<typeof modulePermissionKeys>[0]) =>
      modulePermissionKeys(modules, ["invitations"]).some(
        (entry) => entry.action === "invitePlatform",
      );

    expect(platform({ permissions: { model: "provider" } })).toBe(false);
    expect(platform({ permissions: { model: "catalog" } })).toBe(true);
  });

  it("lists the optional platform keys an organizations config names", () => {
    expect(
      modulePermissionKeys(
        {
          organizations: {
            permissions: {
              create: "platform.organization.create",
              deletePlatform: "platform.organization.delete",
            },
          },
        },
        ["organizations"],
      ).filter((entry) => entry.scope === "platform"),
    ).toEqual([
      {
        module: "organizations",
        action: "create",
        key: "platform.organization.create",
        scope: "platform",
      },
      {
        module: "organizations",
        action: "deletePlatform",
        key: "platform.organization.delete",
        scope: "platform",
      },
    ]);
  });

  it("adds the app's reserved slugs to the data file", () => {
    const data = (slugs: readonly string[]) =>
      renderBlocks(["reserved-slugs"], {
        modules: { "reserved-slugs": { options: { slugs } } },
      }).find((file) => file.kind === "data")!.contents;

    expect(data(["pricing-beta", "team"])).toContain(
      "select value, 'app'\nfrom unnest(array['pricing-beta', 'team']) as value",
    );
    expect(data([])).not.toContain("options.slugs");
    expect(() => data(["Bad Slug"])).toThrow(/is not a slug/);
  });
});
