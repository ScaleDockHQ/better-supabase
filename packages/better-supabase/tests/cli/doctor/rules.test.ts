import { parseArgs } from "citty";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { AdvisorSource, Lint } from "../../../src/cli/doctor/advisors.ts";
import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";
import type {
  Catalog,
  CatalogTable,
  Snapshot,
} from "../../../src/cli/introspect/types.ts";
import type { BetterSupabaseConfig } from "../../../src/config/index.ts";

import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import { runSql } from "../../../src/cli/commands/sql.ts";
import { RULES, runRules } from "../../../src/cli/doctor/rules.ts";
import { renderFiles } from "../../../src/cli/gen/render.ts";
import { toCatalog } from "../../../src/cli/introspect/catalog.ts";
import { fromCatalog } from "../../../src/cli/introspect/from-catalog.ts";
import { SQL_ARGS } from "../../../src/cli/sql/args.ts";
import { parseToml } from "../../../src/cli/supabase-toml.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { renderBlocks, moduleLayout } from "../../../src/sql/index.ts";
import { stubProvider } from "../../fixtures/authorization-provider.ts";
import { snapshotFixture as fixture } from "../fixtures/library.ts";

const base = await parseSnapshot(fixture);

type Mutable<T> = { -readonly [K in keyof T]: T[K] };

function snapshot(
  change: (tables: Mutable<CatalogTable>[], catalog: Mutable<Catalog>) => void,
): Snapshot {
  const copy = structuredClone(toCatalog(base)) as Mutable<Catalog>;
  change(copy.tables as Mutable<CatalogTable>[], copy);

  return fromCatalog(copy);
}

const table = (tables: Mutable<CatalogTable>[], name: string) =>
  tables.find((entry) => entry.schema === "public" && entry.name === name) ??
  tables.find((entry) => entry.name === name)!;

const toml = (text: string): DoctorContext["configToml"] => ({
  path: "supabase/config.toml",
  dir: "supabase",
  text,
  document: parseToml(text),
  parser: "smol-toml",
});

function context(
  snap: Snapshot = base,
  extra: Partial<DoctorContext> = {},
  config: BetterSupabaseConfig = {},
): DoctorContext {
  return {
    config: resolveConfig(config, "/project"),
    snapshot: snap,
    configToml: undefined,
    envFiles: [],
    gitignore: "",
    sources: [],
    ...extra,
  };
}

const run = (code: string, ctx: DoctorContext) =>
  runRules(
    ctx,
    RULES.filter((rule) => rule.code === code),
  );

const lint = (overrides: Partial<Lint>): Lint => ({
  name: "function_search_path_mutable",
  title: "Function Search Path Mutable",
  level: "WARN",
  facing: "EXTERNAL",
  categories: ["SECURITY"],
  description: "",
  detail: "Function \\`public.f\\` has a mutable search_path",
  remediation: "https://supabase.com/docs/lint",
  metadata: { schema: "public", name: "f", type: "function" },
  cache_key: "key_f",
  ...overrides,
});

const advisors = (lints: Lint[]): AdvisorSource => ({
  describe: "test",
  lints: () => Promise.resolve(lints),
});

describe("advisor findings (BS100, BS200)", () => {
  it("maps lint objects and levels", async () => {
    const findings = await run(
      "BS100",
      context(base, {
        advisors: advisors([
          lint({}),
          lint({
            name: "security_definer_view",
            level: "ERROR",
            metadata: { schema: "public", name: "v", type: "view" },
            cache_key: "key_v",
          }),
          lint({
            name: "extension_in_public",
            // SAFETY: splinter can report a level the map does not know.
            level: "FATAL" as Lint["level"],
            metadata: { schema: "public", name: "vector", type: "extension" },
            cache_key: "key_ext",
          }),
          lint({ metadata: { name: 1 }, cache_key: "key_odd" }),
        ]),
      }),
    );

    expect(findings).toEqual([
      expect.objectContaining({
        severity: "warning",
        message:
          "Function `public.f` has a mutable search_path [function_search_path_mutable]",
        target: "public.f",
        object: { kind: "function", schema: "public", name: "f" },
      }),
      expect.objectContaining({
        severity: "error",
        object: { kind: "table", schema: "public", name: "v" },
      }),
      expect.objectContaining({ severity: "warning", target: "key_ext" }),
      expect.objectContaining({ target: "key_odd" }),
    ]);
    expect(findings[2]).not.toHaveProperty("object");
  });

  it("reports a non-Error failure", async () => {
    const failing: AdvisorSource = {
      describe: "splinter",
      lints: () => Promise.reject("offline"),
    };

    expect(
      await run("BS200", context(base, { advisors: failing })),
    ).toMatchObject([
      { message: "The performance advisor could not run (splinter): offline" },
    ]);
    expect(await run("BS200", context(base))).toEqual([]);
  });

  it("reports every splinter overlap lint next to BS207", async () => {
    const overlap = (metadata: Lint["metadata"]) =>
      lint({
        name: "multiple_permissive_policies",
        categories: ["PERFORMANCE"],
        metadata,
      });

    const findings = await runRules(
      context(base, {
        advisors: advisors([
          overlap(null),
          overlap({ schema: "public", name: "nowhere", type: "table" }),
          overlap({ schema: "public", name: "notes", type: "table" }),
        ]),
      }),
      RULES.filter((rule) => ["BS200", "BS207"].includes(rule.code)),
    );

    expect(findings.map((finding) => finding.code)).toEqual([
      "BS200",
      "BS200",
      "BS200",
    ]);
  });
});

describe("BS103", () => {
  it("names public when a policy lists no roles", async () => {
    const snap = snapshot((tables) => {
      table(tables, "tags").policies = [
        {
          name: "open",
          command: "delete",
          roles: [],
          permissive: true,
          using: "(true)",
          check: null,
        },
      ];
    });

    expect(await run("BS103", context(snap))).toMatchObject([
      {
        message:
          'Policy "open" on public.tags allows delete for public with `true`.',
      },
    ]);
  });
});

describe("BS107 without the tenant plugin", () => {
  const policy = (
    name: string,
    command: "select" | "insert",
    using: string | null,
    extra: { check?: string; functions?: string[]; roles?: string[] } = {},
  ) => ({
    name,
    command,
    roles: extra.roles ?? ["authenticated"],
    permissive: true,
    using,
    check: extra.check ?? null,
    ...(extra.functions ? { functions: extra.functions } : {}),
  });

  it("finds tenant tables by their policies and skips tenant roots", async () => {
    const snap = snapshot((tables) => {
      table(tables, "tags").policies = [
        policy("tags_read", "select", null, { check: "org_id = 1" }),
      ];
      table(tables, "notes").policies = [
        policy("notes_read", "select", "true", {
          functions: ["private.is_member"],
        }),
      ];
      table(tables, "contacts").policies = [
        policy("contacts_read", "select", "true"),
      ];
      table(tables, "locations").policies = [
        policy("locations_read", "select", "is_member(organization)", {
          roles: ["anon"],
        }),
      ];
      table(tables, "customers").rls = false;
      table(tables, "organizations").policies = [
        policy("organizations_read", "select", "is_member(id)"),
      ];
    });

    const findings = await run("BS107", context(snap));
    expect(findings.map((finding) => finding.target)).toEqual([
      "public.notes",
      "public.tags",
    ]);
    expect(findings[1]!.message).toContain("no insert, update, delete policy");

    const excluded = await run(
      "BS107",
      context(snap, {}, { gen: { tables: { tags: { exclude: true } } } }),
    );

    expect(excluded.map((finding) => finding.target)).toEqual(["public.notes"]);
  });

  it("counts a restrictive using (false) policy as covering the command", async () => {
    const snap = snapshot((tables) => {
      table(tables, "notes").policies = [
        policy("notes_read", "select", "is_member(organization_id)"),
        {
          name: "notes_no_write",
          command: "all",
          roles: ["authenticated"],
          permissive: false,
          using: "false",
          check: null,
        },
      ];
    });

    expect(await run("BS107", context(snap))).toEqual([]);
  });
});

describe("BS204, BS210, BS301", () => {
  it("skips the tenant index check without the tenant plugin", async () => {
    expect(await run("BS204", context())).toEqual([]);
  });

  it("accepts aggregates enabled with on, and passes code without them", async () => {
    const withSetting = (value: string): Snapshot => ({
      ...base,
      extras: {
        ...base.extras,
        roleSettings: {
          authenticator: { "pgrst.db_aggregates_enabled": value },
        },
      },
    });

    const sources = [{ path: "a.ts", text: "db.x.aggregate({})" }];
    expect(await run("BS210", context(withSetting("on"), { sources }))).toEqual(
      [],
    );
    expect(
      await run(
        "BS210",
        context(withSetting("off"), {
          sources: [{ path: "b.ts", text: "db.x.findMany()" }],
        }),
      ),
    ).toEqual([]);
  });

  it("ignores policies without a using clause for soft delete", async () => {
    const snap = snapshot((tables) => {
      table(tables, "customers").policies = [
        {
          name: "insert_only",
          command: "all",
          roles: ["authenticated"],
          permissive: true,
          using: null,
          check: "true",
        },
      ];
    });

    expect(
      await run(
        "BS301",
        context(
          snap,
          {},
          { plugins: { softDelete: { column: "archived_at" } } },
        ),
      ),
    ).toEqual([]);
  });
});

