import {
  type BetterSupabaseConfig,
  resolveConfig,
} from "better-supabase/config";
import { renderKit } from "better-supabase/sql";
import { kitLayout } from "better-supabase/sql";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { AdvisorSource, Lint } from "../../src/doctor/advisors.ts";
import type {
  Catalog,
  CatalogTable,
  Snapshot,
} from "../../src/introspect/types.ts";

import { renderFiles } from "../../src/commands/gen.ts";
import { parseSnapshot } from "../../src/commands/snapshot.ts";
import { type DoctorContext, RULES, runRules } from "../../src/doctor/rules.ts";
import { toCatalog } from "../../src/introspect/catalog.ts";
import { fromCatalog } from "../../src/introspect/from-catalog.ts";
import { parseToml } from "../../src/supabase-toml.ts";
import { snapshotFixture as fixture } from "../fixtures/library.ts";

const base = parseSnapshot(fixture);

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

  it("keeps splinter's overlap lint when BS207 has nothing for that table", async () => {
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
        policy("locations_read", "select", "is_member(org)", {
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
        path: "{orgId}/{file}",
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
});

describe("generated and kit files (BS303, BS304)", () => {
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

  it("checks the SQL kit modules in sql.kit", async () => {
    expect(await run("BS304", rooted())).toEqual([]);
    const ctx = rooted({ sql: { kit: ["updated-at", "audit"] } });
    const files = renderKit(ctx.config.sql.kit, kitLayout(ctx.config));
    const missing = await run("BS304", ctx);
    expect(missing.map((finding) => finding.target)).toEqual(
      files.map((file) => file.path),
    );
    expect(missing[0]!.message).toMatch(/\(updated-at\) is missing\./);

    await write(files[0]!.path, files[0]!.contents);
    await write(files[1]!.path, "-- changed\n");
    expect(await run("BS304", ctx)).toEqual([
      expect.objectContaining({
        target: files[1]!.path,
        message: expect.stringContaining("(audit) is out of date"),
        location: { file: files[1]!.path, line: 1 },
      }),
    ]);
  });

  it("skips the read-sets module when the read sets could not be loaded", async () => {
    const ctx = rooted({ sql: { kit: ["read-sets"] } });
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
      renderKit(["read-sets"], kitLayout(ctx.config)).map((file) => file.path),
    );
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
