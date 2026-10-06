import { cp, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { BetterSupabaseConfig } from "../../src/config/index.ts";

import { buildModel } from "../../src/cli/gen/model.ts";
import {
  parseCheckNotNull,
  parseCheckUnion,
} from "../../src/cli/gen/shared.ts";
import { run } from "../../src/cli/run.ts";
import { resolveConfig } from "../../src/config/index.ts";
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

describe("parseCheckNotNull", () => {
  it.each<[string, string, string[]]>([
    ["one column", "CHECK ((slug IS NOT NULL))", ["slug"]],
    [
      "a top-level AND",
      "CHECK (((a IS NOT NULL) AND (b IS NOT NULL) AND (c > 0)))",
      ["a", "b"],
    ],
    ["a quoted name", 'CHECK (("Weird ""x""" IS NOT NULL))', ['Weird "x"']],
    ["an OR", "CHECK (((a IS NOT NULL) OR (b IS NOT NULL)))", []],
    ["a NOT", "CHECK ((NOT (a IS NOT NULL)))", []],
    [
      "an AND under an OR",
      "CHECK ((((a IS NOT NULL) AND (b IS NOT NULL)) OR (c IS NULL)))",
      [],
    ],
    ["a CASE", "CHECK ((CASE WHEN a THEN (b IS NOT NULL) ELSE true END))", []],
    ["a comparison", "CHECK (((a IS NOT NULL) = true))", []],
    ["a NOT VALID constraint", "CHECK ((slug IS NOT NULL)) NOT VALID", []],
    ["a string with AND in it", "CHECK ((note <> 'x AND y'))", []],
    ["something else", "UNIQUE (a)", []],
  ])("reads %s", (_name, definition, columns) => {
    expect(parseCheckNotNull(definition)).toEqual(columns);
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

describe("relations", () => {
  it("names a composite tenant foreign key after its own column", async () => {
    const model = buildModel(
      await loadFixtureSnapshot(),
      resolveConfig({ casing: "camel" }, fixtures),
    );
    const relation = (table: string, name: string) =>
      model.tables
        .find((entry) => entry.key === table)
        ?.relations.find((entry) => entry.name === name)?.meta;
    expect(relation("customers", "primaryContact")).toMatchObject({
      table: "contacts",
      columns: ["primaryContactId", "organizationId"],
      references: ["id", "organizationId"],
    });
    expect(relation("locations", "customer")).toMatchObject({
      columns: ["customerId", "organizationId"],
    });
    expect(relation("customerTags", "tag")).toMatchObject({
      columns: ["tagId", "organizationId"],
    });
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

describe("function results", () => {
  const model = async (config: BetterSupabaseConfig) =>
    buildModel(await loadFixtureSnapshot(), resolveConfig(config, fixtures));
  const fn = (built: Awaited<ReturnType<typeof model>>, name: string) =>
    built.functions.find((entry) => entry.key === name);

  it("types table rows with the model row and records in the casing", async () => {
    const camel = await model({ casing: "camel" });
    expect(fn(camel, "customers_by_status")).toMatchObject({
      returns: `(Models["customers"]['Row'])[]`,
      meta: { result: { table: "customers" } },
    });
    expect(fn(camel, "customer_note_counts")).toMatchObject({
      returns:
        '{ "customerId": string; "lastNoteAt": string; "noteCount": number }[]',
      meta: {
        result: {
          columns: [
            { db: "customer_id", name: "customerId" },
            { db: "last_note_at", name: "lastNoteAt" },
            { db: "note_count", name: "noteCount" },
          ],
        },
      },
    });
  });

  it("records codecs and leaves results decoding wouldn't change out of the metadata", async () => {
    const snake = await model({ casing: "snake" });
    expect(fn(snake, "customers_by_status")?.meta.result).toBeUndefined();
    expect(fn(snake, "customer_note_counts")?.meta.result).toBeUndefined();
    const coded = await model({
      casing: "snake",
      codecs: { timestamptz: "instant", int8: "bigint" },
    });
    expect(fn(coded, "customer_note_counts")).toMatchObject({
      returns:
        '{ "customer_id": string; "last_note_at": Temporal.Instant; "note_count": bigint }[]',
      meta: {
        result: {
          columns: [
            { db: "customer_id" },
            { db: "last_note_at", codec: "instant" },
            { db: "note_count", codec: "bigint" },
          ],
        },
      },
    });
    expect(fn(coded, "customers_by_status")?.meta.result).toEqual({
      table: "customers",
    });
  });
});

describe("CHECK not null", () => {
  it("narrows the column in the row, insert and update shapes", async () => {
    const fixture = await loadFixtureSnapshot();
    const snapshot = {
      ...fixture,
      extras: {
        ...fixture.extras,
        tables: fixture.extras.tables.map((table) =>
          table.schema === "public" && table.name === "customers"
            ? {
                ...table,
                checks: [
                  ...table.checks,
                  {
                    name: "customers_kvk_present",
                    definition: "CHECK ((kvk IS NOT NULL))",
                  },
                  {
                    name: "customers_contact_or_logo",
                    definition:
                      "CHECK (((primary_contact_id IS NOT NULL) OR (logo_path IS NOT NULL)))",
                  },
                ],
              }
            : table,
        ),
      },
    };
    const model = buildModel(snapshot, resolveConfig({}, fixtures));
    const column = (name: string) =>
      model.tables
        .find((table) => table.key === "customers")
        ?.columns.find((entry) => entry.db === name);
    expect(column("kvk")).toMatchObject({ nullable: false, optional: false });
    expect(column("primary_contact_id")).toMatchObject({
      nullable: true,
      optional: true,
    });
    expect(model.meta.tables["customers"]?.columns["kvk"]?.nullable).toBe(
      false,
    );
  });
});

describe("function arguments", () => {
  it("accept null, and stay optional when they have a default", async () => {
    const snake = (await renderFixtures()).find((file) =>
      file.path.endsWith("/generated.ts"),
    );
    expect(snake?.contents).toContain("p_limit?: number | null;");
    expect(snake?.contents).toContain("p_status: string | null;");
  });
});

describe("plugin flags", () => {
  it("rejects a soft-delete column that is not a timestamp", async () => {
    const config = resolveConfig(
      { plugins: { softDelete: { column: "name" } } },
      fixtures,
    );
    const snapshot = await loadFixtureSnapshot();
    expect(() => buildModel(snapshot, config)).toThrow(
      "plugins.softDelete.column: public.customers.name is text, but softDelete() writes a timestamp",
    );
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
      kits: true,
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
    const generated = await readFile(
      join(dir, "src/db/generated.meta.js"),
      "utf8",
    );
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
        version: 1,
        permissions: [
          { key: "docs.read", rowConditions: true },
          { key: "docs.write" },
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
    expect(refused.stderr).toContain(
      'buckets.docs: "docs.write" has no rowConditions flag in permissions.catalog.json',
    );
  });

  it("refuses PermDock bucket policies when there is no catalog", async () => {
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
    const refused = await run([
      "gen",
      "--snapshot",
      "snapshot.json",
      "--cwd",
      dir,
    ]);
    expect(refused.code).toBe(1);
    expect(refused.stderr).toContain(
      "buckets.docs: there is no permissions.catalog.json, so whether the keys have row conditions is unknown",
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
    expect(listed.stdout).toContain(
      "Then create a migration: supabase db diff -f better_supabase_kit",
    );
  });

  it("names the pg-delta sync and skips the schema_paths note under pg-delta", async () => {
    await mkdir(join(dir, "supabase"), { recursive: true });
    await writeFile(
      join(dir, "supabase/config.toml"),
      '[db.migrations]\nschema_paths = ["./schemas/010_app.sql"]\n\n[experimental.pgdelta]\nenabled = true\n',
    );
    const added = await run(["sql", "add", "audit", "--cwd", dir]);
    expect(added.stdout).not.toContain("no entry matches");
    expect(added.stdout).toContain(
      "Then create a migration: supabase db schema declarative sync -f better_supabase_kit",
    );
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

  it("refuses entitlements next to a permdock.config.ts without a manifest", async () => {
    await writeFile(join(dir, "permdock.config.ts"), "export default {};\n");
    const refused = await run(["sql", "add", "entitlements", "--cwd", dir]);
    expect(refused.code).toBe(1);
    expect(refused.stderr).toContain(
      "permdock.config.ts is a PermDock project, but there is no permdock.manifest.json",
    );
    await writeFile(
      join(dir, "better-supabase.config.json"),
      JSON.stringify({
        entitlements: {
          customer: "organizations.stripe_customer_id",
          permdock: false,
        },
      }),
    );
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
    await writeFile(
      join(dir, "better-supabase.config.json"),
      JSON.stringify({
        entitlements: { customer: "organizations.stripe_customer_id" },
      }),
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
      JSON.stringify({
        entitlements: {
          customer: "organizations.stripe_customer_id",
          permdock: { scope: "team" },
        },
      }),
    );
    const invalid = await run(["sql", "add", "entitlements", "--cwd", dir]);
    expect(invalid.code).toBe(1);
    expect(invalid.stderr).toContain(
      'entitlements.permdock.scope is "team", but permdock.manifest.json has the scopes organization, customer',
    );

    await writeFile(
      join(dir, "better-supabase.config.json"),
      JSON.stringify({
        entitlements: {
          customer: "organizations.stripe_customer_id",
          permdock: false,
        },
      }),
    );
    const tenant = await run(["sql", "add", "entitlements", "--cwd", dir]);
    expect(tenant.stdout).toContain("tenant came along as a dependency");
  });

  it("prints a module and rejects unknown ones", async () => {
    const print = await run(["sql", "print", "audit", "--cwd", dir]);
    expect(print.stdout).toContain('"better_supabase"."audit_events"');
    expect((await run(["sql", "add", "nope", "--cwd", dir])).code).toBe(2);
    expect(
      (await run(["sql", "add", "--dry-run", "audit", "--cwd", dir])).stdout,
    ).toContain("Would write");
  });
});