describe("BS302 bucket drift in config.toml", () => {
  const config: BetterSupabaseConfig = {
    database: {
      buckets: {
        docs: {
          path: "{organizationId}/{file}",
          public: false,
          fileSizeLimit: "1KiB",
          allowedMimeTypes: ["application/pdf"],
        },
      },
    },
  };

  it("reads numeric sizes and missing mime lists", async () => {
    const findings = await run(
      "BS302",
      context(
        base,
        {
          configToml: toml(
            "[storage.buckets.docs]\npublic = false\nfile_size_limit = 2048\n",
          ),
        },
        config,
      ),
    );

    const inToml = findings.filter(
      (finding) => finding.target === "[storage.buckets.docs]",
    );

    expect(
      inToml.map((finding) => [finding.message, finding.location?.line]),
    ).toEqual([
      [
        "supabase/config.toml [storage.buckets.docs]: file size limit differs",
        1,
      ],
      [
        "supabase/config.toml [storage.buckets.docs]: allowed MIME types differ",
        1,
      ],
    ]);
  });

  it("ignores a bucket entry that is not a table", async () => {
    const findings = await run(
      "BS302",
      context(
        base,
        { configToml: toml("[storage.buckets]\ndocs = true\n") },
        config,
      ),
    );

    expect(
      findings.every((finding) => finding.target === "storage.buckets.docs"),
    ).toBe(true);
  });

  it("finds a declared bucket whose header it can't locate", async () => {
    const findings = await run(
      "BS302",
      context(
        base,
        {
          configToml: toml(
            '[storage.buckets."docs"]\npublic = true\nfile_size_limit = "1KiB"\nallowed_mime_types = ["application/pdf"]\n',
          ),
        },
        config,
      ),
    );

    const inToml = findings.filter(
      (finding) => finding.target === "[storage.buckets.docs]",
    );

    expect(inToml).toEqual([
      expect.objectContaining({
        message: "supabase/config.toml [storage.buckets.docs]: public is true",
      }),
    ]);
    expect(inToml[0]).not.toHaveProperty("location");
  });

  it("compares versioning and lifecycle when Storage reports them", async () => {
    const versioned: BetterSupabaseConfig = {
      database: {
        buckets: {
          docs: {
            ...config.database!.buckets!["docs"]!,
            versioning: true,
            lifecycle: {
              rules: [{ noncurrentVersionExpiration: { noncurrentDays: 30 } }],
            },
          },
        },
      },
    };

    const withBucket = (extra: Record<string, unknown>) =>
      snapshot((_tables, catalog) => {
        catalog.buckets = [
          {
            id: "docs",
            public: false,
            fileSizeLimit: 1024,
            allowedMimeTypes: ["application/pdf"],
            ...extra,
          },
        ];
      });

    const messages = async (extra: Record<string, unknown>) =>
      (await run("BS302", context(withBucket(extra), {}, versioned))).map(
        (finding) => finding.message,
      );

    expect(await messages({})).toEqual([]);
    expect(
      await messages({
        versioning: "ENABLED",
        lifecycle: {
          rules: [
            {
              id: "x",
              status: "Enabled",
              filter: {},
              noncurrentVersionExpiration: { noncurrentDays: 30 },
            },
          ],
        },
      }),
    ).toEqual([]);
    expect(await messages({ versioning: "DISABLED", lifecycle: null })).toEqual(
      [
        'Bucket docs: Bucket "docs" versioning is DISABLED',
        'Bucket docs: Bucket "docs" lifecycle policy differs',
      ],
    );
  });
});

describe("generated and module files (BS303, BS304)", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "better-supabase-rules-"));
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  async function write(path: string, contents: string): Promise<void> {
    await mkdir(dirname(join(root, path)), { recursive: true });
    await writeFile(join(root, path), contents);
  }

  const rooted = (config: BetterSupabaseConfig = {}): DoctorContext => ({
    ...context(),
    config: resolveConfig(config, root),
  });

  it("reports missing and stale generated files", async () => {
    const ctx = rooted();
    const files = await renderFiles(ctx.config, ctx.snapshot);
    expect(files.length).toBeGreaterThanOrEqual(2);
    const missing = await run("BS303", ctx);
    expect(missing.map((finding) => finding.message)).toEqual(
      files.map(
        (file) => `${file.path} is missing. Run \`better-supabase gen\`.`,
      ),
    );
    expect(missing[0]).not.toHaveProperty("location");

    await write(files[0]!.path, files[0]!.contents);
    await write(files[1]!.path, "// edited\n");
    const stale = await run("BS303", ctx);
    expect(stale).toEqual([
      expect.objectContaining({
        severity: "error",
        target: files[1]!.path,
        message: `${files[1]!.path} is out of date. Run \`better-supabase gen\`.`,
        location: { file: files[1]!.path, line: 1 },
      }),
      ...stale.slice(1),
    ]);
    expect(stale.map((finding) => finding.target)).not.toContain(
      files[0]!.path,
    );
  });

  it("renders api-keys scopes from the provider's permissions, and skips without them", async () => {
    const config: BetterSupabaseConfig = {
      blocks: { "api-keys": { options: { scopes: "catalog" } } },
    };

    const missing = await run(
      "BS304",
      rooted({ ...config, auth: { authorization: stubProvider } }),
    );

    expect(missing.map((finding) => finding.target)).toContain(
      "supabase/schemas/900_better_supabase_28_api_keys.sql",
    );
    expect(await run("BS304", rooted(config))).toEqual([]);
  });

  it("renders the same layout as sql sync for schema-derived modules", async () => {
    await write(
      "supabase/schemas/010_notes.sql",
      "create table public.notes (id int);\ncreate table public.jobs (id int);\nalter table public.jobs enable row level security;\ncreate policy notes_read on public.notes for select to authenticated using (true);\n",
    );

    const config: BetterSupabaseConfig = {
      blocks: {
        grants: { options: { fromPolicies: true } },
        sessions: { options: { policies: true } },
      },
    };

    const ctx = rooted(config);
    const missing = await run("BS304", ctx);
    expect(missing.length).toBeGreaterThanOrEqual(2);

    const synced = await runSql(ctx.config, parseArgs(["sync"], SQL_ARGS));

    expect(synced.code).toBe(0);
    expect(await run("BS304", ctx)).toEqual([]);

    const grants = await readFile(
      join(root, "supabase/schemas/900_better_supabase_13_grants.sql"),
      "utf-8",
    );

    expect(grants).toContain('"public"."jobs"');
  });

  it("checks the SQL modules in blocks", async () => {
    expect(await run("BS304", rooted())).toEqual([]);
    const ctx = rooted({ blocks: ["updated-at", "audit"] });

    const files = renderBlocks(ctx.config.blockNames, moduleLayout(ctx.config));

    const missing = await run("BS304", ctx);
    expect(missing.map((finding) => finding.target)).toEqual(
      files.map((file) => file.path),
    );
    expect(missing[0]!.message).toMatch(/\(updated-at\) is missing\./);
    expect(missing[0]!.message).toContain(
      "then `supabase db schema declarative sync`.",
    );

    const migra = await run("BS304", {
      ...ctx,
      configToml: toml("[experimental.pgdelta]\nenabled = false\n"),
    });

    expect(migra[0]!.message).toContain("then `supabase db diff`.");

    const migrations = await run("BS304", {
      ...ctx,
      config: {
        ...ctx.config,
        sql: { ...ctx.config.sql, workflow: "migrations" },
      },
    });

    expect(migrations[0]!.message).toContain("then `supabase migration up`.");

    const data = files.find((file) => file.kind === "data")!;
    expect(
      missing.find((finding) => finding.target === data.path)!.message,
    ).toContain("which also writes the rows into a migration");

    const audit = files.find(
      (file) => file.module === "audit" && file.kind === "schema",
    );

    for (const file of files) {
      await write(file.path, file.contents);
    }

    await write(
      audit!.path,
      audit!.contents.replace("create schema", "-- changed\ncreate schema"),
    );
    expect(await run("BS304", ctx)).toEqual([
      expect.objectContaining({
        target: audit!.path,
        message: expect.stringContaining("(audit) is out of date"),
        location: { file: audit!.path, line: 1 },
      }),
    ]);
  });

  it("checks the newest module migration under the migrations workflow", async () => {
    const ctx = rooted({
      database: { sql: { workflow: "migrations" } },
      blocks: ["tenant", "mfa"],
    });

    const missing = await run("BS304", ctx);
    expect(missing.map((finding) => finding.message)).toEqual(
      ["updated-at", "tenant", "mfa"].map(
        (module) =>
          `${module} in supabase/migrations/<stamp>_better_supabase_modules.sql is missing. Run \`better-supabase upgrade\`, then \`supabase migration up\`.`,
      ),
    );
    const files = renderBlocks(["tenant", "mfa"], moduleLayout(ctx.config));

    const name =
      "supabase/migrations/20200101000000_better_supabase_modules.sql";

    await write(
      name,
      files
        .filter((file) => file.kind !== "test")
        .map((file) => file.contents)
        .join("\n")
        .replace(/^-- @bsb-block tenant@2/m, "-- @bsb-block tenant@1"),
    );
    expect(await run("BS304", ctx)).toEqual([]);
    expect(await run("BS311", ctx)).toEqual([
      expect.objectContaining({
        target: name,
        message: expect.stringContaining("has tenant version 1"),
      }),
    ]);
  });

  it("still checks the pgTAP files under the migrations workflow", async () => {
    const ctx = rooted({
      database: { sql: { workflow: "migrations" } },
      blocks: ["pgtap"],
    });

    const files = renderBlocks(["pgtap"], moduleLayout(ctx.config));
    const test = files.find((file) => file.kind === "test");
    expect(test).toBeDefined();
    await write(
      "supabase/migrations/20200101000000_better_supabase_modules.sql",
      files
        .filter((file) => file.kind !== "test")
        .map((file) => file.contents)
        .join("\n"),
    );
    expect((await run("BS304", ctx)).map((finding) => finding.target)).toEqual([
      test!.path,
    ]);
    await write(test!.path, test!.contents);
    expect(await run("BS304", ctx)).toEqual([]);
  });

  it("reports a module behind its version in BS311, not BS304", async () => {
    const ctx = rooted({ blocks: ["tenant"] });
    const files = renderBlocks(["tenant"], moduleLayout(ctx.config));

    for (const module of files) {
      await write(module.path, module.contents);
    }

    const file = files.find(
      (module) => module.module === "tenant" && module.kind === "schema",
    );

    await write(file!.path, file!.contents.replace(/^-- @bsb-block .*\n/m, ""));
    expect(await run("BS304", ctx)).toEqual([]);
    expect(await run("BS311", ctx)).toEqual([
      expect.objectContaining({
        severity: "warning",
        target: file!.path,
        message: expect.stringContaining(
          "has tenant version 1; this release ships version 2. Run `better-supabase upgrade`",
        ),
      }),
    ]);
    await write(file!.path, file!.contents);
    expect(await run("BS311", ctx)).toEqual([]);
  });

  it("reads modules on a live database in BS311", async () => {
    const ctx = rooted({ blocks: ["tenant", "mfa"] });

    const live = (rows: Record<string, unknown>[] | Error) => ({
      ...ctx,
      database: {
        describe: "test",
        session: true,
        query: <R>() =>
          rows instanceof Error
            ? Promise.reject(rows)
            : Promise.resolve(rows as R[]),
      },
    });

    expect(
      await run(
        "BS311",
        live([
          { name: "tenant", version: 1 },
          { name: "mfa", version: 1 },
          { name: "audit", version: 0 },
        ]),
      ),
    ).toEqual([
      expect.objectContaining({
        target: "better_supabase.blocks.tenant",
        message: expect.stringContaining(
          "The database has tenant version 1; this release ships version 2.",
        ),
      }),
    ]);
    expect(await run("BS311", live(new Error("no table")))).toEqual([]);
  });

  it("skips the read-sets module when the read sets could not be loaded", async () => {
    const ctx = rooted({ blocks: ["read-sets"] });
    expect(
      (await run("BS304", { ...ctx, readSets: { skipped: "no config" } })).map(
        (finding) => finding.message,
      ),
    ).toEqual([]);
    expect(
      (await run("BS304", { ...ctx, readSets: [] })).map(
        (finding) => finding.target,
      ),
    ).toEqual(
      renderBlocks(["read-sets"], moduleLayout(ctx.config)).map(
        (file) => file.path,
      ),
    );
  });
});

