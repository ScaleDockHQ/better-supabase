import type { BetterSupabaseConfig } from "better-supabase/config";

import { resolveConfig } from "better-supabase/config";
import { cp, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { buildModel } from "../src/gen/model.ts";
import { parseCheckUnion } from "../src/gen/shared.ts";
import { run } from "../src/run.ts";
import { libraryFixture } from "./fixtures/library.ts";
import { loadFixtureSnapshot, renderFixtures } from "./fixtures/render.ts";

const fixtures = fileURLToPath(libraryFixture(""));
const cliFixtures = fileURLToPath(new URL("fixtures/", import.meta.url));

describe("parseCheckUnion", () => {
  it("reads ANY(ARRAY[...]) constraints", () => {
    expect(
      parseCheckUnion(
        "CHECK ((status = ANY (ARRAY['lead'::text, 'active'::text, 'archived'::text])))",
      ),
    ).toEqual({ column: "status", values: ["lead", "active", "archived"] });
  });

  it("reads OR chains and unescapes quotes", () => {
    expect(
      parseCheckUnion("CHECK (((kind = 'it''s'::text) OR (kind = 'b'::text)))"),
    ).toEqual({ column: "kind", values: ["it's", "b"] });
  });

  it("ignores constraints that are not unions", () => {
    expect(parseCheckUnion("CHECK ((length(name) > 2))")).toBeUndefined();
    expect(
      parseCheckUnion("CHECK (((a = 'x'::text) OR (b = 'y'::text)))"),
    ).toBeUndefined();
  });
});

describe("fixtures", () => {
  it("are in sync with the generator", async () => {
    for (const file of await renderFixtures()) {
      expect({
        path: file.path,
        contents: await readFile(file.path, "utf8"),
      }).toEqual(file);
    }
  });
});

describe("storagePaths", () => {
  const model = async (config: BetterSupabaseConfig) =>
    buildModel(await loadFixtureSnapshot(), resolveConfig(config, fixtures));
  const logo = (built: Awaited<ReturnType<typeof model>>) =>
    built.tables
      .find((table) => table.key === "customers")
      ?.columns.find((column) => column.db === "logo_path");

  it("types a column with the bucket id from a buckets key or a raw id", async () => {
    const byKey = await model({
      buckets: { customerLogos: { path: "{orgId}/{file}" } },
      storagePaths: { "public.customers.logo_path": "customerLogos" },
    });
    expect(logo(byKey)).toMatchObject({
      storage: "customer-logos",
      tsType: 'StoragePath<"customer-logos">',
    });
    expect(byKey.meta.tables["customers"]?.columns["logo_path"]?.storage).toBe(
      "customer-logos",
    );
    const byId = await model({
      storagePaths: { "customers.logo_path": "logos" },
    });
    expect(logo(byId)?.tsType).toBe('StoragePath<"logos">');
  });

  it("rejects unknown and non-text columns", async () => {
    await expect(
      model({ storagePaths: { "customers.logo_url": "logos" } }),
    ).rejects.toThrow('storagePaths["customers.logo_url"]: no such column');
    await expect(
      model({ storagePaths: { "customers.metadata": "logos" } }),
    ).rejects.toThrow("is jsonb, not a text column");
  });
});

describe("codecs", () => {
  const createdAt = async (config: BetterSupabaseConfig) =>
    buildModel(await loadFixtureSnapshot(), resolveConfig(config, fixtures))
      .tables.find((table) => table.key === "customers")
      ?.columns.find((column) => column.db === "created_at");

  it("types timestamptz columns as Temporal.Instant with the instant codec", async () => {
    expect(
      await createdAt({ codecs: { timestamptz: "instant" } }),
    ).toMatchObject({ codec: "instant", tsType: "Temporal.Instant" });
    expect(await createdAt({})).toMatchObject({
      codec: undefined,
      tsType: "string",
    });
  });
});

describe("config JSON Schema", () => {
  it("describes every config key", async () => {
    const schema = JSON.parse(
      await readFile(
        new URL(import.meta.resolve("better-supabase/schemas/config-v1.json")),
        "utf8",
      ),
    ) as { properties: Record<string, unknown> };
    const keys: Record<keyof BetterSupabaseConfig, true> = {
      $schema: true,
      source: true,
      schemas: true,
      casing: true,
      tables: true,
      output: true,
      postgrestVersion: true,
      json: true,
      codecs: true,
      generators: true,
      plugins: true,
      claims: true,
      buckets: true,
      topics: true,
      realtime: true,
      entitlements: true,
      permdock: true,
      vectorSearch: true,
      sensitive: true,
      storagePaths: true,
      expose: true,
      readSets: true,
      sql: true,
      seed: true,
      openapi: true,
      doctor: true,
    };
    expect(Object.keys(schema.properties).sort()).toEqual(
      Object.keys(keys).sort(),
    );
  });
});

describe("gen", () => {
  let dir: string;

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "better-supabase-"));
    await cp(join(fixtures, "snapshot.json"), join(dir, "snapshot.json"));
    await writeFile(
      join(dir, "better-supabase.config.json"),
      JSON.stringify({
        casing: "camel",
        output: "src/db/generated.ts",
      }),
    );
  });

  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it("writes, reports no changes, then detects drift with --check", async () => {
    const first = await run([
      "gen",
      "--snapshot",
      "snapshot.json",
      "--cwd",
      dir,
    ]);
    expect(first.code).toBe(0);
    expect(first.stdout).toContain("src/db/generated.ts");
    const generated = await readFile(join(dir, "src/db/generated.ts"), "utf8");
    expect(generated).toContain('from "better-supabase"');
    expect(generated).toContain("customerTags");

    const again = await run([
      "gen",
      "--snapshot",
      "snapshot.json",
      "--cwd",
      dir,
    ]);
    expect(again.stdout).toContain("No changes");

    const check = await run([
      "gen",
      "--check",
      "--snapshot",
      "snapshot.json",
      "--cwd",
      dir,
    ]);
    expect(check.code).toBe(0);

    await writeFile(
      join(dir, "src/db/generated.ts"),
      `${generated}// edited\n`,
    );
    const drift = await run([
      "gen",
      "--check",
      "--snapshot",
      "snapshot.json",
      "--cwd",
      dir,
    ]);
    expect(drift.code).toBe(1);
    expect(drift.stderr).toContain("out of date");
  });

  it("writes database.types.ts next to the main module", async () => {
    await run(["gen", "--snapshot", "snapshot.json", "--cwd", dir]);
    const types = await readFile(join(dir, "src/db/database.types.ts"), "utf8");
    expect(types).toContain("export type Database = {");
    expect(types).toContain('PostgrestVersion: "13"');
  });

  it("emits realtime table metadata and rejects unknown tables", async () => {
    await writeFile(
      join(dir, "better-supabase.config.json"),
      JSON.stringify({
        casing: "camel",
        output: "src/db/generated.ts",
        plugins: { tenant: true },
        realtime: { tables: ["customers", "public.tags", "organizations"] },
      }),
    );
    expect(
      (await run(["gen", "--snapshot", "snapshot.json", "--cwd", dir])).code,
    ).toBe(0);
    const generated = await readFile(join(dir, "src/db/generated.ts"), "utf8");
    expect(generated).toMatch(
      /"realtime": \{\s+"customers": \{\s+"tenant": "organizationId"\s+\},\s+"tags": \{\s+"tenant": "organizationId"\s+\},\s+"organizations": \{\}/,
    );

    await writeFile(
      join(dir, "better-supabase.config.json"),
      JSON.stringify({ realtime: { tables: ["nope"] } }),
    );
    const failed = await run([
      "gen",
      "--snapshot",
      "snapshot.json",
      "--cwd",
      dir,
    ]);
    expect(failed.code).not.toBe(0);
    expect(failed.stderr).toContain('realtime.tables: unknown table "nope"');
  });

  it("refuses bucket policies with PermDock keys that have row conditions", async () => {
    await writeFile(
      join(dir, "better-supabase.config.json"),
      JSON.stringify({
        output: "src/db/generated.ts",
        buckets: {
          docs: {
            path: "{orgId}/{file}",
            policy: {
              permdock: { read: "docs.read", write: "docs.write" },
              scope: "organization",
            },
          },
        },
      }),
    );
    await writeFile(join(dir, "permdock.config.ts"), "export default {};\n");
    await writeFile(
      join(dir, "permissions.catalog.json"),
      JSON.stringify({
        permissions: [
          { key: "docs.read", rowConditions: true },
          { key: "docs.write", rowConditions: false },
        ],
      }),
    );
    const refused = await run([
      "gen",
      "--snapshot",
      "snapshot.json",
      "--cwd",
      dir,
    ]);
    expect(refused.code).toBe(1);
    expect(refused.stderr).toContain(
      'buckets.docs: "docs.read" has row conditions in permissions.catalog.json',
    );
  });

  it("rejects an unknown introspect --format", async () => {
    const result = await run(["introspect", "--format", "nope", "--cwd", dir]);
    expect(result.code).toBe(2);
  });

  it("prints help and version", async () => {
    const help = (await run(["--help"])).stdout;
    expect(help).toContain("USAGE better-supabase [OPTIONS]");
    for (const command of ["init", "gen", "doctor", "sql"])
      expect(help).toMatch(new RegExp(`^ +${command} +\\S`, "m"));
    expect((await run(["--version"])).stdout).toMatch(/\d+\.\d+\.\d+/);
  });
});

