import { toStandardJsonSchema } from "@valibot/to-json-schema";
import * as v from "valibot";
import { describe, expect, it } from "vitest";

import { resolveConfig, resolveJsonSchema } from "../../src/config/index.ts";
import {
  renderKit,
  resolveModules,
  sameKitFile,
  SQL_MODULES,
} from "../../src/sql/kit.ts";
import { kitLayout } from "../../src/sql/layout.ts";

describe("resolveModules", () => {
  it("adds dependencies and keeps registry order", () => {
    expect(
      resolveModules(["invitations", "updated-at"]).map(
        (module) => module.name,
      ),
    ).toEqual(["updated-at", "tenant", "invitations"]);
  });

  it("deduplicates and rejects unknown modules", () => {
    expect(resolveModules(["tenant", "tenant", "invitations"])).toHaveLength(2);
    expect(() => resolveModules(["nope"])).toThrow(
      /Unknown SQL kit module "nope"/,
    );
  });
});

describe("renderKit", () => {
  it("numbers files by registry position so paths stay stable", () => {
    const all = renderKit(Object.keys(SQL_MODULES));
    const jobs = renderKit(["jobs"]);
    expect(jobs[0]!.path).toBe(
      all.find((file) => file.module === "jobs")!.path,
    );
    expect(jobs[0]!.path).toMatch(
      /^supabase\/schemas\/900_better_supabase_\d\d_jobs\.sql$/,
    );
  });

  it("writes pgtap to the tests directory with a managed header", () => {
    const [file] = renderKit(["pgtap"], {
      testsDir: "db/tests/",
      version: "1.2.3",
    });
    expect(file!.path).toBe("db/tests/000_better_supabase_pgtap.test.sql");
    expect(file!.contents).toMatch(
      /^-- better-supabase SQL kit: pgtap \(1\.2\.3\)\n/,
    );
    expect(file!.contents).toContain("Managed by `better-supabase sql add`");
    expect(file!.contents.endsWith("\n")).toBe(true);
  });

  it("honours dir and prefix", () => {
    const [file] = renderKit(["audit"], { dir: "schemas/", prefix: "zz" });
    expect(file!.path).toMatch(/^schemas\/zz_\d\d_audit\.sql$/);
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
});

describe("sameKitFile", () => {
  it("ignores the version in the header only", () => {
    const [file] = renderKit(["updated-at"], { version: "1.2.0" });
    const older = file!.contents.replace(" (1.2.0)", " (0.0.1)");
    expect(older).not.toBe(file!.contents);
    expect(sameKitFile(older, file!.contents)).toBe(true);
    expect(sameKitFile(`${file!.contents}-- edited\n`, file!.contents)).toBe(
      false,
    );
    expect(sameKitFile(undefined, file!.contents)).toBe(false);
  });

  it("registers realtime tables with the tenant column", () => {
    const [file] = renderKit(["realtime-tables"], {
      realtimeTables: ["customers", "billing.invoices"],
      tenantColumn: "organization_id",
    });
    expect(file!.contents).toContain(
      "select better_supabase.track_realtime('public.customers', 'organization_id');",
    );
    expect(file!.contents).toContain(
      "select better_supabase.track_realtime('billing.invoices', 'organization_id');",
    );
    expect(renderKit(["realtime-tables"])[0]!.contents).not.toContain(
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
    const [file] = renderKit(["jsonb-schemas"], {
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
      `alter table "public"."customers" add constraint "bs_json_metadata"\n  check (extensions.jsonb_matches_schema('{"type":"object"}'::json, "metadata"));`,
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
    const [file] = renderKit(["grants"], kitLayout(config));
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
    expect(renderKit(["grants"])[0]!.contents).not.toContain("config.expose");
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
    const [file] = renderKit(["vector-search"], kitLayout(config));
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
    expect(renderKit(["vector-search"])[0]!.contents).not.toContain(
      "config.vectorSearch",
    );
  });
});

describe("entitlements in PermDock mode", () => {
  const permdock = {
    schema: "authz",
    scope: "organization",
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

  it("drops the tenant dependency", () => {
    expect(
      resolveModules(["entitlements"]).map((module) => module.name),
    ).toEqual(["tenant", "entitlements"]);
    expect(
      resolveModules(["entitlements"], { permdock }).map(
        (module) => module.name,
      ),
    ).toEqual(["entitlements"]);
  });

  it("reads member_<scope>_ids and member_<scope>_ids_for", () => {
    const [file] = renderKit(["entitlements"], { permdock });
    const sql = file!.contents;
    expect(sql).toContain(
      'select tenant in (select "authz"."member_organization_ids"())',
    );
    expect(sql).toContain(
      'from "authz"."member_organization_ids_for"(feature_claims.user_id) as t(id)',
    );
    expect(sql).toContain("features: 'better_supabase.feature_claims'");
    expect(sql).not.toContain("has_org_role");
    expect(sql).not.toContain("better_supabase.memberships");
    // entitlement_members reads the organization-scoped source only.
    expect(sql).toContain(
      `from "public"."memberships" m\n  where m."scope_id"::text in (select t::text from better_supabase.stripe_customer_tenants(customer) t)\n    and m."scope"::text = 'organization'`,
    );
    expect(sql).not.toContain('"public"."contacts"');
  });

  it("keeps the tenant-mode functions without PermDock", () => {
    const file = renderKit(["entitlements"]).find(
      (entry) => entry.module === "entitlements",
    );
    expect(file!.contents).toContain(
      "select better_supabase.has_org_role(tenant)",
    );
    expect(file!.contents).toContain("from better_supabase.memberships m");
  });
});