describe("module upgrades (BS309, BS310)", () => {
  it("reports deprecated module symbols in schema files and policies", async () => {
    const snap = snapshot((tables) => {
      table(tables, "notes").policies = [
        {
          name: "organization members",
          command: "select",
          roles: ["authenticated"],
          permissive: true,
          using: "(org_id = (auth.jwt() ->> 'org_id')::uuid)",
          check: null,
        },
      ];
    });

    const findings = await run(
      "BS309",
      context(
        snap,
        {
          sqlFiles: [
            {
              path: "supabase/schemas/100_notes.sql",
              text: "create view v as\nselect better_supabase.current_org_id();\n",
            },
            {
              path: "supabase/migrations/1_old.sql",
              text: "select better_supabase.current_org_id();",
            },
            {
              path: "../../supabase/migrations/2_old.sql",
              text: "select better_supabase.current_org_id();",
            },
            {
              path: "supabase/schemas/900_better_supabase_04_tenant.sql",
              text: "-- @bsb-block tenant@2 managed\nselect better_supabase.current_org_id();",
            },
          ],
        },
        { blocks: ["tenant"] },
      ),
    );

    expect(
      findings.map((finding) => [finding.target, finding.location]),
    ).toEqual([
      [
        "supabase/schemas/100_notes.sql:better_supabase.current_org_id",
        { file: "supabase/schemas/100_notes.sql", line: 2 },
      ],
      ["public.notes.organization members:org_id", undefined],
    ]);
    expect(findings[0]!.message).toContain(
      "removed in 0.2.0. Use better_supabase.current_tenant_id().",
    );
    expect(
      await run(
        "BS309",
        context(
          snap,
          {},
          { blocks: ["tenant"], auth: { organization: { claim: "org_id" } } },
        ),
      ),
    ).toEqual([]);
    expect(await run("BS309", context(snap))).toEqual([]);
  });

  it("reports a renamed module column used unqualified next to its table", async () => {
    const snap = snapshot((tables) => {
      table(tables, "notes").policies = [
        {
          name: "own rows",
          command: "select",
          roles: ["authenticated"],
          permissive: true,
          using:
            "(exists (select 1 from better_supabase.memberships m where m.org_id = notes.tenant))",
          check: null,
        },
      ];
    });

    const sqlFiles = [
      {
        path: "supabase/schemas/100_notes.sql",
        text: "create view v as select 1;\ncreate view w as\nselect m.org_id\nfrom better_supabase.memberships m;\n",
      },
      {
        path: "supabase/schemas/110_other.sql",
        text: "select org_id from public.notes;",
      },
    ];

    const findings = await run(
      "BS309",
      context(snap, { sqlFiles }, { blocks: ["tenant"] }),
    );

    expect(
      findings.map((finding) => [finding.target, finding.location]),
    ).toEqual([
      [
        "supabase/schemas/100_notes.sql:memberships.org_id",
        { file: "supabase/schemas/100_notes.sql", line: 3 },
      ],
      ["public.notes.own rows:memberships.org_id", undefined],
    ]);
    expect(
      await run(
        "BS309",
        context(
          snap,
          { sqlFiles },
          { blocks: { tenant: { ownership: "adopt" } } },
        ),
      ),
    ).toEqual([]);
  });

  it("reports a table with a module trigger and an equivalent one", async () => {
    const trigger = (name: string, fn: string) => ({
      name,
      timing: "before" as const,
      events: ["update" as const],
      level: "row" as const,
      function: fn,
    });

    const snap = snapshot((tables) => {
      table(tables, "notes").triggers = [
        trigger("bsb_updated_at", "better_supabase.set_updated_at"),
        trigger("handle_updated_at", "extensions.moddatetime"),
        trigger("bsb_audit", "better_supabase.audit_trigger"),
        trigger("notify", "public.notify_change"),
      ];
      table(tables, "tags").triggers = [trigger("touch", "public.touch_row")];
    });

    const findings = await run("BS310", context(snap));
    expect(findings).toEqual([
      expect.objectContaining({
        target: "public.notes.handle_updated_at",
        message: expect.stringContaining(
          "select better_supabase.track_updated_at('public.notes', replace_trigger => true)",
        ),
      }),
    ]);
  });
});

describe("exposed module schemas (BS312)", () => {
  const api = toml('[api]\nschemas = ["public", "better_supabase", "crm"]\n');

  it("reports better_supabase and modules.*.schema in [api] schemas", async () => {
    const findings = await run(
      "BS312",
      context(
        base,
        { configToml: api },
        { blocks: { tenant: {}, audit: { schema: "crm" } } },
      ),
    );

    expect(findings.map((finding) => finding.target)).toEqual([
      "better_supabase",
      "crm",
    ]);
    expect(findings[0]!.severity).toBe("error");
  });

  it("skips projects without SQL modules or exposed module schemas", async () => {
    expect(await run("BS312", context(base, { configToml: api }))).toEqual([]);
    expect(
      await run(
        "BS312",
        context(
          base,
          { configToml: toml('[api]\nschemas = ["public"]\n') },
          {
            blocks: ["tenant"],
            database: { schemas: ["public", "better_supabase"] },
          },
        ),
      ),
    ).toEqual([]);
    expect(
      await run(
        "BS312",
        context(
          base,
          {},
          {
            blocks: ["tenant"],
            database: { schemas: ["public", "better_supabase"] },
          },
        ),
      ),
    ).toHaveLength(1);
  });
});

describe("rate limits wired to PostgREST (BS313)", () => {
  const live = (
    module: string[],
    rows: Record<string, unknown>[] | Error,
  ): Parameters<typeof run>[1] => ({
    ...context(base, {}, { blocks: module }),
    database: {
      describe: "test",
      session: true,
      query: <R>() =>
        rows instanceof Error
          ? Promise.reject(rows)
          : Promise.resolve(rows as R[]),
    },
  });

  it("reports an unset hook and one that doesn't call check_request", async () => {
    expect(
      await run("BS313", live(["rate-limit"], [{ hook: null, calls: false }])),
    ).toEqual([
      expect.objectContaining({
        severity: "warning",
        target: "authenticator pgrst.db_pre_request",
        message: expect.stringContaining("pgrst.db_pre_request isn't set"),
      }),
    ]);
    expect(
      (
        await run(
          "BS313",
          live(["rate-limit"], [{ hook: "public.pre_request", calls: false }]),
        )
      )[0]!.message,
    ).toBe(
      "pgrst.db_pre_request is public.pre_request, which doesn't call better_supabase.check_request(), so rate limits never apply. Call it from public.pre_request.",
    );
  });

  it("passes the module hook, a chaining hook, and projects without the module or a database", async () => {
    for (const row of [
      { hook: "better_supabase.check_request", calls: false },
      { hook: "public.pre_request", calls: true },
    ]) {
      expect(await run("BS313", live(["rate-limit"], [row]))).toEqual([]);
    }

    expect(
      await run("BS313", live(["tenant"], [{ hook: null, calls: false }])),
    ).toEqual([]);
    expect(
      await run("BS313", live(["rate-limit"], new Error("denied"))),
    ).toEqual([]);
    expect(
      await run("BS313", context(base, {}, { blocks: ["rate-limit"] })),
    ).toEqual([]);
  });
});

describe("rate limits without the pre-request hook (BS313)", () => {
  it("skips the check when preRequest is false", async () => {
    const database = {
      describe: "test",
      session: true,
      query: <R>() => Promise.resolve([{ hook: null, calls: false }] as R[]),
    };

    const modules = (preRequest: boolean) =>
      context(
        base,
        { database },
        { blocks: { "rate-limit": { options: { preRequest } } } },
      );

    expect(await run("BS313", modules(false))).toEqual([]);
    expect(await run("BS313", modules(true))).toHaveLength(1);
  });
});

describe("audit registrations of dropped tables (BS322)", () => {
  const live = (
    module: string[],
    rows: Record<string, unknown>[] | Error,
  ): Parameters<typeof run>[1] => ({
    ...context(base, {}, { blocks: module }),
    database: {
      describe: "test",
      session: true,
      query: <R>() =>
        rows instanceof Error
          ? Promise.reject(rows)
          : Promise.resolve(rows as R[]),
    },
  });

  it("reports each registration whose table is gone", async () => {
    expect(
      await run("BS322", live(["audit"], [{ oid: "16384" }, { oid: "16390" }])),
    ).toEqual([
      expect.objectContaining({
        severity: "warning",
        target: "better_supabase.audited_tables 16384",
        message: expect.stringContaining("oid 16384, which no longer exists"),
      }),
      expect.objectContaining({
        target: "better_supabase.audited_tables 16390",
      }),
    ]);
  });

  it("passes a clean registry, projects without the module, a failed query and no database", async () => {
    expect(await run("BS322", live(["audit"], []))).toEqual([]);
    expect(await run("BS322", live(["tenant"], [{ oid: "1" }]))).toEqual([]);
    expect(await run("BS322", live(["audit"], new Error("denied")))).toEqual(
      [],
    );
    expect(
      await run("BS322", context(base, {}, { blocks: ["audit"] })),
    ).toEqual([]);
  });
});

describe("flags past their expiry (BS336)", () => {
  const withExpiry = (extraColumns: Record<string, string>) => ({
    blocks: { flags: { options: { extraColumns } } },
  });

  const live = (
    config: Parameters<typeof context>[2],
    rows: Record<string, unknown>[] | Error,
    queries: string[] = [],
  ): Parameters<typeof run>[1] =>
    context(
      base,
      {
        database: {
          describe: "test",
          session: true,
          query: <R>(sql: string) => {
            queries.push(sql);

            return rows instanceof Error
              ? Promise.reject(rows)
              : Promise.resolve(rows as R[]);
          },
        },
      },
      config,
    );

  it("reports each expired flag with its owner", async () => {
    const queries: string[] = [];

    const findings = await run(
      "BS336",
      live(
        withExpiry({ expires_at: "timestamptz", owner: "text" }),
        [
          {
            key: "new-nav",
            expires_at: "2026-01-01 00:00:00+00",
            owner: "growth",
          },
          {
            key: "dark-mode",
            expires_at: "2026-02-01 00:00:00+00",
            owner: null,
          },
        ],
        queries,
      ),
    );

    expect(queries[0]).toContain('f."owner"::text as owner');
    expect(queries[0]).toContain('not f."archived"');
    expect(findings).toEqual([
      expect.objectContaining({
        severity: "warning",
        target: "flags:new-nav",
        message: expect.stringContaining(
          'Flag "new-nav" expired on 2026-01-01 00:00:00+00 (owner: growth)',
        ),
      }),
      expect.objectContaining({
        target: "flags:dark-mode",
        message: expect.not.stringContaining("owner:"),
      }),
    ]);
  });

  it("skips projects without the column, the module or a database, and a failed query", async () => {
    const rows = [{ key: "a", expires_at: "2026-01-01", owner: null }];

    expect(
      await run("BS336", live(withExpiry({ owner: "text" }), rows)),
    ).toEqual([]);
    expect(await run("BS336", live({ blocks: ["audit"] }, rows))).toEqual([]);
    expect(
      await run(
        "BS336",
        live(withExpiry({ expires_at: "timestamptz" }), new Error("denied")),
      ),
    ).toEqual([]);
    expect(
      await run(
        "BS336",
        context(base, {}, withExpiry({ expires_at: "timestamptz" })),
      ),
    ).toEqual([]);
  });
});

