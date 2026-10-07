import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { AdvisorSource, Lint } from "../../../src/cli/doctor/advisors.ts";
import type {
  Catalog,
  CatalogTable,
  Snapshot,
} from "../../../src/cli/introspect/types.ts";

import { renderFiles } from "../../../src/cli/commands/gen.ts";
import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import {
  type DoctorContext,
  RULES,
  runRules,
} from "../../../src/cli/doctor/rules.ts";
import { toCatalog } from "../../../src/cli/introspect/catalog.ts";
import { fromCatalog } from "../../../src/cli/introspect/from-catalog.ts";
import { parseToml } from "../../../src/cli/supabase-toml.ts";
import {
  type BetterSupabaseConfig,
  resolveConfig,
} from "../../../src/config/index.ts";
import { renderModules } from "../../../src/sql/index.ts";
import { moduleLayout } from "../../../src/sql/index.ts";
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
      {
        message: "The performance advisor could not run (splinter): offline",
      },
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
        policy("tags_read", "select", null, {
          check: "org_id = 1",
        }),
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
      context(snap, {}, { tables: { tags: { exclude: true } } }),
    );
    expect(excluded.map((finding) => finding.target)).toEqual(["public.notes"]);
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
    buckets: {
      docs: {
        path: "{organizationId}/{file}",
        public: false,
        fileSizeLimit: "1KiB",
        allowedMimeTypes: ["application/pdf"],
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
      buckets: {
        docs: {
          ...config.buckets!["docs"]!,
          versioning: true,
          lifecycle: {
            rules: [{ noncurrentVersionExpiration: { noncurrentDays: 30 } }],
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

  it("renders api-keys scopes from PermDock's catalog, and skips without one", async () => {
    const config: BetterSupabaseConfig = {
      sql: {
        modules: { "api-keys": { options: { scopes: "catalog" } } },
      },
    };
    const withCatalog: DoctorContext = {
      ...rooted(config),
      permdock: {
        manifestPath: "permdock.manifest.json",
        catalogPath: "permissions.catalog.json",
        catalog: {
          permissions: [{ key: "deals.read", rowConditions: false }],
        },
        problems: [],
      },
    };
    const missing = await run("BS304", withCatalog);
    expect(missing.map((finding) => finding.target)).toContain(
      "supabase/schemas/900_better_supabase_28_api_keys.sql",
    );
    expect(await run("BS304", rooted(config))).toEqual([]);
    const catalogOnly = await run("BS304", {
      ...rooted(config),
      permissionCatalog: ["deals.read"],
    });
    expect(catalogOnly.map((finding) => finding.target)).toContain(
      "supabase/schemas/900_better_supabase_28_api_keys.sql",
    );
  });

  it("checks the SQL modules in sql.modules", async () => {
    expect(await run("BS304", rooted())).toEqual([]);
    const ctx = rooted({ sql: { modules: ["updated-at", "audit"] } });
    const files = renderModules(
      ctx.config.sql.moduleNames,
      moduleLayout(ctx.config),
    );
    const missing = await run("BS304", ctx);
    expect(missing.map((finding) => finding.target)).toEqual(
      files.map((file) => file.path),
    );
    expect(missing[0]!.message).toMatch(/\(updated-at\) is missing\./);
    expect(missing[0]!.message).toContain("then `supabase db diff`.");
    const pgdelta = await run("BS304", {
      ...ctx,
      configToml: toml("[experimental.pgdelta]\nenabled = true\n"),
    });
    expect(pgdelta[0]!.message).toContain(
      "then `supabase db schema declarative sync`.",
    );

    const data = files.find((file) => file.kind === "data")!;
    expect(
      missing.find((finding) => finding.target === data.path)!.message,
    ).toContain("which also writes the rows into a migration");

    const audit = files.find(
      (file) => file.module === "audit" && file.kind === "schema",
    );
    for (const file of files) await write(file.path, file.contents);
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

  it("reports a module behind its version in BS311, not BS304", async () => {
    const ctx = rooted({ sql: { modules: ["tenant"] } });
    const files = renderModules(["tenant"], moduleLayout(ctx.config));
    for (const module of files) await write(module.path, module.contents);
    const file = files.find(
      (module) => module.module === "tenant" && module.kind === "schema",
    );
    await write(file!.path, file!.contents.replace(/^-- @bs-module .*\n/m, ""));
    expect(await run("BS304", ctx)).toEqual([]);
    expect(await run("BS311", ctx)).toEqual([
      expect.objectContaining({
        severity: "warning",
        target: file!.path,
        message: expect.stringContaining(
          "has tenant version 1; this release ships version 2. Run `better-supabase sql upgrade`",
        ),
      }),
    ]);
    await write(file!.path, file!.contents);
    expect(await run("BS311", ctx)).toEqual([]);
  });

  it("reads modules on a live database in BS311", async () => {
    const ctx = rooted({ sql: { modules: ["tenant", "mfa"] } });
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
        target: "better_supabase.modules.tenant",
        message: expect.stringContaining(
          "The database has tenant version 1; this release ships version 2.",
        ),
      }),
    ]);
    expect(await run("BS311", live(new Error("no table")))).toEqual([]);
  });

  it("skips the read-sets module when the read sets could not be loaded", async () => {
    const ctx = rooted({ sql: { modules: ["read-sets"] } });
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
      renderModules(["read-sets"], moduleLayout(ctx.config)).map(
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
              text: "-- @bs-module tenant@2 managed\nselect better_supabase.current_org_id();",
            },
          ],
        },
        { sql: { modules: ["tenant"] } },
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
          { sql: { modules: ["tenant"] }, claims: { tenant: "org_id" } },
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
      context(snap, { sqlFiles }, { sql: { modules: ["tenant"] } }),
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
          {
            sql: { modules: { tenant: { mode: "adopt" } } },
          },
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
        trigger("bs_updated_at", "better_supabase.set_updated_at"),
        trigger("handle_updated_at", "extensions.moddatetime"),
        trigger("bs_audit", "better_supabase.audit_trigger"),
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
        {
          sql: { modules: { tenant: {}, audit: { schema: "crm" } } },
        },
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
            sql: { modules: ["tenant"] },
            schemas: ["public", "better_supabase"],
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
            sql: { modules: ["tenant"] },
            schemas: ["public", "better_supabase"],
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
    ...context(base, {}, { sql: { modules: module } }),
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
    ])
      expect(await run("BS313", live(["rate-limit"], [row]))).toEqual([]);
    expect(
      await run("BS313", live(["tenant"], [{ hook: null, calls: false }])),
    ).toEqual([]);
    expect(
      await run("BS313", live(["rate-limit"], new Error("denied"))),
    ).toEqual([]);
    expect(
      await run(
        "BS313",
        context(base, {}, { sql: { modules: ["rate-limit"] } }),
      ),
    ).toEqual([]);
  });
});

