import { toStandardJsonSchema } from "@valibot/to-json-schema";
import * as v from "valibot";
import { describe, expect, it } from "vitest";

import { resolveConfig, resolveJsonSchema } from "../../src/config/index.ts";
import { moduleLayout } from "../../src/sql/layout.ts";
import {
  modulePermissionKeys,
  renderModules,
  resolveModules,
  sameModuleFile,
  SQL_MODULES,
} from "../../src/sql/registry.ts";

describe("resolveModules", () => {
  it("adds dependencies and keeps registry order", () => {
    expect(
      resolveModules(["invitations", "updated-at"]).map(
        (module) => module.name,
      ),
    ).toEqual(["updated-at", "tenant", "invitations", "access"]);
  });

  it("deduplicates and rejects unknown modules", () => {
    expect(resolveModules(["tenant", "tenant", "invitations"])).toHaveLength(4);
    expect(() => resolveModules(["nope"])).toThrow(/Unknown SQL module "nope"/);
  });
});

describe("renderModules", () => {
  it("numbers files by registry position so paths stay stable", () => {
    const all = renderModules(Object.keys(SQL_MODULES));
    const jobs = renderModules(["jobs"]);
    expect(jobs[0]!.path).toBe(
      all.find((file) => file.module === "jobs")!.path,
    );
    expect(jobs[0]!.path).toMatch(
      /^supabase\/schemas\/900_better_supabase_\d\d_jobs\.sql$/,
    );
  });

  it("writes pgtap to the tests directory with a managed header", () => {
    const [file] = renderModules(["pgtap"], {
      testsDir: "db/tests/",
      version: "1.2.3",
    });
    expect(file!.path).toBe("db/tests/000_better_supabase_pgtap.test.sql");
    expect(file!.contents).toMatch(
      /^-- better-supabase module: pgtap \(1\.2\.3\)\n/,
    );
    expect(file!.contents).toContain("Managed by `better-supabase sql add`");
    expect(file!.contents.endsWith("\n")).toBe(true);
  });

  it("honours dir and prefix", () => {
    const [file] = renderModules(["audit"], { dir: "schemas/", prefix: "zz" });
    expect(file!.path).toMatch(/^schemas\/zz_\d\d_audit\.sql$/);
  });

  it("renders the audit log's tenant column from config and keys rows by their primary key", () => {
    const [plain] = renderModules(["audit"]);
    expect(plain!.contents).toContain(
      "row_data ->> coalesce(entry.tenant_column, 'organization_id')",
    );
    const [file] = renderModules(["audit"], { tenantColumn: "team_id" });
    expect(file!.contents).toContain(
      "row_data ->> coalesce(entry.tenant_column, 'team_id')",
    );
    expect(file!.contents).not.toContain("'organization_id'");
    expect(file!.contents).toContain("i.indisprimary");
    expect(file!.contents).not.toContain("row_data ->> 'id'");
  });

  it("keeps every schema module in the better_supabase schema", () => {
    for (const module of Object.values(SQL_MODULES)) {
      if (module.target !== "schema") continue;
      const functions = [
        ...module.sql.matchAll(/create or replace function ([\w.]+)\(/g),
      ];
      for (const [, name] of functions)
        expect(name).toMatch(/^better_supabase\./);
      expect(module.sql).not.toMatch(/create table (?!if not exists)/);
    }
  });

  it("keeps statements a schema diff skips out of the schema files", () => {
    const layouts = [
      {},
      { modules: { jobs: { options: { backend: "table" } } } },
    ];
    for (const layout of layouts) {
      const files = renderModules(Object.keys(SQL_MODULES), layout);
      for (const file of files.filter((entry) => entry.kind === "schema")) {
        expect(file.contents).not.toMatch(
          /^(insert|update|delete|select|truncate|notify|alter role|call)\b/im,
        );
      }
      for (const file of files.filter((entry) => entry.kind === "data")) {
        expect(file.path).toMatch(/\/better-supabase-data\/[^/]+\.sql$/);
        expect(file.contents).not.toMatch(/^(create|drop|alter table)\b/im);
      }
    }
  });
});

describe("sameModuleFile", () => {
  it("ignores the version in the header only", () => {
    const [file] = renderModules(["updated-at"], { version: "1.2.0" });
    const older = file!.contents.replace(" (1.2.0)", " (0.0.1)");
    expect(older).not.toBe(file!.contents);
    expect(sameModuleFile(older, file!.contents)).toBe(true);
    expect(sameModuleFile(`${file!.contents}-- edited\n`, file!.contents)).toBe(
      false,
    );
    expect(sameModuleFile(undefined, file!.contents)).toBe(false);
  });

  it("registers realtime tables with the tenant column", () => {
    const [file] = renderModules(["realtime-tables"], {
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
    expect(renderModules(["realtime-tables"])[0]!.contents).not.toContain(
      "config.realtime.tables",
    );
  });

  it("adds pg_jsonschema checks for json config schemas", () => {
    const schema = resolveJsonSchema(
      toStandardJsonSchema(v.object({ source: v.string() })),
    );
    expect(schema).toMatchObject({
      type: "object",
      required: ["source"],
    });
    expect(resolveJsonSchema({ type: "array" })).toEqual({ type: "array" });
    const [file] = renderModules(["jsonb-schemas"], {
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
      `alter table "public"."customers" add constraint "bs_json_metadata"\n  check (extensions.jsonb_matches_schema('{"type":"object"}'::json, "metadata")) not valid;\nalter table "public"."customers" validate constraint "bs_json_metadata";`,
    );
    expect(file!.contents).toContain(
      'alter table "billing"."invoices" drop constraint if exists "bs_json_lines";',
    );
  });

  it("writes Data API grants from the expose config", () => {
    const config = resolveConfig(
      {
        expose: {
          customers: ["select", "insert", "update", "delete"],
          "billing.invoices": { anon: ["select"], authenticated: ["select"] },
        },
      },
      "/project",
    );
    const [file] = renderModules(["grants"], moduleLayout(config));
    expect(file!.path).toBe(
      "supabase/schemas/900_better_supabase_13_grants.sql",
    );
    expect(file!.contents).toContain(
      [
        "-- config.expose",
        'grant select, insert, update, delete on table "public"."customers" to authenticated;',
        'grant select on table "billing"."invoices" to anon;',
        'grant select on table "billing"."invoices" to authenticated;',
      ].join("\n"),
    );
    expect(renderModules(["grants"])[0]!.contents).not.toContain(
      "config.expose",
    );
  });

  it("writes a search function per vectorSearch table", () => {
    const config = resolveConfig(
      {
        vectorSearch: {
          chunks: "embedding",
          "docs.pages": { column: "vec", distance: "inner_product" },
        },
      },
      "/project",
    );
    const [file] = renderModules(["vector-search"], moduleLayout(config));
    expect(file!.path).toBe(
      "supabase/schemas/900_better_supabase_18_vector_search.sql",
    );
    expect(file!.contents).toContain(
      [
        'create or replace function "public"."search_chunks"(query extensions.vector, k integer default 10)',
        'returns setof "public"."chunks"',
        "language sql",
        "stable",
        "security invoker",
        "set search_path = ''",
        "set hnsw.iterative_scan = 'strict_order'",
      ].join("\n"),
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
    expect(renderModules(["vector-search"])[0]!.contents).not.toContain(
      "config.vectorSearch",
    );
  });
});

describe("entitlements in PermDock mode", () => {
  const permdock = {
    schema: "authz",
    scope: "organization",
    idType: "uuid",
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
      resolveModules(["entitlements"]).map((module) => module.name),
    ).toEqual(["updated-at", "tenant", "entitlements"]);
    expect(
      resolveModules(["entitlements"], { permdock }).map(
        (module) => module.name,
      ),
    ).toEqual(["entitlements"]);
  });

  it("reads member_<scope>_ids and member_<scope>_ids_for", () => {
    const [file] = renderModules(["entitlements"], { permdock, entitlements });
    const sql = file!.contents;
    expect(sql).toContain(
      'select tenant in (select "authz"."member_organization_ids"())',
    );
    expect(sql).toContain(
      'from "authz"."member_organization_ids_for"(feature_claims.user_id) as t(id)',
    );
    expect(sql).toContain("features: 'better_supabase.feature_claims'");
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
      const file = renderModules(["entitlements"], {
        permdock: { ...permdock, idType },
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
      ])
        expect(sql).toContain(signature);
      expect(sql).toContain(`returns setof ${idType}`);
      expect(sql).toContain("feature_claims(user_id uuid)");
      expect(
        sql.match(/\(tenant (\w+)/g)?.map((match) => match.slice(8)),
      ).toEqual([idType, idType, idType]);
      expect(sql).toMatchSnapshot();
    },
  );

  it("keeps the tenant-mode functions without PermDock", () => {
    const file = renderModules(["entitlements"], { entitlements }).find(
      (entry) => entry.module === "entitlements",
    );
    expect(file!.contents).toContain(
      "select better_supabase.has_organization_role(tenant)",
    );
    expect(file!.contents).toContain('from "better_supabase"."memberships" m');
  });

  it("needs a customer column unless the managed organizations module adds one", () => {
    expect(() => renderModules(["entitlements"])).toThrow(
      "The entitlements module needs entitlements.customer",
    );
    expect(() =>
      renderModules(["entitlements", "organizations"], {
        modules: { organizations: { mode: "adopt" } },
      }),
    ).toThrow("The entitlements module needs entitlements.customer");
    const files = renderModules(["entitlements", "organizations"]);
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
      renderModules(["entitlements"], {
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
      renderModules(["organizations"]).find(
        (file) => file.module === "organizations",
      )!.contents,
    ).not.toContain("stripe_customer_id");
  });
});

describe("modulePermissionKeys", () => {
  it("lists every key the installed modules check, with its scope", () => {
    const keys = modulePermissionKeys({}, [
      "organizations",
      "support-sessions",
    ]);
    expect(keys).toContainEqual({
      module: "organizations",
      action: "update",
      key: "organization.update",
      scope: "tenant",
    });
    expect(keys).toContainEqual({
      module: "support-sessions",
      action: "start",
      key: "support.start",
      scope: "platform",
    });
    expect(keys.map((entry) => entry.module)).not.toContain("notifications");
  });

  it("applies sql.modules.<module>.permissions and skips custom modules", () => {
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
    expect(platform({ access: { model: "permdock" } })).toBe(false);
    expect(platform({ access: { model: "catalog" } })).toBe(true);
  });
});