describe("adopted tables without a mapped column (BS330)", () => {
  const credentials = {
    blocks: {
      credentials: {
        mode: "adopt" as const,
        tables: { secrets: "public.integration_secrets" },
        columns: {
          secrets: { name: "key", tenant: "organization_id", scope: null },
        },
      },
    },
  };

  const live = (rows: Record<string, unknown>[] | Error) => ({
    describe: "test",
    session: true,
    query: <R>() =>
      rows instanceof Error
        ? Promise.reject(rows)
        : Promise.resolve(rows as R[]),
  });

  const columns = (...names: string[]) =>
    names.map((column) => ({
      schema: "public",
      name: "integration_secrets",
      column,
    }));

  it("reports each mapped column the live table lacks", async () => {
    const findings = await run(
      "BS330",
      context(
        base,
        { database: live(columns("provider", "organization_id", "vault_id")) },
        credentials,
      ),
    );

    expect(findings.map((finding) => finding.target)).toEqual([
      "public.integration_secrets.key",
      "public.integration_secrets.updated_at",
    ]);
    expect(findings[0]).toEqual(
      expect.objectContaining({
        severity: "error",
        message: expect.stringContaining(
          "blocks.credentials.columns.secrets.name",
        ),
      }),
    );
  });

  it("reports a missing table, and passes a complete one, managed modules and no database", async () => {
    expect(
      await run("BS330", context(base, { database: live([]) }, credentials)),
    ).toEqual([
      expect.objectContaining({
        target: "public.integration_secrets",
        message: expect.stringContaining("which the database does not have"),
      }),
    ]);
    expect(
      await run(
        "BS330",
        context(
          base,
          {
            database: live(
              columns(
                "provider",
                "key",
                "organization_id",
                "vault_id",
                "updated_at",
              ),
            ),
          },
          credentials,
        ),
      ),
    ).toEqual([]);
    expect(
      await run(
        "BS330",
        context(base, { database: live([]) }, { blocks: { credentials: {} } }),
      ),
    ).toEqual([]);
    expect(await run("BS330", context(base, {}, credentials))).toEqual([]);
    expect(
      await run(
        "BS330",
        context(base, { database: live(new Error("denied")) }, credentials),
      ),
    ).toEqual([]);
  });

  it("checks tables an adopted module uses only when mapped, once they are mapped", async () => {
    const targets = async (tables: Record<string, string>) =>
      (
        await run(
          "BS330",
          context(
            base,
            { database: live([]) },
            { blocks: { notifications: { ownership: "adopt", tables } } },
          ),
        )
      ).map((finding) => finding.target);

    const unmapped = await targets({});
    expect(unmapped).not.toContain(
      "better_supabase.notification_delivery_events",
    );
    expect(unmapped).not.toContain("better_supabase.notification_suppressions");
    expect(unmapped).toContain("better_supabase.notification_deliveries");

    expect(
      await targets({
        deliveryEvents: "public.delivery_events",
        suppressions: "public.suppressed_addresses",
      }),
    ).toEqual(
      expect.arrayContaining([
        "public.delivery_events",
        "public.suppressed_addresses",
      ]),
    );
  });
});

describe("adopted enum columns the module writes as text (BS342)", () => {
  const enumSnapshot = snapshot((tables, catalog) => {
    const notes = table(tables, "notes");
    const column = notes.columns[0]!;

    catalog.enums = [
      ...catalog.enums,
      { schema: "public", name: "subject_type", values: ["invoice"] },
      { schema: "public", name: "fiscal_period", values: ["2026"] },
    ];

    const enumColumn = (name: string, udt: string) => ({
      ...column,
      name,
      udt,
      format: udt,
      typeSchema: "public",
      isEnum: true,
      isArray: false,
    });

    tables.push({
      ...notes,
      name: "number_sequences",
      columns: [
        enumColumn("entity", "subject_type"),
        enumColumn("period", "fiscal_period"),
      ],
      foreignKeys: [],
      triggers: [],
    });
  });

  const blocks = {
    blocks: {
      "number-sequences": {
        mode: "adopt" as const,
        tables: { sequences: "public.number_sequences" },
      },
    },
  };

  it("reports an enum column the module writes as text, not one it casts", async () => {
    expect(await run("BS342", context(enumSnapshot, {}, blocks))).toEqual([
      expect.objectContaining({
        severity: "error",
        target: "public.number_sequences.period",
        message: expect.stringContaining(
          "(sequences.period), which is the enum public.fiscal_period",
        ),
      }),
    ]);
  });

  it("passes managed modules and tables the snapshot lacks", async () => {
    expect(await run("BS342", context(enumSnapshot))).toEqual([]);
    expect(await run("BS342", context(base, {}, blocks))).toEqual([]);
  });
});

describe("adopted webhook endpoints without a format (BS344)", () => {
  const withEndpoints = (columns: readonly string[]) =>
    snapshot((tables) => {
      const notes = table(tables, "notes");
      const column = notes.columns[0]!;

      tables.push({
        ...notes,
        name: "hook_endpoints",
        columns: columns.map((name) => ({ ...column, name })),
        foreignKeys: [],
        triggers: [],
      });
    });

  const adopt = (extra: Record<string, unknown> = {}) => ({
    blocks: {
      "webhooks-out": {
        mode: "adopt" as const,
        tables: { endpoints: "public.hook_endpoints" },
        ...extra,
      },
    },
  });

  it("reports an adopted endpoints table with no format column and no defaultFormat", async () => {
    expect(
      await run("BS344", context(withEndpoints(["id", "url"]), {}, adopt())),
    ).toEqual([
      expect.objectContaining({
        severity: "warning",
        target: "blocks.webhooks-out.options.defaultFormat",
        message: expect.stringContaining(
          "public.hook_endpoints has no format column",
        ),
      }),
    ]);
    expect(
      await run(
        "BS344",
        context(withEndpoints(["id", "url", "format"]), {}, adopt()),
      ),
    ).toEqual([
      expect.objectContaining({
        message: expect.stringContaining(
          "has a format column the config doesn't map",
        ),
      }),
    ]);
  });

  it("passes an explicit defaultFormat, a mapped column and managed tables", async () => {
    const snap = withEndpoints(["id", "url", "format"]);

    expect(
      await run(
        "BS344",
        context(snap, {}, adopt({ options: { defaultFormat: "standard" } })),
      ),
    ).toEqual([]);
    expect(
      await run(
        "BS344",
        context(
          snap,
          {},
          adopt({ columns: { endpoints: { format: "format" } } }),
        ),
      ),
    ).toEqual([]);
    expect(
      await run("BS344", context(snap, {}, { blocks: { "webhooks-out": {} } })),
    ).toEqual([]);
  });
});

describe("subject registry (BS331, BS332)", () => {
  it("reports a missing table and each missing column", async () => {
    const findings = await run(
      "BS331",
      context(
        base,
        {},
        {
          records: {
            note: { table: "notes", title: "headline", url: "/n/{slug}" },
            ghost: { table: "public.ghosts" },
            other: { table: "elsewhere.things" },
          },
        },
      ),
    );

    expect(findings.map((finding) => finding.target)).toEqual([
      "public.notes.headline",
      "public.notes.slug",
      "public.ghosts",
    ]);
    expect(findings[0]).toEqual(
      expect.objectContaining({
        severity: "error",
        message: expect.stringContaining("subjects.note.title"),
      }),
    );
  });

  it("passes a complete entry", async () => {
    expect(
      await run(
        "BS331",
        context(
          base,
          {},
          {
            records: {
              note: { table: "notes", title: "body", url: "/n/{id}" },
            },
          },
        ),
      ),
    ).toEqual([]);
  });

  it("warns about a subject table without RLS", async () => {
    const config = { records: { note: { table: "notes" } } };
    expect(await run("BS332", context(base, {}, config))).toEqual([]);

    const open = snapshot((tables) => {
      table(tables, "notes").rls = false;
    });

    expect(await run("BS332", context(open, {}, config))).toEqual([
      expect.objectContaining({ severity: "warning", target: "public.notes" }),
    ]);
  });
});