describe("sql", () => {
  let dir: string;

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "better-supabase-"));
    await writeFile(
      join(dir, "better-supabase.config.json"),
      JSON.stringify({ sql: { kit: ["invitations"] } }),
    );
  });

  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it("adds modules with their dependencies and suggests tracking them", async () => {
    const added = await run(["sql", "add", "jobs", "pgtap", "--cwd", dir]);
    expect(added.code).toBe(0);
    expect(added.stdout).toMatch(
      /Wrote supabase\/schemas\/900_better_supabase_\d\d_jobs\.sql/,
    );
    expect(added.stdout).toContain(
      "supabase/tests/000_better_supabase_pgtap.test.sql",
    );
    expect(added.stdout).toContain("kit: ['invitations', 'jobs', 'pgtap']");

    const list = await run(["sql", "list", "--cwd", dir]);
    expect(list.stdout).toMatch(/○ jobs/);
    expect(list.stdout).toMatch(/^ {2}audit/m);
  });

  it("names kit files that schema_paths misses", async () => {
    await mkdir(join(dir, "supabase"), { recursive: true });
    await writeFile(
      join(dir, "supabase/config.toml"),
      '[db.migrations]\nschema_paths = [\n  "./schemas/010_app.sql",\n]\n',
    );
    const added = await run(["sql", "add", "audit", "--cwd", dir]);
    expect(added.stdout).toContain("no entry matches these files");
    expect(added.stdout).toMatch(
      /^ {2}"\.\/schemas\/900_better_supabase_\d\d_audit\.sql",$/m,
    );

    await writeFile(
      join(dir, "supabase/config.toml"),
      '[db.migrations]\nschema_paths = ["./schemas/9*.sql"]\n',
    );
    const listed = await run(["sql", "add", "audit", "--cwd", dir]);
    expect(listed.stdout).not.toContain("no entry matches");
  });

  it("syncs sql.kit and detects stale files with --check", async () => {
    expect((await run(["sql", "sync", "--check", "--cwd", dir])).code).toBe(1);
    const sync = await run(["sql", "sync", "--cwd", dir]);
    expect(sync.stdout).toContain("tenant");
    expect(sync.stdout).toContain("invitations");
    expect((await run(["sql", "sync", "--check", "--cwd", dir])).code).toBe(0);
    const list = await run(["sql", "list", "--cwd", dir]);
    expect(list.stdout).toMatch(/● invitations/);
    expect(list.stdout).toMatch(/○ tenant/);
  });

  it("stops before writing the tenant module next to a permdock.config.ts", async () => {
    await writeFile(join(dir, "permdock.config.ts"), "export default {};\n");
    const stopped = await run(["sql", "add", "tenant", "--cwd", dir]);
    expect(stopped.code).toBe(1);
    expect(stopped.stderr).toContain("permdock.config.ts is present");
    expect(stopped.stderr).toContain("tenant would add a second source");
    expect(stopped.stderr).toContain("permdock supabase hook generate");
    expect((await run(["sql", "list", "--cwd", dir])).stdout).toMatch(
      /^ {2}tenant/m,
    );
    expect((await run(["sql", "add", "audit", "--cwd", dir])).code).toBe(0);
    const forced = await run(["sql", "add", "tenant", "--force", "--cwd", dir]);
    expect(forced.code).toBe(0);
    expect(forced.stdout).toMatch(/900_better_supabase_\d\d_tenant\.sql/);
  });

  it("writes entitlements next to a permdock.config.ts without --force", async () => {
    await writeFile(join(dir, "permdock.config.ts"), "export default {};\n");
    const added = await run(["sql", "add", "entitlements", "--cwd", dir]);
    expect(added.code).toBe(0);
    expect(added.stdout).toMatch(/900_better_supabase_\d\d_entitlements\.sql/);
    expect(added.stdout).toContain("tenant came along as a dependency");
    expect(added.stdout).toContain("membership_claims");
  });

  it("writes entitlements on PermDock's helpers when the manifest is there", async () => {
    await writeFile(join(dir, "permdock.config.ts"), "export default {};\n");
    await cp(
      join(cliFixtures, "permdock.manifest.json"),
      join(dir, "permdock.manifest.json"),
    );
    const added = await run(["sql", "add", "entitlements", "--cwd", dir]);
    expect(added.code).toBe(0);
    expect(added.stdout).not.toContain("tenant");
    expect(added.stdout).not.toContain("came along as a dependency");
    const path =
      /supabase\/schemas\/900_better_supabase_\d\d_entitlements\.sql/.exec(
        added.stdout,
      )![0];
    expect(await readFile(join(dir, path), "utf8")).toContain(
      '"public"."member_organization_ids_for"(feature_claims.user_id)',
    );
    expect((await run(["sql", "list", "--cwd", dir])).stdout).toMatch(
      /entitlements +Active Stripe entitlements[^\n]*\.\n/,
    );

    await writeFile(
      join(dir, "better-supabase.config.json"),
      JSON.stringify({ entitlements: { permdock: { scope: "team" } } }),
    );
    const invalid = await run(["sql", "add", "entitlements", "--cwd", dir]);
    expect(invalid.code).toBe(1);
    expect(invalid.stderr).toContain(
      'entitlements.permdock.scope is "team", but permdock.manifest.json has the scopes organization, customer',
    );

    await writeFile(
      join(dir, "better-supabase.config.json"),
      JSON.stringify({ entitlements: { permdock: false } }),
    );
    const tenant = await run(["sql", "add", "entitlements", "--cwd", dir]);
    expect(tenant.stdout).toContain("tenant came along as a dependency");
  });

  it("prints a module and rejects unknown ones", async () => {
    const print = await run(["sql", "print", "audit", "--cwd", dir]);
    expect(print.stdout).toContain("better_supabase.audit_log");
    expect((await run(["sql", "add", "nope", "--cwd", dir])).code).toBe(2);
    expect(
      (await run(["sql", "add", "--dry-run", "audit", "--cwd", dir])).stdout,
    ).toContain("Would write");
  });
});
