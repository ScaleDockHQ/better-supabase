import { cp, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { parseCommandArgs } from "../../../src/cli/command.ts";
import {
  migrationsDir,
  sqlCommand,
  type SqlArgs,
  runSql,
} from "../../../src/cli/commands/sql.ts";
import { VERSION } from "../../../src/cli/version.ts";
import {
  type BetterSupabaseConfig,
  resolveConfig,
} from "../../../src/config/index.ts";
import {
  kitPermissionKeys,
  renderKit,
  SQL_MODULES,
} from "../../../src/sql/index.ts";
import { kitLayout } from "../../../src/sql/index.ts";

const fixtures = resolve(import.meta.dirname, "../fixtures");

describe("kitLayout", () => {
  it("turns expose into grants per role and json schemas into column checks", () => {
    const config = resolveConfig(
      {
        expose: {
          "public.posts": {
            anon: ["select"],
            authenticated: ["select", "insert"],
          },
          "public.notes": ["select"],
        },
        json: {
          "public.posts.meta": { type: "Meta", schema: { type: "object" } },
          "public.posts.raw": { type: "unknown" },
        },
        plugins: { tenant: { column: "org_id" } },
      },
      "/p",
    );
    const kit = kitLayout(config, "tests/sql");
    expect(kit.grants).toEqual([
      { table: "public.posts", role: "anon", privileges: ["select"] },
      {
        table: "public.posts",
        role: "authenticated",
        privileges: ["select", "insert"],
      },
      { table: "public.notes", role: "anon", privileges: [] },
      { table: "public.notes", role: "authenticated", privileges: ["select"] },
    ]);
    expect(kit.jsonSchemas).toEqual([
      { table: "public.posts", column: "meta", schema: { type: "object" } },
    ]);
    expect(kit).toMatchObject({
      testsDir: "tests/sql",
      version: VERSION,
      tenantColumn: "org_id",
    });
    expect(kit).not.toHaveProperty("permdock");
  });
});

describe("runSql", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "better-supabase-sql-"));
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  const sql = (argv: string[], config: BetterSupabaseConfig = {}) =>
    runSql(
      resolveConfig(config, root),
      parseCommandArgs(sqlCommand, argv) as SqlArgs,
    );

  it("asks for an action and rejects unknown ones", async () => {
    const usage = "Run `better-supabase sql --help` for the actions.";
    expect(await sql([])).toEqual({
      code: 2,
      error: `Name an action.\n${usage}`,
    });
    expect(await sql(["drop"])).toEqual({
      code: 2,
      error: `Unknown sql action "drop".\n${usage}`,
    });
  });

  it("asks for module names", async () => {
    expect(await sql(["add"])).toEqual({
      code: 2,
      error:
        "Name at least one module.\nRun `better-supabase sql --help` for the actions.",
    });
    const names = Object.keys(SQL_MODULES).join(", ");
    expect(await sql(["print"])).toEqual({
      code: 2,
      error: `Name one module: ${names}`,
    });
    expect((await sql(["print", "nope"])).code).toBe(2);
  });

  it("has nothing to sync for an empty sql.kit", async () => {
    expect(await sql(["sync"])).toEqual({
      code: 0,
      output: "sql.kit is empty; nothing to sync.",
    });
  });

  it("writes the rows a schema diff skips into a data migration", async () => {
    expect(await sql(["data"])).toEqual({
      code: 0,
      output: "sql.kit is empty; nothing to write.",
    });
    const config: BetterSupabaseConfig = {
      sql: { kit: ["tenant", "rate-limit"] },
    };
    const synced = await sql(["sync"], config);
    expect(synced.output).toContain(
      "Wrote supabase/better-supabase-data/900_better_supabase_04_tenant.sql (tenant)",
    );
    expect(synced.output).toContain("run `better-supabase sql data`");
    expect((await sql(["sync"], config)).output).not.toContain("sql data");

    expect((await sql(["data", "--dry-run"], config)).output).toMatch(
      /^Would write supabase\/migrations\/\d{14}_better_supabase_kit_data\.sql$/,
    );
    const wrote = await sql(["data"], config);
    const path = wrote.output!.replace("Wrote ", "");
    expect(path).toMatch(
      /^supabase\/migrations\/\d{14}_better_supabase_kit_data\.sql$/,
    );
    const migration = await readFile(join(root, path), "utf8");
    expect(migration).toContain("values ('tenant', 2, 'managed')");
    expect(migration).toContain("values ('rate-limit',");
    expect(migration).toContain(
      "alter role authenticator set pgrst.db_pre_request",
    );
    expect(migration).not.toContain("create table");
    expect(await sql(["data"], config)).toEqual({
      code: 0,
      output: `${path} already has these rows; nothing to write.`,
    });
  });

  it("writes a pgTAP file per audited table and removes the ones it no longer writes", async () => {
    const config: BetterSupabaseConfig = { sql: { kit: ["audit"] } };
    const schemas = join(root, "supabase/schemas");
    const migrations = join(root, "supabase/migrations");
    await mkdir(schemas, { recursive: true });
    await mkdir(migrations, { recursive: true });
    await writeFile(
      join(schemas, "010_crm.sql"),
      "select better_supabase.audit('public.customers', ignore => '{updated_at}');\nselect better_supabase.audit('public.notes');\n",
    );
    await writeFile(
      join(migrations, "20260101000000_unaudit.sql"),
      "select better_supabase.unaudit('public.notes');\n",
    );
    const test =
      "supabase/tests/900_better_supabase_audit_public_customers.test.sql";
    const synced = await sql(["sync"], config);
    expect(synced.output).toContain(`Wrote ${test} (audit)`);
    expect(synced.output).not.toContain("public_notes");
    expect(await readFile(join(root, test), "utf8")).toContain(
      `'{"updated_at"}'::text[]`,
    );
    expect(await sql(["sync", "--check"], config)).toMatchObject({ code: 0 });

    await writeFile(join(schemas, "010_crm.sql"), "");
    const check = await sql(["sync", "--check"], config);
    expect(check).toMatchObject({ code: 1 });
    expect(check.error).toContain(test);
    expect((await sql(["sync", "--dry-run"], config)).output).toContain(
      `Would remove ${test}`,
    );
    expect((await sql(["sync"], config)).output).toContain(`Removed ${test}`);
    expect(await sql(["sync", "--check"], config)).toMatchObject({ code: 0 });
  });

  it("keeps data files out of pg-delta's schema folder when sql.dir is inside it", async () => {
    await mkdir(join(root, "supabase"), { recursive: true });
    await writeFile(
      join(root, "supabase/config.toml"),
      '[experimental.pgdelta]\nenabled = true\ndeclarative_schema_path = "./declarative"\n',
    );
    const synced = await sql(["sync"], {
      sql: { kit: ["tenant"], dir: "supabase/declarative/kit" },
    });
    expect(synced.output).toContain(
      "Wrote supabase/declarative/kit/900_better_supabase_04_tenant.sql (tenant)",
    );
    expect(synced.output).toContain(
      "Wrote supabase/better-supabase-data/900_better_supabase_04_tenant.sql (tenant)",
    );
  });

  it("stamps the data migration after the newest migration", async () => {
    const config: BetterSupabaseConfig = { sql: { kit: ["tenant"] } };
    await sql(["sync"], config);
    await mkdir(join(root, "supabase/migrations"), { recursive: true });
    await writeFile(
      join(root, "supabase/migrations/29991231235959_kit.sql"),
      "",
    );
    expect((await sql(["data"], config)).output).toBe(
      "Wrote supabase/migrations/30000101000000_better_supabase_kit_data.sql",
    );
  });

  it("puts migrations next to the config.toml above sql.dir", async () => {
    await mkdir(join(root, "db/supabase/schemas"), { recursive: true });
    await writeFile(join(root, "db/supabase/config.toml"), "");
    const config = resolveConfig({ sql: { dir: "db/supabase/schemas" } }, root);
    expect(migrationsDir(config)).toBe("db/supabase/migrations");
    expect(migrationsDir(resolveConfig({}, root))).toBe("supabase/migrations");
  });

  it("finds a shared stack's migrations when sql.dir is outside the project", async () => {
    const app = join(root, "apps/web");
    await mkdir(app, { recursive: true });
    await mkdir(join(root, "stack/supabase/schemas"), { recursive: true });
    await writeFile(join(root, "stack/supabase/config.toml"), "");
    const config = resolveConfig(
      { sql: { dir: "../../stack/supabase/schemas" } },
      app,
    );
    expect(migrationsDir(config)).toBe("../../stack/supabase/migrations");
  });

  it("upgrades modules installed before versioned headers", async () => {
    const config: BetterSupabaseConfig = { sql: { kit: ["tenant"] } };
    expect(await sql(["upgrade"])).toEqual({
      code: 0,
      output: "sql.kit is empty; nothing to upgrade.",
    });
    expect(await sql(["upgrade", "--check"], config)).toEqual({
      code: 0,
      output: "SQL kit modules are at their current versions.",
    });
    await sql(["sync"], config);
    const file = renderKit(
      ["tenant"],
      kitLayout(resolveConfig(config, root)),
    ).find((kit) => kit.module === "tenant" && kit.kind === "schema");
    const path = join(root, file!.path);
    const legacy = (await readFile(path, "utf8")).replace(
      /^-- @bs-kit .*\n/m,
      "",
    );
    await writeFile(path, legacy);

    const check = await sql(["upgrade", "--check"], config);
    expect(check.code).toBe(1);
    expect(check.error).toContain(
      "tenant is at version 1; the current version is 2",
    );
    expect(check.error).toContain("Run `better-supabase sql upgrade`.");

    const dry = await sql(["upgrade", "--dry-run"], config);
    expect(dry.output).toContain("tenant: version 1 to 2");
    expect(await readFile(path, "utf8")).toBe(legacy);

    const done = await sql(["upgrade"], config);
    expect(done.output).toContain(
      "Renames memberships.org_id to organization_id",
    );
    expect(done.output).toContain("Then create a migration:");
    expect(await readFile(path, "utf8")).toContain("-- @bs-kit tenant@2");
    expect((await sql(["upgrade"], config)).output).toBe(
      "SQL kit modules are at their current versions.",
    );
  });

  it("reports a stale file at the current version in upgrade --check", async () => {
    const config: BetterSupabaseConfig = { sql: { kit: ["mfa"] } };
    await sql(["sync"], config);
    const [file] = renderKit(["mfa"], kitLayout(resolveConfig(config, root)));
    await writeFile(
      join(root, file!.path),
      `${await readFile(join(root, file!.path), "utf8")}\n-- edited\n`,
    );
    const check = await sql(["upgrade", "--check"], config);
    expect(check.code).toBe(1);
    expect(check.error).toMatch(/^Out of date: .*mfa\.sql\./);
    expect(check.output).toContain("-- edited");
  });

  it("prints a rendered module with the configured claims", async () => {
    const printed = await sql(["print", "tenant"], {
      claims: { scope: "workspace" },
    });
    expect(printed.code).toBe(0);
    expect(printed.output).toContain("'workspace'");
    expect(printed.output).not.toBe(SQL_MODULES["tenant"]!.sql);
    expect(await sql(["print", "mfa"])).toEqual({
      code: 0,
      output: SQL_MODULES["mfa"]!.sql,
    });
  });

  it("prints the contract of a custom-mode module", async () => {
    const printed = await sql(["print", "tenant"], {
      kits: { tenant: { mode: "custom", schema: "app" } },
    });
    expect(printed.code).toBe(0);
    expect(printed.output).toMatch(
      /^-- kits\.tenant is in custom mode: the app writes these functions\.\n-- app\./,
    );
  });

  it("stops on an entitlements scope the manifest lacks", async () => {
    await writeFile(join(root, "permdock.config.ts"), "export default {};\n");
    await cp(
      join(fixtures, "permdock.manifest.json"),
      join(root, "permdock.manifest.json"),
    );
    await expect(
      sql(["print", "entitlements"], {
        entitlements: { permdock: { scope: "team" } },
      }),
    ).rejects.toThrow(/entitlements\.permdock\.scope is "team"/);
    expect(
      await sql(["list"], { entitlements: { permdock: { scope: "team" } } }),
    ).toMatchObject({ code: 0 });
    expect(
      await sql(["print", "audit"], {
        entitlements: { permdock: { scope: "team" } },
      }),
    ).toMatchObject({ code: 0 });
  });

  it("guards the tenant module when only PermDock's manifest is present", async () => {
    await cp(
      join(fixtures, "permdock.manifest.json"),
      join(root, "permdock.manifest.json"),
    );
    expect(await sql(["add", "tenant"])).toMatchObject({
      code: 1,
      error: expect.stringContaining(
        "permdock.manifest.json is present, so PermDock owns the access token hook",
      ),
    });
  });

  describe("the permdock access model", () => {
    const writeProject = async (
      edit: (manifest: { rls: { scopes: unknown[] } }) => void = () => {},
      permissions?: readonly { key: string; rowConditions?: boolean }[],
    ) => {
      const manifest = JSON.parse(
        await readFile(join(fixtures, "permdock.manifest.json"), "utf8"),
      );
      manifest.rls.schema = "authz";
      manifest.rls.scopes = [
        { name: "tenant", type: "uuid" },
        { name: "team", type: "uuid", within: "tenant" },
      ];
      edit(manifest);
      await writeFile(
        join(root, "permdock.manifest.json"),
        JSON.stringify(manifest),
      );
      const keys = kitPermissionKeys(
        { access: { model: "permdock" } },
        Object.keys(SQL_MODULES),
      ).map((entry) => ({ key: entry.key, rowConditions: false }));
      await writeFile(
        join(root, "permissions.catalog.json"),
        JSON.stringify({ version: 1, permissions: permissions ?? keys }),
      );
    };
    const permdock = (
      extra: BetterSupabaseConfig = {},
    ): BetterSupabaseConfig => ({
      kits: { access: { model: "permdock" } },
      ...extra,
    });

    it("renders the manifest's schema and root scope, whatever entitlements says", async () => {
      await writeProject();
      for (const config of [
        permdock(),
        permdock({ entitlements: { permdock: false } }),
      ]) {
        const printed = await sql(["print", "access"], config);
        expect(printed.output).toContain('"authz"."permitted_tenant_ids"');
        expect(printed.output).not.toContain("permitted_organization_ids");
      }
    });

    it("stops on a manifest it can't read a root scope from", async () => {
      await writeProject((manifest) => {
        manifest.rls.scopes = [
          { name: "tenant", type: "uuid" },
          { name: "workspace", type: "uuid" },
        ];
      });
      await expect(sql(["print", "access"], permdock())).rejects.toThrow(
        /no single root scope \(tenant, workspace\)/,
      );
      await expect(
        sql(["add", "organizations", "--dry-run"], permdock()),
      ).rejects.toThrow(/no single root scope/);
      expect(await sql(["list"], permdock())).toMatchObject({ code: 0 });
      expect(await sql(["print", "audit"], permdock())).toMatchObject({
        code: 0,
      });
    });

    it("stops without a PermDock project", async () => {
      await expect(sql(["print", "access"], permdock())).rejects.toThrow(
        /no PermDock project here/,
      );
    });

    it("stops on a kit permission key the catalog doesn't mark scope-only", async () => {
      await writeProject(undefined, [
        { key: "organization.update", rowConditions: true },
      ]);
      await expect(
        sql(["add", "organizations", "--dry-run"], permdock()),
      ).rejects.toThrow(
        /checks "organization\.update" \(update\) with authz\.permitted_tenant_ids, but it has row conditions[\s\S]*"organization\.delete" \(delete\).*is not in permissions\.catalog\.json/,
      );
    });
  });

  it("refuses to render entitlements for a scope id type it doesn't support", async () => {
    const manifest = JSON.parse(
      await readFile(join(fixtures, "permdock.manifest.json"), "utf8"),
    );
    manifest.rls.scopes[0].type = "numeric";
    await writeFile(join(root, "permdock.config.ts"), "export default {};\n");
    await writeFile(
      join(root, "permdock.manifest.json"),
      JSON.stringify(manifest),
    );
    await expect(sql(["print", "entitlements"])).rejects.toThrow(
      /scope "organization" the type numeric/,
    );
  });
});