describe("attachments subject on block-wide keys (BS345)", () => {
  const withPolicies = (select: string, insert: string) =>
    snapshot((tables) => {
      const notes = table(tables, "notes");
      notes.rls = true;
      notes.policies = [
        {
          name: "notes_select",
          command: "select",
          roles: ["authenticated"],
          permissive: true,
          using: select,
          check: null,
        },
        {
          name: "notes_insert",
          command: "insert",
          roles: ["authenticated"],
          permissive: true,
          using: null,
          check: insert,
        },
      ];
    });

  const tenantOnly =
    "(organization_id = ( SELECT better_supabase.current_tenant_id() AS current_tenant_id))";

  const strict =
    "(better_supabase.can('tenant'::text, organization_id, 'notes.read'::text) AND (owner_id = ( SELECT auth.uid() AS uid)))";

  const config = (
    subjects: Readonly<Record<string, unknown>>,
    registry: Readonly<Record<string, { table: string }>> = {},
  ): BetterSupabaseConfig => ({
    records: registry,
    blocks: { attachments: { options: { subjects } } },
  });

  it("reports a subject whose table checks more than tenant membership", async () => {
    const findings = await run(
      "BS345",
      context(
        withPolicies(strict, tenantOnly),
        {},
        config({ note: { table: "notes" } }),
      ),
    );

    expect(findings).toEqual([
      expect.objectContaining({
        severity: "warning",
        target: "public.notes",
        message: expect.stringContaining(
          "blocks.attachments.options.subjects.note.permissions.read",
        ),
      }),
    ]);
    expect(findings[0]?.message).not.toContain("permissions.upload");
  });

  it("passes tenant-only policies, the block's own key and a soft-delete filter", async () => {
    const blockKey =
      "((organization_id IN ( SELECT better_supabase.tenant_ids_with('attachments.read'::text) AS tenant_ids_with)) AND (deleted_at IS NULL))";

    expect(
      await run(
        "BS345",
        context(
          withPolicies(blockKey, tenantOnly),
          {},
          config({ note: { table: "notes" } }),
        ),
      ),
    ).toEqual([]);
  });

  it("counts the subject's own read key, which the readable check adds", async () => {
    const snap = withPolicies(strict, tenantOnly);

    expect(
      await run(
        "BS345",
        context(
          snap,
          {},
          config({ note: { table: "notes", permission: "notes.read" } }),
        ),
      ),
    ).toEqual([]);
    expect(
      await run(
        "BS345",
        context(
          snap,
          {},
          {
            records: {
              note: { table: "notes", permissions: { read: "notes.read" } },
            },
            blocks: { attachments: {} },
          },
        ),
      ),
    ).toEqual([]);
  });

  it("reads subjects listed by name from the registry and skips unknown tables", async () => {
    const findings = await run(
      "BS345",
      context(
        withPolicies(strict, tenantOnly),
        {},
        {
          records: {
            note: { table: "public.notes" },
            ghost: { table: "missing" },
          },
          blocks: {
            attachments: { options: { subjects: ["note", "ghost", 1] } },
          },
        },
      ),
    );

    expect(findings.map((finding) => finding.target)).toEqual(["public.notes"]);

    const forAll = snapshot((tables) => {
      const notes = table(tables, "notes");
      notes.rls = true;
      notes.policies = [
        {
          name: "notes_all",
          command: "all",
          roles: ["authenticated"],
          permissive: true,
          using: tenantOnly,
          check: null,
        },
      ];
    });

    for (const subjects of [{ note: { table: "notes" }, bad: 1 }, "notes"]) {
      expect(
        await run(
          "BS345",
          context(
            forAll,
            {},
            {
              records: { note: { table: "notes" } },
              blocks: { attachments: { options: { subjects } } },
            },
          ),
        ),
      ).toEqual([]);
    }
  });

  it("passes provider membership helpers, a wider or branch and a table no client inserts into", async () => {
    const provider =
      "(organization_id IN ( SELECT centrakit.authz_organization_member_ids() AS authz_organization_member_ids))";

    const wider = `(${provider} OR (id IN ( SELECT pm.note_id FROM project_members pm WHERE (pm.user_id = ( SELECT auth.uid() AS uid)))))`;

    const readOnly = snapshot((tables) => {
      const notes = table(tables, "notes");
      notes.rls = true;
      notes.policies = [
        {
          name: "notes_select",
          command: "select",
          roles: ["authenticated"],
          permissive: true,
          using: wider,
          check: null,
        },
      ];
    });

    for (const snap of [withPolicies(provider, provider), readOnly]) {
      expect(
        await run(
          "BS345",
          context(snap, {}, config({ note: { table: "notes" } })),
        ),
      ).toEqual([]);
    }
  });

  it("passes a subject with its own keys, from the block or the registry", async () => {
    const snap = withPolicies(tenantOnly, strict);

    expect(
      await run(
        "BS345",
        context(
          snap,
          {},
          config({
            note: { table: "notes", permissions: { upload: "notes.edit" } },
          }),
        ),
      ),
    ).toEqual([]);
    expect(
      await run(
        "BS345",
        context(
          snap,
          {},
          {
            records: {
              note: { table: "notes", permissions: { upload: "notes.edit" } },
            },
            blocks: { attachments: {} },
          },
        ),
      ),
    ).toEqual([]);
    expect(
      await run(
        "BS345",
        context(
          snap,
          {},
          {
            records: { note: { table: "notes" } },
            blocks: { attachments: {} },
          },
        ),
      ),
    ).toEqual([
      expect.objectContaining({
        message: expect.stringContaining("subjects.note.permissions.upload"),
      }),
    ]);
  });
});

describe("partition without RLS (BS343)", () => {
  const withPartition = (rls: boolean) =>
    snapshot((tables) => {
      const parent = table(tables, "notes");
      parent.rls = true;
      tables.push({
        ...structuredClone(parent),
        id: 9_000_001,
        name: "notes_default",
        rls,
        partitionOf: "public.notes",
        policies: [],
      });
    });

  it("reports a partition whose parent has RLS and it doesn't", async () => {
    expect(await run("BS343", context(withPartition(false)))).toEqual([
      expect.objectContaining({
        severity: "error",
        target: "public.notes_default",
      }),
    ]);
  });

  it("passes a partition with RLS and tables that aren't partitions", async () => {
    expect(await run("BS343", context(withPartition(true)))).toEqual([]);
    expect(await run("BS343", context(base))).toEqual([]);
  });
});

describe("unpartitioned audit log (BS335)", () => {
  const withLog = (primaryKey: string[]) =>
    snapshot((tables) => {
      const log = tables.find(
        (entry) =>
          entry.schema === "better_supabase" && entry.name === "audit_events",
      );

      if (log) {
        log.primaryKey = primaryKey;
      }
    });

  const partitioned = { blocks: { audit: { options: { partitioned: true } } } };

  it("reports a log whose key is id alone", async () => {
    expect(
      await run("BS335", context(withLog(["id"]), {}, partitioned)),
    ).toEqual([
      expect.objectContaining({
        severity: "warning",
        target: "better_supabase.audit_events",
      }),
    ]);
  });

  it("passes a partitioned log, the option off and a missing table", async () => {
    expect(
      await run(
        "BS335",
        context(withLog(["id", "occurred_at"]), {}, partitioned),
      ),
    ).toEqual([]);
    expect(
      await run("BS335", context(withLog(["id"]), {}, { blocks: ["audit"] })),
    ).toEqual([]);

    const missing = snapshot((tables) => {
      tables.splice(
        tables.findIndex((entry) => entry.name === "audit_events"),
        1,
      );
    });

    expect(await run("BS335", context(missing, {}, partitioned))).toEqual([]);
    expect(await run("BS335", context(withLog(["id"])))).toEqual([]);
  });
});

describe("unpartitioned block tables (BS335)", () => {
  const NAMES = [
    "outbox_events",
    "usage_history",
    "webhook_deliveries",
    "notification_delivery_events",
  ];

  const withTables = (primaryKey: string[]) =>
    snapshot((tables) => {
      const log = tables.find(
        (entry) =>
          entry.schema === "better_supabase" && entry.name === "audit_events",
      )!;

      for (const name of NAMES) {
        const existing = tables.find(
          (entry) => entry.schema === "better_supabase" && entry.name === name,
        );

        if (existing) {
          existing.primaryKey = primaryKey;
        } else {
          tables.push({ ...structuredClone(log), name, primaryKey });
        }
      }
    });

  const partitioned = {
    blocks: {
      outbox: { options: { partitioned: true } },
      usage: { options: { partitioned: true, history: true } },
      webhooks: { options: { partitioned: true } },
      notifications: { options: { partitioned: true } },
    },
  };

  it("reports each block table whose key is id alone", async () => {
    const findings = await run(
      "BS335",
      context(withTables(["id"]), {}, partitioned),
    );

    expect(
      findings
        .map((finding) => finding.target ?? "")
        .toSorted((a, b) => a.localeCompare(b)),
    ).toEqual(
      NAMES.map((name) => `better_supabase.${name}`).toSorted((a, b) =>
        a.localeCompare(b),
      ),
    );
  });

  it("passes partitioned tables, and usage without history", async () => {
    expect(
      await run(
        "BS335",
        context(withTables(["id", "created_at"]), {}, partitioned),
      ),
    ).toEqual([]);
    expect(
      await run(
        "BS335",
        context(
          withTables(["id"]),
          {},
          { blocks: { usage: { options: { partitioned: true } } } },
        ),
      ),
    ).toEqual([]);
  });
});

describe("module event triggers (BS323)", () => {
  const modules = { blocks: ["audit", "ensure-rls", "tenant"] };

  const live = (rows: Record<string, unknown>[] | Error) => ({
    describe: "test",
    session: true,
    query: <R>() =>
      rows instanceof Error
        ? Promise.reject(rows)
        : Promise.resolve(rows as R[]),
  });

  it("reports the module event triggers the database lacks", async () => {
    const findings = await run(
      "BS323",
      context(base, { database: live([{ name: "bsb_ensure_rls" }]) }, modules),
    );

    expect(findings).toEqual([
      expect.objectContaining({
        severity: "warning",
        target: "bsb_audit_forget_dropped",
        message: expect.stringContaining(
          "The database has no event trigger bsb_audit_forget_dropped, which the audit module creates.",
        ),
      }),
    ]);
    expect(findings[0]!.message).toContain("better-supabase add --adopt");
    expect(
      await run(
        "BS323",
        context(
          base,
          {
            database: live([
              { name: "bsb_ensure_rls" },
              { name: "bsb_audit_forget_dropped" },
            ]),
          },
          modules,
        ),
      ),
    ).toEqual([]);
    expect(
      await run(
        "BS323",
        context(base, { database: live(new Error("denied")) }, modules),
      ),
    ).toEqual([]);
  });

  it("checks the migrations without a database", async () => {
    const migration = (text: string, name = "1_init.sql") => ({
      path: `supabase/migrations/${name}`,
      text,
    });

    const findings = await run(
      "BS323",
      context(
        base,
        {
          configToml: toml(""),
          sqlFiles: [
            {
              path: "supabase/schemas/audit.sql",
              text: "create event trigger bsb_audit_forget_dropped on sql_drop execute function f();",
            },
            migration(
              'create event trigger "bsb_ensure_rls" on ddl_command_end execute function g();',
            ),
          ],
        },
        modules,
      ),
    );

    expect(findings.map((finding) => finding.target)).toEqual([
      "bsb_audit_forget_dropped",
    ]);
    expect(findings[0]!.message).toContain("No migration creates");
    expect(
      await run(
        "BS323",
        context(base, { configToml: toml(""), sqlFiles: [] }, modules),
      ),
    ).toEqual([]);
    expect(await run("BS323", context(base, {}, modules))).toEqual([]);
    expect(
      await run(
        "BS323",
        context(base, { database: live([]) }, { blocks: ["tenant"] }),
      ),
    ).toEqual([]);
  });
});

describe("migration-only module options (BS314)", () => {
  it("warns about each weakening option on a module in blocks", async () => {
    const findings = await run(
      "BS314",
      context(
        base,
        {},
        {
          blocks: {
            invitations: {
              ownership: "adopt",
              options: { tokenStorage: "plain" },
            },
            outbox: {
              ownership: "adopt",
              options: {
                blockSource: "better-supabase/{module}",
                defaultSource: "domain",
              },
            },
          },
        },
      ),
    );

    expect(findings).toEqual([
      expect.objectContaining({
        severity: "warning",
        target: "blocks.invitations.options.tokenStorage",
      }),
      expect.objectContaining({
        target: "blocks.outbox.options.defaultSource",
      }),
    ]);
    expect(findings[0]!.message).toBe(
      'blocks.invitations.options.tokenStorage is "plain". It stores invitation tokens in plain text instead of their SHA-256 hash. It exists to adopt an existing schema; remove it once your data matches the managed default.',
    );
  });

  it("is quiet for managed defaults", async () => {
    expect(
      await run(
        "BS314",
        context(
          base,
          {},
          { blocks: { invitations: { options: { tokenStorage: "sha256" } } } },
        ),
      ),
    ).toEqual([]);
  });
});