describe("audit registrations of dropped tables (BS322)", () => {
  const live = (
    module: string[],
    rows: Record<string, unknown>[] | Error,
  ): Parameters<typeof run>[1] => ({
    ...context(base, {}, { sql: { modules: module } }),
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
      await run("BS322", context(base, {}, { sql: { modules: ["audit"] } })),
    ).toEqual([]);
  });
});

describe("module event triggers (BS323)", () => {
  const modules = { sql: { modules: ["audit", "ensure-rls", "tenant"] } };
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
      context(base, { database: live([{ name: "bs_ensure_rls" }]) }, modules),
    );
    expect(findings).toEqual([
      expect.objectContaining({
        severity: "warning",
        target: "bs_audit_forget_dropped",
        message: expect.stringContaining(
          "The database has no event trigger bs_audit_forget_dropped, which the audit module creates.",
        ),
      }),
    ]);
    expect(findings[0]!.message).toContain("better-supabase sql data");
    expect(
      await run(
        "BS323",
        context(
          base,
          {
            database: live([
              { name: "bs_ensure_rls" },
              { name: "bs_audit_forget_dropped" },
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
              text: "create event trigger bs_audit_forget_dropped on sql_drop execute function f();",
            },
            migration(
              'create event trigger "bs_ensure_rls" on ddl_command_end execute function g();',
            ),
          ],
        },
        modules,
      ),
    );
    expect(findings.map((finding) => finding.target)).toEqual([
      "bs_audit_forget_dropped",
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
        context(base, { database: live([]) }, { sql: { modules: ["tenant"] } }),
      ),
    ).toEqual([]);
  });
});