describe("legacy migra engine (BS316)", () => {
  const schema = {
    path: "supabase/schemas/tasks.sql",
    text: "create table tasks (id int);",
  };

  it("flags declarative schemas without pg-delta", async () => {
    const findings = await run(
      "BS316",
      context(base, { configToml: toml("[db]\n"), sqlFiles: [schema] }),
    );

    expect(findings).toHaveLength(1);
    expect(findings[0]).toMatchObject({
      severity: "warning",
      target: "supabase/config.toml",
      location: { file: "supabase/config.toml", line: 1 },
    });
    expect(findings[0]!.message).toContain(
      "`supabase db schema declarative sync` instead of `supabase db diff`",
    );
    expect(
      await run(
        "BS316",
        context(base, { configToml: toml("[db]\n") }, { blocks: ["audit"] }),
      ),
    ).toHaveLength(1);
  });

  it("stays quiet when sql.workflow chooses migra or migrations", async () => {
    const legacy = { configToml: toml("[db]\n"), sqlFiles: [schema] };
    const [unset] = await run("BS316", context(base, legacy));
    expect(unset!.message).toContain(
      'To stay on migra, set `database.sql.workflow: "migra"` in better-supabase.config.ts.',
    );

    for (const workflow of ["migra", "migrations"] as const) {
      expect(
        await run(
          "BS316",
          context(base, legacy, { database: { sql: { workflow } } }),
        ),
      ).toEqual([]);
    }
  });

  it("passes pg-delta projects and projects without declarative schemas", async () => {
    const pgdelta = toml("[experimental.pgdelta]\nenabled = true\n");
    expect(
      await run(
        "BS316",
        context(base, { configToml: pgdelta, sqlFiles: [schema] }),
      ),
    ).toEqual([]);
    expect(
      await run(
        "BS316",
        context(base, {
          configToml: toml("[db]\n"),
          sqlFiles: [{ path: "supabase/migrations/1_init.sql", text: "" }],
        }),
      ),
    ).toEqual([]);
    expect(await run("BS316", context(base, { sqlFiles: [schema] }))).toEqual(
      [],
    );
  });
});

describe("tables without an audit trigger (BS315)", () => {
  const publicTables = toCatalog(base)
    .tables.filter(
      (entry) => entry.schema === "public" && entry.kind === "table",
    )
    .map((entry) => `public.${entry.name}`);

  it("lists tables in schemas without the bsb_audit trigger", async () => {
    const audited = snapshot((tables) => {
      table(tables, "customers").triggers = [
        {
          name: "bsb_audit",
          timing: "after",
          events: ["insert", "update", "delete"],
          level: "row",
          function: "better_supabase.audit_row_change",
        },
      ];
      table(tables, "notes").triggers = [
        {
          name: "audit_notes",
          timing: "after",
          events: ["insert", "update", "delete"],
          level: "row",
          function: "better_supabase.audit_row_change",
        },
      ];
    });

    const findings = await run(
      "BS315",
      context(audited, {}, { blocks: ["audit"] }),
    );

    expect(findings.map((finding) => finding.target)).toEqual(
      publicTables.filter(
        (name) => name !== "public.customers" && name !== "public.notes",
      ),
    );
    expect(findings[0]).toMatchObject({
      severity: "warning",
      object: { kind: "table", schema: "public" },
    });
    expect(findings[0]!.message).toContain(
      "or list it in blocks.audit.options.exempt",
    );
  });

  it("skips exempt globs, adopted module tables and projects without the module", async () => {
    const [first = "", ...rest] = publicTables;
    expect(
      await run(
        "BS315",
        context(
          base,
          {},
          {
            blocks: {
              audit: {
                options: {
                  exempt: rest.map((table) => ({ table, reason: "archive" })),
                },
              },
              tenant: { ownership: "adopt", tables: { memberships: first } },
            },
          },
        ),
      ),
    ).toEqual([]);
    expect(
      await run(
        "BS315",
        context(
          base,
          {},
          {
            blocks: {
              audit: {
                options: {
                  exempt: [{ table: "public.*", reason: "scratch tables" }],
                },
              },
            },
          },
        ),
      ),
    ).toEqual([]);
    expect(await run("BS315", context(base))).toEqual([]);
  });

  it("asks for a reason when an exemption is a bare glob", async () => {
    const findings = await run(
      "BS315",
      context(
        base,
        {},
        { blocks: { audit: { options: { exempt: ["public.*"] } } } },
      ),
    );

    expect(findings).toEqual([
      expect.objectContaining({
        severity: "warning",
        target: "blocks.audit.options.exempt:public.*",
      }),
    ]);
  });
});

describe("reserved roles (BS319)", () => {
  const file = (text: string) => ({
    path: "supabase/migrations/20261006000000_roles.sql",
    text,
  });

  it("flags changes to reserved roles with their line", async () => {
    const findings = await run(
      "BS319",
      context(base, {
        sqlFiles: [
          file(`-- alter role supabase_admin nologin;
create table public.t (id int);
alter role supabase_auth_admin set search_path = 'auth';
grant supabase_storage_admin to postgres;
revoke pgbouncer
  from authenticator;
alter role authenticator nologin;
drop role if exists anon;
do $$
begin
  if true then
    alter role "dashboard_user" with password 'x';
  end if;
end $$;`),
        ],
      }),
    );

    expect(
      findings.map((finding) => [finding.location?.line, finding.message]),
    ).toEqual([
      [
        3,
        expect.stringContaining("alters the reserved role supabase_auth_admin"),
      ],
      [
        4,
        expect.stringContaining(
          "grants a membership of the reserved role supabase_storage_admin",
        ),
      ],
      [
        5,
        expect.stringContaining(
          "revokes a membership of the reserved role pgbouncer",
        ),
      ],
      [
        7,
        expect.stringContaining(
          "only `alter role authenticator set ...` is allowed",
        ),
      ],
      [8, expect.stringContaining("drops the reserved role anon")],
      [12, expect.stringContaining("alters the reserved role dashboard_user")],
    ]);
    expect(findings[0]).toMatchObject({
      severity: "error",
      target: "supabase/migrations/20261006000000_roles.sql:3",
    });
  });

  it("allows settings on the API roles and privileges granted to reserved roles", async () => {
    expect(
      await run(
        "BS319",
        context(base, {
          sqlFiles: [
            file(`do $$
begin
  if to_regprocedure('better_supabase.check_request()') is not null then
    alter role authenticator set pgrst.db_pre_request = 'better_supabase.check_request';
  end if;
end $$;
alter role authenticated in database postgres set statement_timeout = '8s';
alter role anon reset statement_timeout;
grant usage on schema auth to supabase_auth_admin;
revoke execute on function better_supabase.f() from public, anon, authenticated;
grant anon to authenticator;
comment on table public.t is 'alter role supabase_admin nologin';`),
          ],
        }),
      ),
    ).toEqual([]);
    expect(await run("BS319", context(base))).toEqual([]);
  });
});

describe("tables without the session policy (BS320)", () => {
  const rlsTables = toCatalog(base)
    .tables.filter(
      (entry) =>
        entry.schema === "public" && entry.kind === "table" && entry.rls,
    )
    .map((entry) => `public.${entry.name}`);

  it("lists RLS tables without a restrictive session_active() policy", async () => {
    const covered = snapshot((tables) => {
      // The repo's stack turns blocks.sessions.options.policies on.
      for (const entry of tables) {
        entry.policies = entry.policies.filter(
          (policy) => policy.name !== "bsb_session_active",
        );
      }

      const customers = table(tables, "customers");
      customers.policies = [
        ...customers.policies,
        {
          name: "bsb_session_active",
          command: "all",
          roles: ["authenticated"],
          permissive: false,
          using: "( SELECT better_supabase.session_active() AS session_active)",
          check: "( SELECT better_supabase.session_active() AS session_active)",
        },
      ];
      const notes = table(tables, "notes");
      notes.policies = [
        ...notes.policies,
        {
          name: "permissive_only",
          command: "all",
          roles: ["authenticated"],
          permissive: true,
          using: "better_supabase.session_active()",
          check: null,
        },
      ];
    });

    const findings = await run(
      "BS320",
      context(covered, {}, { blocks: ["sessions"] }),
    );

    expect(findings.map((finding) => finding.target)).toEqual(
      rlsTables.filter((name) => name !== "public.customers"),
    );
    expect(findings[0]).toMatchObject({
      severity: "warning",
      object: { kind: "table", schema: "public" },
    });
    expect(findings[0]!.message).toContain("blocks.sessions.options.exclude");
  });

  it("skips excluded tables and projects without the module", async () => {
    expect(
      await run(
        "BS320",
        context(
          base,
          {},
          { blocks: { sessions: { options: { exclude: ["public.*"] } } } },
        ),
      ),
    ).toEqual([]);
    expect(await run("BS320", context(base))).toEqual([]);
  });
});

describe("soft-delete columns reactions read (BS213)", () => {
  it("leaves out a subject's deletedAt column", async () => {
    const projects = (findings: readonly { target?: string }[]) =>
      findings.filter((finding) => finding.target === "public.projects");

    const bare = projects(await run("BS213", context()));
    expect(bare).toHaveLength(1);
    expect(bare[0]).toMatchObject({
      message: expect.stringContaining("authenticated may update deleted_at."),
    });

    expect(
      projects(
        await run(
          "BS213",
          context(
            base,
            {},
            {
              records: {
                project: { table: "projects", deletedAt: "deleted_at" },
              },
            },
          ),
        ),
      ),
    ).toEqual([]);
  });
});

describe("gen.functions.notNull entries a tag could replace (BS338)", () => {
  const tagged = (comments: Record<string, string>) =>
    snapshot((_tables, catalog) => {
      catalog.functions = catalog.functions.map((fn) =>
        comments[fn.name] === undefined
          ? fn
          : { ...fn, comment: comments[fn.name]! },
      );
    });

  it("suggests the tag, and reports entries that match or differ from it", async () => {
    const config = {
      gen: {
        functions: {
          customer_note_counts: { notNull: ["customer_id", "note_count"] },
          rs_workspace_summary: { notNull: true as const },
        },
      },
    };

    const untagged = await run("BS338", context(tagged({}), {}, config));

    expect(untagged.map((finding) => finding.severity)).toEqual([
      "info",
      "info",
    ]);
    expect(untagged[0]!.message).toContain(
      "add `@notNull(customer_id, note_count)` to the comment on public.customer_note_counts(p_customer_ids uuid[])",
    );

    const findings = await run(
      "BS338",
      context(
        tagged({
          customer_note_counts: "Counts. @notNull(note_count, customer_id)",
          rs_workspace_summary: "@notNull(id)",
        }),
        {},
        config,
      ),
    );

    expect(findings.map((finding) => finding.message)).toEqual([
      expect.stringContaining(
        "matches the @notNull(customer_id, note_count) tag",
      ),
      expect.stringContaining("differs from the @notNull(id) tag"),
    ]);
    expect(await run("BS338", context(tagged({}), {}, {}))).toEqual([]);
  });
});

describe("expose exclusions of missing columns (BS339)", () => {
  it("reports an excluded column the table doesn't have", async () => {
    const findings = await run(
      "BS339",
      context(
        base,
        {},
        {
          database: {
            expose: {
              notes: {
                authenticated: ["select(*, -body, -token_hash)"],
                anon: ["select(*, -token_hash)"],
              },
            },
          },
        },
      ),
    );

    expect(findings).toMatchObject([
      {
        severity: "warning",
        target: "public.notes.token_hash",
        message: expect.stringContaining('Remove "-token_hash"'),
      },
    ]);
    expect(
      await run(
        "BS339",
        context(
          base,
          {},
          { database: { expose: { gone: ["select(*, -x)"] } } },
        ),
      ),
    ).toEqual([]);
  });
});

describe("tenant foreign keys without a same-tenant trigger (BS340)", () => {
  const tenantSnapshot = (trigger: boolean) =>
    snapshot((tables) => {
      const notes = table(tables, "notes");
      const tags = table(tables, "tags");
      const tenant = { ...notes.columns[0]!, name: "organization_id" };

      for (const entry of [notes, tags]) {
        entry.columns = [
          ...entry.columns.filter(
            (column) => column.name !== "organization_id",
          ),
          tenant,
        ];
      }

      notes.columns = [...notes.columns, { ...tenant, name: "tag_id" }];
      notes.foreignKeys = [
        {
          name: "notes_tag_id_fkey",
          columns: ["tag_id"],
          refSchema: "public",
          refTable: "tags",
          refColumns: ["id"],
          oneToOne: false,
          onDelete: "no action",
          onUpdate: "no action",
        },
      ];
      notes.triggers = trigger
        ? [
            {
              name: "bsb_same_tenant_tag_id",
              timing: "before",
              events: ["insert", "update"],
              level: "row",
              function: "better_supabase.same_tenant",
            },
          ]
        : [];
    });

  const notes = (findings: readonly { readonly target?: string }[]) =>
    findings.filter((finding) => finding.target === "public.notes.tag_id");

  it("lists a key between two tenant tables without the trigger", async () => {
    const findings = await run(
      "BS340",
      context(tenantSnapshot(false), {}, { blocks: ["tenant"] }),
    );

    expect(notes(findings)).toMatchObject([
      {
        severity: "info",
        message: expect.stringContaining(
          "public.notes.tag_id references public.tags, and both have organization_id",
        ),
      },
    ]);
  });

  it("passes with the trigger, or without the tenant block", async () => {
    expect(
      notes(
        await run(
          "BS340",
          context(tenantSnapshot(true), {}, { blocks: ["tenant"] }),
        ),
      ),
    ).toEqual([]);
    expect(await run("BS340", context(tenantSnapshot(false)))).toEqual([]);
  });
});

describe("secret columns in data exports (BS341)", () => {
  const secrets = snapshot((tables) => {
    for (const name of ["notes", "tags"]) {
      const entry = table(tables, name);
      const text = { ...entry.columns[0]!, udt: "text", type: "text" };

      entry.columns = [
        ...entry.columns.filter((column) => column.name !== "organization_id"),
        { ...text, name: "organization_id" },
        { ...text, name: "api_key" },
        { ...text, name: "Password" },
      ];
    }
  });

  const lifecycle = (options: Readonly<Record<string, unknown>>) =>
    context(secrets, {}, { blocks: { "data-lifecycle": { options } } });

  const targets = (findings: readonly { readonly target?: string }[]) =>
    findings
      .map((finding) => finding.target)
      .filter((target) => /^public\.(notes|tags)\./.test(target ?? ""));

  it("reports secret-looking columns of listed and auto tables", async () => {
    const findings = await run(
      "BS341",
      lifecycle({
        tables: { notes: { tenant: "organization_id", omit: ["api_key"] } },
        autoTables: { schemas: ["public"] },
      }),
    );

    expect(targets(findings)).toEqual([
      "public.notes.Password",
      "public.tags.api_key",
      "public.tags.Password",
    ]);
    expect(findings[0]).toMatchObject({ severity: "warning" });
  });

  it("passes with omitPattern, an excluded table, or no export", async () => {
    expect(
      targets(
        await run(
          "BS341",
          lifecycle({ autoTables: { schemas: ["public"] }, omitPattern: true }),
        ),
      ),
    ).toEqual([]);
    expect(
      targets(
        await run(
          "BS341",
          lifecycle({
            tables: { notes: { tenant: "organization_id", export: false } },
            autoTables: { schemas: ["public"], exclude: ["public.tags"] },
          }),
        ),
      ),
    ).toEqual([]);
    expect(await run("BS341", context(secrets))).toEqual([]);
  });

  it("checks listed tables without autoTables and skips tables the snapshot lacks", async () => {
    expect(
      targets(
        await run(
          "BS341",
          lifecycle({
            tables: {
              tags: { tenant: "organization_id" },
              gone: { tenant: "organization_id" },
            },
            omitPattern: "(",
          }),
        ),
      ),
    ).toEqual(["public.tags.api_key", "public.tags.Password"]);
  });
});

describe("whole-row broadcast triggers (BS337)", () => {
  const trigger = (source: string, comment?: string) => ({
    name: "bsb_broadcast_org",
    timing: "after" as const,
    events: ["insert" as const],
    level: "row" as const,
    function: "better_supabase.bsb_broadcast_org_public_notes",
    source,
    ...(comment === undefined ? {} : { comment }),
  });

  it("reports broadcast_changes with new and old, and old_record sends", async () => {
    const snap = snapshot((tables) => {
      table(tables, "notes").triggers = [
        trigger(
          "begin perform realtime.broadcast_changes(topic, tg_op, tg_op, tg_table_name, tg_table_schema, new, old); return null; end;",
        ),
      ];
      table(tables, "tags").triggers = [
        {
          ...trigger(
            "begin perform realtime.send(jsonb_build_object('old_record', old, 'record', new), tg_op, 't', true); end;",
          ),
          name: "bsb_broadcast_tags",
        },
      ];
    });

    expect(await run("BS337", context(snap))).toMatchObject([
      {
        target: "public.notes.bsb_broadcast_org",
        message: expect.stringContaining('pass `payload: "row"`'),
      },
      { target: "public.tags.bsb_broadcast_tags" },
    ]);
  });

  it("passes key payloads, marked row payloads and commented-out calls", async () => {
    const snap = snapshot((tables) => {
      table(tables, "notes").triggers = [
        trigger(
          "begin perform realtime.send(jsonb_build_object('id', 1, 'values', vals), tg_op, 't', true); end;",
        ),
        trigger(
          "begin perform realtime.send(jsonb_build_object('old_record', old, 'record', new), tg_op, 't', true); end;",
          "better-supabase: payload row",
        ),
        trigger(
          "begin\n-- realtime.broadcast_changes(topic, tg_op, tg_op, t, s, new, old)\nreturn null; end;",
        ),
        {
          name: "bsb_broadcast_topic",
          timing: "after",
          events: ["insert"],
          level: "row",
          function: "better_supabase.broadcast_topic",
          args: ["t:{id}", "", "", "row"],
        },
      ];
    });

    expect(await run("BS337", context(snap))).toEqual([]);
  });
});

describe("realtime and auth.users (BS305, BS306, BS406)", () => {
  it("passes tables with a broadcast trigger and keyed replica identity", async () => {
    const snap = snapshot((tables, catalog) => {
      table(tables, "notes").triggers = [
        {
          name: "bsb_realtime_notes",
          timing: "after",
          events: ["insert"],
          level: "statement",
          function: "better_supabase.broadcast_changes",
        },
      ];
      catalog.realtime = ["public.notes", "public.tags"];
      table(tables, "tags").primaryKey = [];
      table(tables, "notes").replicaIdentity = "FULL";
    });

    expect(
      await run(
        "BS305",
        context(snap, {}, { database: { realtime: { tables: ["notes"] } } }),
      ),
    ).toEqual([]);
    expect(await run("BS306", context(snap))).toMatchObject([
      {
        target: "public.tags",
        message: expect.stringContaining(
          "replica identity default and no primary key",
        ),
      },
    ]);
  });

  it("names an unknown replica identity", async () => {
    const snap = snapshot((tables, catalog) => {
      catalog.realtime = ["public.tags"];
      table(tables, "tags").replicaIdentity = "NOTHING";
    });

    expect((await run("BS306", context(snap)))[0]!.message).toBe(
      "public.tags is published to Realtime with replica identity nothing. Add a primary key or run `alter table public.tags replica identity full`.",
    );
  });

  it("leaves foreign keys inside the auth schema alone", async () => {
    const snap = snapshot((tables) => {
      const sessions = structuredClone(table(tables, "tags"));
      sessions.schema = "auth";
      sessions.name = "sessions";
      sessions.foreignKeys = [
        {
          name: "sessions_user_id_fkey",
          columns: ["user_id"],
          refSchema: "auth",
          refTable: "users",
          refColumns: ["id"],
          oneToOne: false,
          onDelete: "no action",
          onUpdate: "no action",
        },
      ];
      tables.push(sessions);
    });

    expect(await run("BS406", context(snap))).toEqual([]);
  });
});

describe("config.toml auth settings (BS401, BS402, BS403)", () => {
  it("passes without config.toml or with rotation off", async () => {
    for (const code of ["BS401", "BS402", "BS403"]) {
      expect(await run(code, context())).toEqual([]);
    }

    expect(
      await run(
        "BS401",
        context(base, {
          configToml: toml(
            "[auth]\nenable_refresh_token_rotation = false\nrefresh_token_reuse_interval = 0\n",
          ),
        }),
      ),
    ).toEqual([]);
    expect(
      await run("BS401", context(base, { configToml: toml("[auth]\n") })),
    ).toEqual([]);
  });

  it("reports without a location when config.toml has no [auth] table", async () => {
    const findings = await runRules(
      context(base, { configToml: toml("[db]\nport = 1\n") }),
      RULES.filter((rule) => rule.code === "BS403"),
    );

    expect(findings).toHaveLength(1);
    expect(findings[0]).not.toHaveProperty("location");
    expect(
      await run(
        "BS403",
        context(base, { configToml: toml('[db]\ndriver = "pglite"\n') }),
      ),
    ).toEqual([]);
    const nested = toml("[auth]\njwt_expiry = 7200\n");
    expect(
      (await run("BS402", context(base, { configToml: nested })))[0]!.location,
    ).toEqual({ file: "supabase/config.toml", line: 2 });
  });
});