describe("migration-only module options (BS314)", () => {
  it("warns about each weakening option on a module in sql.modules", async () => {
    const findings = await run(
      "BS314",
      context(
        base,
        {},
        {
          sql: {
            modules: {
              invitations: {
                mode: "adopt",
                options: { tokenStorage: "plain" },
              },
              outbox: {
                mode: "adopt",
                options: {
                  blockSource: "better-supabase/{module}",
                  defaultSource: "domain",
                },
              },
            },
          },
        },
      ),
    );
    expect(findings).toEqual([
      expect.objectContaining({
        severity: "warning",
        target: "sql.modules.invitations.options.tokenStorage",
      }),
      expect.objectContaining({
        target: "sql.modules.outbox.options.defaultSource",
      }),
    ]);
    expect(findings[0]!.message).toBe(
      'sql.modules.invitations.options.tokenStorage is "plain". It stores invitation tokens in plain text instead of their SHA-256 hash. It exists to adopt an existing schema; remove it once your data matches the managed default.',
    );
  });

  it("is quiet for managed defaults", async () => {
    expect(
      await run(
        "BS314",
        context(
          base,
          {},
          {
            sql: {
              modules: { invitations: { options: { tokenStorage: "sha256" } } },
            },
          },
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
        context(
          base,
          { configToml: toml("[db]\n") },
          { sql: { modules: ["audit"] } },
        ),
      ),
    ).toHaveLength(1);
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

  it("lists tables in schemas without the bs_audit trigger", async () => {
    const audited = snapshot((tables) => {
      table(tables, "customers").triggers = [
        {
          name: "bs_audit",
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
      context(audited, {}, { sql: { modules: ["audit"] } }),
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
      "or list it in sql.modules.audit.options.exempt",
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
            sql: {
              modules: {
                audit: { options: { exempt: rest } },
                tenant: { mode: "adopt", tables: { memberships: first } },
              },
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
            sql: { modules: { audit: { options: { exempt: ["public.*"] } } } },
          },
        ),
      ),
    ).toEqual([]);
    expect(await run("BS315", context(base))).toEqual([]);
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
      const customers = table(tables, "customers");
      customers.policies = [
        ...customers.policies,
        {
          name: "bs_session_active",
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
      context(covered, {}, { sql: { modules: ["sessions"] } }),
    );
    expect(findings.map((finding) => finding.target)).toEqual(
      rlsTables.filter((name) => name !== "public.customers"),
    );
    expect(findings[0]).toMatchObject({
      severity: "warning",
      object: { kind: "table", schema: "public" },
    });
    expect(findings[0]!.message).toContain(
      "sql.modules.sessions.options.exclude",
    );
  });

  it("skips excluded tables and projects without the module", async () => {
    expect(
      await run(
        "BS320",
        context(
          base,
          {},
          {
            sql: {
              modules: { sessions: { options: { exclude: ["public.*"] } } },
            },
          },
        ),
      ),
    ).toEqual([]);
    expect(await run("BS320", context(base))).toEqual([]);
  });
});

describe("realtime and auth.users (BS305, BS306, BS406)", () => {
  it("passes tables with a broadcast trigger and keyed replica identity", async () => {
    const snap = snapshot((tables, catalog) => {
      table(tables, "notes").triggers = [
        {
          name: "bs_realtime_notes",
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
        context(snap, {}, { realtime: { tables: ["notes"] } }),
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
      context(base, {
        configToml: toml("[db]\nport = 1\n"),
      }),
      RULES.filter((rule) => rule.code === "BS403"),
    );
    expect(findings).toHaveLength(1);
    expect(findings[0]).not.toHaveProperty("location");
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

describe("session cookie encoding (BS412)", () => {
  const browser = (encode?: string) => ({
    path: "src/lib/client.ts",
    text: `import { createClient } from "better-supabase/client";\nexport const bs = createClient(betterSupabase, {\n  env,${encode ? `\n  cookies: { encode: "${encode}" },` : ""}\n});`,
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
            file(`-- @bs-module grants@1 managed\n${grants.text}`),
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
      "-- @bs-module jobs@4 managed\ncreate extension if not exists pgmq;\ncreate extension if not exists vector with schema extensions;",
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
      context(base, {
        configToml: pgdelta,
        sqlFiles: [jobs, own, migration],
      }),
    );
    expect(
      findings.map((finding) => [finding.target, finding.location?.line]),
    ).toEqual([
      ["supabase/schemas/900_better_supabase_07_jobs.sql", 2],
      ["supabase/schemas/010_extensions.sql", 2],
    ]);
    expect(findings[0]!.message).toContain("better-supabase sql sync");
    expect(findings[1]!.message).toContain(
      "create extension if not exists pg_cron;",
    );
    const data = file(
      '-- @bs-module-data jobs\ncreate extension if not exists "pgmq";\ncreate extension if not exists pg_cron;',
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