describe("env files (BS501, BS502)", () => {
  it("flags service role keys by name and honours rooted ignore patterns", async () => {
    const envFiles = [
      {
        path: ".env.local",
        text: "export VITE_SERVICE_ROLE_KEY='abc'\n# note\n",
      },
      { path: "apps/web/.env", text: "SUPABASE_SECRET_KEY=sb_secret_x\n" },
    ];

    const findings = await runRules(
      context(base, { envFiles, gitignore: "/apps/web/.env\n" }),
      RULES.filter((rule) => ["BS501", "BS502"].includes(rule.code)),
    );

    expect(findings.map((finding) => [finding.code, finding.target])).toEqual([
      ["BS501", ".env.local:VITE_SERVICE_ROLE_KEY"],
      ["BS502", ".env.local"],
    ]);
  });
});

describe("peer versions (BS601)", () => {
  it("flags installed peers outside their range and skips the rest", async () => {
    const peers = [
      {
        name: "@supabase/postgrest-typegen",
        range: ">=0.4.0 <0.5",
        installed: "0.5.0",
      },
      {
        name: "@modelcontextprotocol/server",
        range: ">=2.3.0 <3",
        installed: "2.3.1",
      },
      { name: "hono", range: ">=4 <5", installed: undefined },
      { name: "eve", range: ">=0.71 <1", installed: "canary" },
    ];

    const findings = await run("BS601", context(base, { peers }));
    expect(findings).toEqual([
      expect.objectContaining({
        code: "BS601",
        target: "@supabase/postgrest-typegen",
        message:
          "@supabase/postgrest-typegen@0.5.0 is installed, but better-supabase needs >=0.4.0 <0.5. Install a version in that range, or remove @supabase/postgrest-typegen if nothing imports it.",
      }),
    ]);
    expect(await run("BS601", context(base))).toEqual([]);
  });
});

describe("Supabase Lite gaps (BS328, BS329)", () => {
  const lite = (driver: string) => toml(`[db]\ndriver = "${driver}"\n`);

  const rpc = {
    path: "src/actions.ts",
    text: 'import { bsb } from "./bsb";\n\nawait bsb.$rpc("note_count");',
  };

  const realtime = {
    path: "src/live.ts",
    text: 'const channel = supabase.channel("notes");',
  };

  const invoke = {
    path: "src/send.ts",
    text: 'await supabase.functions.invoke("send");',
  };

  it("reports rpc() only on the SQLite drivers", async () => {
    expect(
      await run(
        "BS328",
        context(base, { configToml: lite("sqlite-postgres"), sources: [rpc] }),
      ),
    ).toMatchObject([
      {
        code: "BS328",
        target: "src/actions.ts:rpc",
        location: { file: "src/actions.ts", line: 3 },
      },
    ]);

    for (const configToml of [lite("pglite"), toml("[db]\nport = 1\n")]) {
      expect(
        await run("BS328", context(base, { configToml, sources: [rpc] })),
      ).toEqual([]);
    }
  });

  it("reports Realtime and Edge Functions on any Lite driver", async () => {
    const findings = await run(
      "BS329",
      context(base, {
        configToml: lite("pglite"),
        sources: [realtime, invoke, rpc],
      }),
    );

    expect(findings.map((finding) => finding.target)).toEqual([
      "src/live.ts:Realtime",
      "src/send.ts:Edge Functions",
    ]);
    expect(
      await run(
        "BS329",
        context(base, { configToml: lite("mysql"), sources: [realtime] }),
      ),
    ).toEqual([]);
    expect(await run("BS329", context(base, { sources: [realtime] }))).toEqual(
      [],
    );
  });
});

describe("session cookie encoding (BS412)", () => {
  const browser = (encode?: string) => ({
    path: "src/lib/client.ts",
    text: `import { createClient } from "better-supabase/client";\nexport const bsb = createClient(betterSupabase, {\n  env,${encode ? `\n  cookies: { encode: "${encode}" },` : ""}\n});`,
  });

  const server = (encode?: string) => ({
    path: "src/lib/server.ts",
    text: `import { createServer } from "better-supabase/server";\nexport const server = createServer(betterSupabase, { env${encode ? `, encode: '${encode}'` : ""} });`,
  });

  const shared = {
    path: "src/lib/both.ts",
    text: `import "better-supabase/client";\nimport { createServerClient } from "@supabase/ssr";\ncreateServerClient(url, key, { cookies: { encode: "tokens-only" } });`,
  };

  it("passes matching encodings and sources that never set tokens-only", async () => {
    for (const sources of [
      [browser(), server()],
      [browser("tokens-only"), server("tokens-only")],
      [browser("tokens-only")],
      [browser("tokens-only"), shared],
      [{ path: "a.ts", text: 'const encode: "tokens-only" = x;' }],
    ]) {
      expect(await run("BS412", context(base, { sources }))).toEqual([]);
    }
  });

  it("reports the side that sets tokens-only when the other side doesn't", async () => {
    const browserOnly = await run(
      "BS412",
      context(base, { sources: [browser("tokens-only"), server()] }),
    );

    expect(browserOnly).toMatchObject([
      {
        code: "BS412",
        severity: "info",
        target: "src/lib/client.ts:encode",
        location: { file: "src/lib/client.ts", line: 4 },
      },
    ]);
    expect(browserOnly[0]!.message).toContain(
      "the server side (src/lib/server.ts) uses the default `user-and-tokens`",
    );

    const serverOnly = await run(
      "BS412",
      context(base, {
        sources: [
          browser(),
          server("tokens-only"),
          {
            path: "src/ssr.ts",
            text: 'import { createBrowserClient } from "@supabase/ssr";\ncreateBrowserClient(url, key);',
          },
        ],
      }),
    );

    expect(serverOnly.map((finding) => finding.target)).toEqual([
      "src/lib/server.ts:encode",
    ]);
    expect(serverOnly[0]!.message).toContain(
      "the browser side (src/lib/client.ts, src/ssr.ts)",
    );
  });
});

describe("pg-delta schema files (BS317, BS318, BS321)", () => {
  const pgdelta = toml("[experimental.pgdelta]\nenabled = true\n");

  const file = (text: string, path = "supabase/schemas/090_grants.sql") => ({
    path,
    text,
  });

  it("flags bulk grants with their line, and only under pg-delta", async () => {
    const grants = file(
      [
        "-- grant all on all tables in schema public to anon;",
        "revoke execute on function public.f() from anon;",
        "grant execute on all functions in schema public to anon, authenticated;",
        "/* grant select on all sequences in schema x to anon; */",
        "GRANT SELECT ON ALL TABLES IN SCHEMA public, app TO authenticated;",
        "alter default privileges in schema public grant select on tables to authenticated;",
        "grant all on all tables in schema public to service_role;",
      ].join("\n"),
    );

    const findings = await run(
      "BS317",
      context(base, { configToml: pgdelta, sqlFiles: [grants] }),
    );

    expect(findings.map((finding) => finding.location?.line)).toEqual([3, 5]);
    expect(findings[0]).toMatchObject({
      severity: "warning",
      target: "supabase/schemas/090_grants.sql",
    });
    expect(findings[0]!.message).toContain("all functions in schema public");
    expect(findings[1]!.message).toContain("all tables in schema public, app");
    expect(findings[0]!.message).toContain("alter default privileges");
    expect(
      await run(
        "BS317",
        context(base, { configToml: toml("[db]\n"), sqlFiles: [grants] }),
      ),
    ).toEqual([]);
    expect(
      await run(
        "BS317",
        context(base, {
          configToml: pgdelta,
          sqlFiles: [
            file(grants.text, "supabase/migrations/1_init.sql"),
            file(`-- @bsb-block grants@1 managed\n${grants.text}`),
          ],
        }),
      ),
    ).toEqual([]);
    expect(await run("BS317", context(base, { sqlFiles: [grants] }))).toEqual(
      [],
    );
  });

  it("flags do blocks that loop over the catalog", async () => {
    const loop = file(
      [
        "create table t (id int);",
        "do $$",
        "declare r record;",
        "begin",
        "  for r in select table_name from information_schema.tables where table_schema = 'public' loop",
        "    execute format('create trigger audit after update on %I for each row execute function audit()', r.table_name);",
        "  end loop;",
        "end $$;",
        "do $body$ begin perform 1; end $body$;",
        "do $$ begin if exists (select 1 from pg_class) then raise notice 'x'; end if; end $$;",
        "do $x$ begin perform pg_catalog.pg_sleep(0); execute 'select 1' using (select 1 from pg_tables); end $x$;",
      ].join("\n"),
      "supabase/schemas/030_triggers.sql",
    );

    const findings = await run(
      "BS318",
      context(base, { configToml: pgdelta, sqlFiles: [loop] }),
    );

    expect(findings.map((finding) => finding.location?.line)).toEqual([2, 11]);
    expect(findings[0]!.message).toContain("reads information_schema.tables");
    expect(findings[0]!.message).toContain("better_supabase.audit");
    expect(
      await run(
        "BS318",
        context(base, { configToml: toml("[db]\n"), sqlFiles: [loop] }),
      ),
    ).toEqual([]);
  });

  it("flags extensions the schema files create that no migration does", async () => {
    const jobs = file(
      "-- @bsb-block jobs@4 managed\ncreate extension if not exists pgmq;\ncreate extension if not exists vector with schema extensions;\nraise exception 'needs pg_cron: create extension pg_cron with schema pg_catalog';",
      "supabase/schemas/900_better_supabase_07_jobs.sql",
    );

    const own = file(
      '-- create extension pg_cron;\nCREATE EXTENSION "pg_cron" WITH SCHEMA pg_catalog;\ncreate extension pgmq;',
      "supabase/schemas/010_extensions.sql",
    );

    const migration = file(
      'create extension if not exists "vector" with schema "extensions";',
      "supabase/migrations/20260101000000_init.sql",
    );

    const findings = await run(
      "BS321",
      context(base, { configToml: pgdelta, sqlFiles: [jobs, own, migration] }),
    );

    expect(
      findings.map((finding) => [finding.target, finding.location?.line]),
    ).toEqual([
      ["supabase/schemas/900_better_supabase_07_jobs.sql", 2],
      ["supabase/schemas/010_extensions.sql", 2],
    ]);
    expect(findings[0]!.message).toContain("better-supabase upgrade");
    expect(findings[1]!.message).toContain(
      "create extension if not exists pg_cron;",
    );

    const data = file(
      '-- @bsb-block-data jobs\ncreate extension if not exists "pgmq";\ncreate extension if not exists pg_cron;',
      "supabase/migrations/20260101000001_better_supabase_module_data.sql",
    );

    expect(
      await run(
        "BS321",
        context(base, {
          configToml: pgdelta,
          sqlFiles: [jobs, own, migration, data],
        }),
      ),
    ).toEqual([]);
    expect(
      await run(
        "BS321",
        context(base, { configToml: pgdelta, sqlFiles: [jobs] }),
      ),
    ).toEqual([]);
    expect(
      await run(
        "BS321",
        context(base, {
          configToml: toml("[db]\n"),
          sqlFiles: [jobs, migration],
        }),
      ),
    ).toEqual([]);
  });
});
