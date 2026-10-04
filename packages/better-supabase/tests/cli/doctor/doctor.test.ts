import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { AdvisorSource, Lint } from "../../../src/cli/doctor/advisors.ts";
import type { LiveDatabase } from "../../../src/cli/doctor/live.ts";
import type {
  Catalog,
  CatalogFunction,
  CatalogTable,
  ExtrasFunction,
  ExtrasHookFunction,
  Snapshot,
} from "../../../src/cli/introspect/types.ts";
import type { PermdockProject } from "../../../src/cli/permdock.ts";

import { locate } from "../../../src/cli/commands/doctor.ts";
import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import { formatReport } from "../../../src/cli/doctor/format.ts";
import {
  hookGrantBlock,
  hookGrantProblems,
} from "../../../src/cli/doctor/hooks.ts";
import { summarizePlan } from "../../../src/cli/doctor/live.ts";
import {
  type DoctorContext,
  RULE_CODES,
  RULES,
  runRules,
} from "../../../src/cli/doctor/rules.ts";
import { toCatalog } from "../../../src/cli/introspect/catalog.ts";
import { fromCatalog } from "../../../src/cli/introspect/from-catalog.ts";
import { parseManifest } from "../../../src/cli/permdock.ts";
import { run } from "../../../src/cli/run.ts";
import {
  parseToml,
  pgFunctionHooks,
  type SupabaseToml,
} from "../../../src/cli/supabase-toml.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { kitPermissionKeys, SQL_MODULES } from "../../../src/sql/index.ts";
import { kitSnapshotFixture as fixture } from "../fixtures/library.ts";
import manifest from "../fixtures/permdock.manifest.json" with { type: "json" };

const base = await parseSnapshot(fixture);

const PERMDOCK: PermdockProject = {
  config: "permdock.config.ts",
  manifestPath: "permdock.manifest.json",
  manifest: { version: 1, claims: [], memberships: [], decidingColumns: [] },
  catalogPath: "permissions.catalog.json",
  problems: [],
};

const toml = (text: string): SupabaseToml => ({
  path: "supabase/config.toml",
  text,
  document: parseToml(text),
  parser: "smol-toml",
});

function snapshot(
  change: (tables: CatalogTable[], functions: CatalogFunction[]) => void,
): Snapshot {
  const copy = structuredClone(toCatalog(base)) as {
    -readonly [K in keyof Catalog]: Catalog[K];
  };
  const tables = copy.tables as CatalogTable[];
  const functions = copy.functions as CatalogFunction[];
  change(tables, functions);
  return fromCatalog(copy);
}

const edit = <T>(value: T): { -readonly [K in keyof T]: T[K] } => value;
const table = (tables: CatalogTable[], name: string) =>
  edit(tables.find((entry) => entry.name === name)!);

function context(
  snap: Snapshot,
  extra: Partial<DoctorContext> = {},
): DoctorContext {
  return {
    config: resolveConfig(
      { plugins: { tenant: true, softDelete: { column: "archived_at" } } },
      "/project",
    ),
    snapshot: snap,
    configToml: undefined,
    envFiles: [],
    gitignore: "",
    sources: [],
    ...extra,
  };
}

const codes = async (ctx: DoctorContext, only?: string): Promise<string[]> =>
  (
    await runRules(
      ctx,
      RULES.filter(
        (rule) =>
          rule.code !== "BS303" &&
          // BS211 reports the role timeouts of every snapshot that has them.
          (only ? rule.code === only : rule.code !== "BS211"),
      ),
    )
  ).map((finding) => finding.code);

describe("doctor rules", () => {
  it("passes the fixture schema", async () => {
    expect(await codes(context(base))).toEqual([]);
  });

  it("flags live query tables without broadcasts and keyless realtime deletes", async () => {
    const catalog = structuredClone(toCatalog(base)) as {
      -readonly [K in keyof Catalog]: Catalog[K];
    };
    catalog.realtime = ["public.tags", "public.customers"];
    table(catalog.tables as CatalogTable[], "tags").replicaIdentity = "NOTHING";
    edit(table(catalog.tables as CatalogTable[], "notes").triggers).push({
      name: "bs_realtime",
      timing: "after",
      events: ["insert", "update", "delete"],
      level: "statement",
      function: "better_supabase.broadcast_changes",
    });
    const ctx = context(fromCatalog(catalog), {
      config: resolveConfig(
        { realtime: { tables: ["customers", "public.notes", "missing"] } },
        "/project",
      ),
    });
    const findings = await runRules(
      ctx,
      RULES.filter((rule) => rule.code === "BS305" || rule.code === "BS306"),
    );
    expect(findings.map((finding) => finding.target)).toEqual([
      "public.customers",
      "missing",
      "public.tags",
    ]);
  });

  it("flags anonymous write policies", async () => {
    const snap = snapshot((tables) => {
      edit(table(tables, "notes").policies).push({
        name: "anyone",
        command: "insert",
        roles: ["anon"],
        permissive: true,
        using: null,
        check: "true",
      });
    });
    const [finding, ...rest] = await runRules(
      context(snap),
      RULES.filter((rule) => rule.code === "BS103"),
    );
    expect(rest).toEqual([]);
    expect(finding).toMatchObject({
      target: "public.notes.anyone",
      object: { kind: "policy", schema: "public", name: "anyone" },
      help: "https://bettersupabase.com/docs/cli/doctor#bs103",
    });
  });

  it("flags tables the Data API roles cannot reach", async () => {
    const snap = snapshot((tables) => {
      table(tables, "tags").grants = [];
      table(tables, "notes").grants = [
        { role: "PUBLIC", privileges: ["SELECT"] },
      ];
    });
    const only = RULES.filter((rule) => rule.code === "BS106");
    const plain = await runRules(context(snap), only);
    expect(plain.map((finding) => finding.target)).toEqual([
      "public.tags:authenticated",
    ]);
    expect(plain[0]!.message).toContain(
      "grant select on table public.tags to authenticated;",
    );

    const exposed = await runRules(
      context(snap, {
        config: resolveConfig(
          {
            expose: {
              notes: ["select", "insert"],
              "public.organizations": { anon: ["select"] },
            },
            tables: { tags: { exclude: true } },
          },
          "/project",
        ),
        configToml: toml("[api]\nauto_expose_new_tables = false\n"),
      }),
      only,
    );
    expect(exposed.map((finding) => finding.target)).toEqual([
      "public.notes:authenticated",
      "public.organizations:anon",
    ]);
    expect(exposed[0]!.message).toMatch(/no insert on public\.notes/);
    expect(exposed[0]!.message).toContain("auto_expose_new_tables = false");
  });

  it("flags tenant tables whose policies skip a command", async () => {
    const policy = (
      name: string,
      command: "all" | "select" | "insert" | "update" | "delete",
      using: string,
    ) => ({
      name,
      command,
      roles: ["authenticated"],
      permissive: true,
      using,
      check: null,
      functions: [],
    });
    const snap = snapshot((tables) => {
      table(tables, "tags").policies = [
        policy("tags_read", "select", "organization_id = current_tenant_id()"),
        policy("tags_add", "insert", "organization_id = current_tenant_id()"),
      ];
      table(tables, "organizations").policies = [
        policy("organizations_read", "select", "id = current_tenant_id()"),
      ];
    });
    const only = RULES.filter((rule) => rule.code === "BS107");
    const findings = await runRules(context(snap), only);
    expect(findings.map((finding) => finding.target)).toEqual(["public.tags"]);
    expect(findings[0]!.message).toContain("no update, delete policy");
  });

  describe("self-grant columns (BS213)", () => {
    const only = RULES.filter((rule) => rule.code === "BS213");
    type MutableTable = {
      -readonly [
        K in keyof Snapshot["extras"]["tables"][number]
      ]: Snapshot["extras"]["tables"][number][K];
    };
    const withTable = (
      name: string,
      change: (table: MutableTable) => void,
    ): Snapshot => {
      const snap = structuredClone(base);
      change(snap.extras.tables.find((t) => t.name === name) as MutableTable);
      return snap;
    };
    const updatePolicy = {
      name: "bs_memberships_update_own",
      command: "update" as const,
      roles: ["authenticated"],
      permissive: true,
      using: "user_id = auth.uid()",
      check: "user_id = auth.uid()",
      functions: ["auth.uid"],
    };

    it("flags memberships.role that has_org_role reads when members may update their row", async () => {
      const snap = withTable("memberships", (memberships) => {
        memberships.policies = [...memberships.policies, updatePolicy];
        memberships.grants = [
          { role: "authenticated", privileges: ["SELECT", "UPDATE"] },
        ];
      });
      const findings = await runRules(context(snap), only);
      expect(findings).toHaveLength(1);
      expect(findings[0]).toMatchObject({
        code: "BS213",
        severity: "warning",
        target: "better_supabase.memberships",
      });
      const message = findings[0]!.message;
      expect(message).toContain(
        "authenticated may update org_id, role, user_id",
      );
      expect(message).toContain("better_supabase.member_org_ids reads them");
      expect(message).toContain(
        "revoke update on better_supabase.memberships from authenticated;\ngrant update (created_at) on better_supabase.memberships to authenticated;",
      );
    });

    it("flags a column-level grant on a grant column", async () => {
      const snap = withTable("memberships", (memberships) => {
        memberships.policies = [...memberships.policies, updatePolicy];
        memberships.columnGrants = [
          { column: "role", role: "authenticated", privileges: ["UPDATE"] },
          {
            column: "created_at",
            role: "authenticated",
            privileges: ["UPDATE"],
          },
        ];
      });
      const findings = await runRules(context(snap), only);
      expect(findings[0]?.message).toContain("authenticated may update role.");
      expect(findings[0]?.message).toContain(
        "revoke update (role) on better_supabase.memberships from authenticated;",
      );
    });

    it("passes once the grant columns are revoked, or no policy lets the role write", async () => {
      const revoked = withTable("memberships", (memberships) => {
        memberships.policies = [...memberships.policies, updatePolicy];
        memberships.columnGrants = [
          {
            column: "created_at",
            role: "authenticated",
            privileges: ["UPDATE"],
          },
        ];
      });
      expect(await runRules(context(revoked), only)).toEqual([]);
      const noPolicy = withTable("memberships", (memberships) => {
        memberships.grants = [
          { role: "authenticated", privileges: ["SELECT", "UPDATE"] },
        ];
      });
      expect(await runRules(context(noPolicy), only)).toEqual([]);
    });

    it("flags PermDock's deciding columns and names PD028", async () => {
      const permdock: PermdockProject = {
        ...PERMDOCK,
        manifest: parseManifest(manifest),
      };
      const findings = await runRules(context(base, { permdock }), only);
      expect(findings.map((finding) => finding.target)).toEqual([
        "public.contacts",
      ]);
      expect(findings[0]!.message).toContain(
        "authenticated may insert organization_id; authenticated may update organization_id",
      );
      expect(findings[0]!.message).toContain(
        "PermDock's manifest lists organization_id as deciding columns, which PD028 protects",
      );
      expect(findings[0]!.message).toContain(
        "revoke insert, update on public.contacts from authenticated;\ngrant insert (id, email, full_name, created_at, updated_at), update (id, email, full_name, created_at, updated_at) on public.contacts to authenticated;",
      );

      const revoked = withTable("contacts", (contacts) => {
        contacts.grants = [
          { role: "authenticated", privileges: ["DELETE", "SELECT"] },
        ];
        contacts.columnGrants = [
          {
            column: "full_name",
            role: "authenticated",
            privileges: ["INSERT", "UPDATE"],
          },
        ];
      });
      expect(await runRules(context(revoked, { permdock }), only)).toEqual([]);
    });
  });

  it("flags policies that read auth.mfa_factors directly", async () => {
    const snap = snapshot((tables) => {
      edit(table(tables, "notes").policies).push({
        name: "notes_mfa",
        command: "select",
        roles: ["authenticated"],
        permissive: false,
        using:
          "EXISTS ( SELECT 1 FROM auth.mfa_factors f WHERE f.user_id = auth.uid())",
        check: null,
        functions: [],
      });
    });
    const findings = await runRules(
      context(snap),
      RULES.filter((rule) => rule.code === "BS108"),
    );
    expect(findings).toMatchObject([
      {
        code: "BS108",
        severity: "error",
        target: "public.notes.notes_mfa",
        message: expect.stringContaining("better_supabase.mfa_satisfied()"),
      },
    ]);
  });

  it("flags foreign keys to auth.users that block deleting the user", async () => {
    const snap = snapshot((tables) => {
      const key = {
        columns: ["created_by"],
        refSchema: "auth",
        refTable: "users",
        refColumns: ["id"],
        oneToOne: false,
        onUpdate: "no action",
      } as const;
      edit(table(tables, "notes").foreignKeys).push(
        { ...key, name: "notes_created_by_fkey", onDelete: "no action" },
        { ...key, name: "notes_updated_by_fkey", onDelete: "set null" },
      );
    });
    const findings = await runRules(
      context(snap),
      RULES.filter((rule) => rule.code === "BS406"),
    );
    expect(findings).toMatchObject([
      {
        code: "BS406",
        severity: "warning",
        target: "public.notes.notes_created_by_fkey",
        message: expect.stringContaining("on delete no action"),
      },
    ]);
  });

  it("reports Supabase advisor lints with their own severity and links", async () => {
    const lint = (overrides: Partial<Lint>): Lint => ({
      name: "rls_disabled_in_public",
      title: "RLS Disabled in Public",
      level: "ERROR",
      facing: "EXTERNAL",
      categories: ["SECURITY"],
      description: "",
      detail:
        "Table \\`public.customers\\` is public, but RLS has not been enabled.",
      remediation:
        "https://supabase.com/docs/guides/database/database-linter?lint=0013_rls_disabled_in_public",
      metadata: { schema: "public", name: "customers", type: "table" },
      cache_key: "rls_disabled_in_public_public_customers",
      ...overrides,
    });
    const requested: string[] = [];
    const advisors: AdvisorSource = {
      describe: "test",
      lints: (category) => {
        requested.push(category);
        return Promise.resolve(
          category === "security"
            ? [lint({})]
            : [
                lint({
                  name: "unindexed_foreign_keys",
                  title: "Unindexed foreign keys",
                  level: "INFO",
                  categories: ["PERFORMANCE"],
                  detail: "No index.",
                  metadata: null,
                  cache_key: "unindexed_x",
                }),
              ],
        );
      },
    };
    const advisorRules = RULES.filter((rule) =>
      ["BS100", "BS200"].includes(rule.code),
    );
    const findings = await runRules(context(base, { advisors }), advisorRules);
    expect(requested).toEqual(["security", "performance"]);
    expect(findings).toEqual([
      {
        code: "BS100",
        severity: "error",
        title: "RLS Disabled in Public",
        message:
          "Table `public.customers` is public, but RLS has not been enabled. [rls_disabled_in_public]",
        target: "public.customers",
        object: { kind: "table", schema: "public", name: "customers" },
        help: "https://supabase.com/docs/guides/database/database-linter?lint=0013_rls_disabled_in_public",
      },
      expect.objectContaining({
        code: "BS200",
        severity: "info",
        target: "unindexed_x",
      }),
    ]);

    const skipped = await runRules(
      context(base, { advisors: { skipped: "offline" } }),
      advisorRules,
    );
    expect(skipped.map((finding) => finding.severity)).toEqual([
      "info",
      "info",
    ]);
    const failing = await runRules(
      context(base, {
        advisors: {
          describe: "splinter",
          lints: () => Promise.reject(new Error("boom")),
        },
      }),
      advisorRules,
    );
    expect(failing[0]).toMatchObject({
      severity: "warning",
      message: expect.stringContaining("boom"),
    });
  });

  it("flags tenant columns without an index", async () => {
    const snap = snapshot((tables) => {
      const notes = table(tables, "notes");
      notes.indexes = notes.indexes.filter(
        (index) => index.columns[0] !== "organization_id",
      );
    });
    // Without the index, the foreign key to organizations has none either.
    expect(await codes(context(snap))).toEqual(["BS204", "BS216"]);
  });

  it("flags aggregates while PostgREST disables them", async () => {
    const withSettings = (settings: Record<string, string>): Snapshot => ({
      ...base,
      extras: { ...base.extras, roleSettings: { authenticator: settings } },
    });
    const sources = [
      { path: "src/a.ts", text: "db.customers.findMany()\n" },
      {
        path: "src/b.ts",
        text: "const x = 1;\nawait db.orders.aggregate({ _count: true });\n",
      },
    ];
    const off = await runRules(
      context(withSettings({}), { sources }),
      RULES.filter((rule) => rule.code === "BS210"),
    );
    expect(off).toMatchObject([
      {
        code: "BS210",
        location: { file: "src/b.ts", line: 2 },
        message: expect.stringContaining("pgrst.db_aggregates_enabled"),
      },
    ]);
    const include = [
      { path: "src/c.tsx", text: "include: { _sum: { invoices: {} } }" },
    ];
    expect(
      await codes(context(withSettings({}), { sources: include }), "BS210"),
    ).toEqual(["BS210"]);
    const lists = [{ path: "src/d.ts", text: "facetCounts: true," }];
    expect(
      await codes(context(withSettings({}), { sources: lists }), "BS210"),
    ).toEqual(["BS210"]);
    const on = withSettings({ "pgrst.db_aggregates_enabled": "true" });
    expect(await codes(context(on, { sources }), "BS210")).toEqual([]);
    // Older snapshots carry no role settings, so there is nothing to check.
    expect(await codes(context(base, { sources }), "BS210")).toEqual([]);
  });

  describe("RLS performance", () => {
    const helper = (overrides: Partial<ExtrasFunction>): ExtrasFunction => ({
      schema: "private",
      name: "is_member",
      signature: "org uuid",
      language: "plpgsql",
      volatility: "stable",
      securityDefiner: true,
      settings: {},
      ...overrides,
    });
    const withFunctions = (
      snap: Snapshot,
      functions: ExtrasFunction[],
      roleSettings?: Record<string, Record<string, string>>,
    ): Snapshot => ({
      ...snap,
      extras: {
        ...snap.extras,
        functions,
        ...(roleSettings ? { roleSettings } : {}),
      },
    });
    const memberPolicy = (name: string, using: string) => ({
      name,
      command: "select" as const,
      roles: ["authenticated"],
      permissive: true,
      using,
      check: null,
      functions: ["private.is_member"],
    });

    it("flags slow helpers called with a row column (BS205)", async () => {
      const snap = snapshot((tables) => {
        table(tables, "customers").policies = [
          memberPolicy(
            "customers_member",
            "( SELECT private.is_member(customers.organization_id) AS is_member)",
          ),
        ];
      });
      const findings = await runRules(
        context(withFunctions(snap, [helper({})])),
        RULES.filter((rule) => rule.code === "BS205"),
      );
      expect(findings).toMatchObject([
        {
          code: "BS205",
          message: expect.stringContaining(
            "private.is_member(organization_id), a plpgsql function",
          ),
          object: { kind: "policy", name: "customers_member" },
        },
      ]);
      // Inlinable SQL helpers, and calls without a column, are fine.
      const sql = withFunctions(snap, [
        helper({ language: "sql", securityDefiner: false }),
      ]);
      expect(await codes(context(sql), "BS205")).toEqual([]);
      // Postgres never inlines security definer functions or ones with `set`.
      const definer = withFunctions(snap, [helper({ language: "sql" })]);
      expect(
        await runRules(
          context(definer),
          RULES.filter((rule) => rule.code === "BS205"),
        ),
      ).toMatchObject([
        {
          message: expect.stringMatching(
            /a security definer function, .*in \(select <helper>\(\)\)`\.$/,
          ),
        },
      ]);
      const pinned = withFunctions(snap, [
        helper({
          language: "sql",
          securityDefiner: false,
          settings: { search_path: '""' },
        }),
      ]);
      expect(
        await runRules(
          context(pinned),
          RULES.filter((rule) => rule.code === "BS205"),
        ),
      ).toMatchObject([
        {
          message: expect.stringContaining("a function with `set search_path`"),
        },
      ]);
      const constant = snapshot((tables) => {
        table(tables, "customers").policies = [
          memberPolicy(
            "customers_member",
            "private.is_member('00000000-0000-4000-8000-000000000001'::uuid)",
          ),
        ];
      });
      expect(
        await codes(context(withFunctions(constant, [helper({})])), "BS205"),
      ).toEqual([]);
    });

    it("flags security definer helpers used in many policies (BS206)", async () => {
      const names = ["customers", "notes", "tags", "contacts", "locations"];
      const snap = snapshot((tables) => {
        for (const name of names) {
          table(tables, name).policies = [
            memberPolicy(`${name}_member`, "(select private.is_member())"),
          ];
        }
      });
      const five = withFunctions(snap, [helper({})]);
      expect(await codes(context(five), "BS206")).toEqual([]);
      const tight = context(five, {
        config: resolveConfig({ doctor: { policyHelperLimit: 4 } }, "/p"),
      });
      const [finding] = await runRules(
        tight,
        RULES.filter((rule) => rule.code === "BS206"),
      );
      expect(finding).toMatchObject({
        target: "private.is_member",
        message: expect.stringContaining("used in 5 policies"),
        object: { kind: "function", schema: "private", name: "is_member" },
      });
      const invoker = withFunctions(snap, [
        helper({ language: "sql", securityDefiner: false }),
      ]);
      expect(
        await codes(context(invoker, { config: tight.config }), "BS206"),
      ).toEqual([]);
    });

    it("flags overlapping permissive policies and drops the splinter duplicate (BS207)", async () => {
      const snap = snapshot((tables) => {
        edit(table(tables, "notes").policies).push({
          name: "notes_public_read",
          command: "select",
          roles: ["public"],
          permissive: true,
          using: "true",
          check: null,
        });
      });
      const findings = await runRules(
        context(snap),
        RULES.filter((rule) => rule.code === "BS207"),
      );
      expect(findings).toMatchObject([
        {
          target: "public.notes",
          message: expect.stringContaining(
            "select for authenticated: notes_tenant, notes_public_read",
          ),
        },
      ]);
      const lint = {
        name: "multiple_permissive_policies",
        title: "Multiple Permissive Policies",
        level: "WARN",
        facing: "EXTERNAL",
        categories: ["PERFORMANCE"],
        description: "",
        detail: "notes has several",
        remediation: "",
        metadata: { schema: "public", name: "notes", type: "table" },
        cache_key: "multiple_permissive_policies_public_notes",
      } satisfies Lint;
      const advisors: AdvisorSource = {
        describe: "test",
        lints: () => Promise.resolve([lint]),
      };
      const both = RULES.filter((rule) =>
        ["BS200", "BS207"].includes(rule.code),
      );
      expect(await codes(context(snap, { advisors }), undefined)).toContain(
        "BS207",
      );
      expect(
        (await runRules(context(snap, { advisors }), both)).map(
          (finding) => finding.code,
        ),
      ).toEqual(["BS207"]);
      // Without BS207 in the run, splinter's lint stays.
      expect(
        (
          await runRules(
            context(snap, { advisors }),
            RULES.filter((rule) => rule.code === "BS200"),
          )
        ).map((finding) => finding.code),
      ).toEqual(["BS200"]);
    });

    it("reports role timeouts and unhoisted function timeouts (BS211)", async () => {
      const roles = {
        anon: { statement_timeout: "3s" },
        authenticated: { statement_timeout: "8s" },
        authenticator: {
          statement_timeout: "8s",
          "pgrst.db_hoisted_tx_settings": "default_transaction_isolation",
        },
      };
      const slow = helper({
        schema: "public",
        name: "report",
        signature: "",
        language: "sql",
        settings: { statement_timeout: "60s" },
      });
      const findings = await runRules(
        context(withFunctions(base, [slow], roles)),
        RULES.filter((rule) => rule.code === "BS211"),
      );
      expect(findings).toMatchObject([
        {
          severity: "info",
          message:
            "statement_timeout: anon 3s, authenticated 8s, authenticator 8s. idle_in_transaction_session_timeout: anon not set, authenticated not set, authenticator not set. Unset roles use the database default.",
        },
        {
          severity: "warning",
          target: "public.report:statement_timeout",
          object: { kind: "function", name: "report" },
        },
      ]);
      const hoisted = {
        ...roles,
        authenticator: { statement_timeout: "8s" },
      };
      expect(
        await codes(context(withFunctions(base, [slow], hoisted)), "BS211"),
      ).toEqual(["BS211"]);
    });

    it("reads temp spills and slow statements from a live database (BS208, BS209)", async () => {
      const answers: [RegExp, Record<string, unknown>[]][] = [
        [
          /pg_stat_database/,
          [{ temp_files: 3, temp_bytes: 3145728, work_mem: "4MB" }],
        ],
        [/pg_extension/, [{ schema: "extensions" }]],
        [
          /temp_blks_written > 0/,
          [{ query: "select * from big order by x", temp_blks_written: 90 }],
        ],
        [
          /mean_exec_time >/,
          [
            {
              queryid: "42",
              query: 'SELECT "public"."customers".* FROM "public"."customers"',
              calls: 5000,
              mean_exec_time: 81.25,
            },
          ],
        ],
      ];
      const database: LiveDatabase = {
        describe: "test",
        session: true,
        query: <R>(sql: string) =>
          Promise.resolve(
            (answers.find(([pattern]) => pattern.test(sql))?.[1] ?? []) as R[],
          ),
      };
      const live = RULES.filter((rule) =>
        ["BS208", "BS209"].includes(rule.code),
      );
      const withoutStats = await runRules(context(base, { database }), live);
      expect(withoutStats).toMatchObject([
        {
          code: "BS208",
          message: expect.stringMatching(
            /^3 temporary files \(3\.0 MB\).*work_mem is 4MB.*select \* from big order by x \(90 blocks\)/,
          ),
        },
      ]);
      const withStats = await runRules(
        context(base, { database, stats: true }),
        live,
      );
      expect(withStats[1]).toMatchObject({
        code: "BS209",
        message: expect.stringContaining("81.3 ms mean over 5000 calls"),
        target: "pg_stat_statements:42",
        object: { kind: "table", schema: "public", name: "customers" },
      });
      expect(
        await codes(context(base, { database: { skipped: "x" } })),
      ).toEqual([]);
    });

    it("summarizes plans without rows (BS212)", () => {
      const summary = summarizePlan({
        "Execution Time": 4.5,
        Plan: {
          "Node Type": "Seq Scan",
          "Relation Name": "notes",
          "Actual Total Time": 4.1,
          "Actual Loops": 1,
          Plans: [
            {
              "Node Type": "Result",
              "Parent Relationship": "InitPlan",
              "Subplan Name": "InitPlan 1",
              "Actual Total Time": 0.02,
              "Actual Loops": 1,
            },
            {
              "Node Type": "Index Scan",
              "Relation Name": "memberships",
              "Parent Relationship": "SubPlan",
              "Subplan Name": "SubPlan 2",
              "Actual Total Time": 0.01,
              "Actual Loops": 250,
            },
          ],
        },
      });
      expect(summary).toEqual({
        nodes: [
          "Seq Scan on notes 4.10 ms ×1",
          "InitPlan 1: Result 0.02 ms ×1",
          "SubPlan 2: Index Scan on memberships 0.01 ms ×250",
        ],
        initPlans: 1,
        perRowSubPlans: ["SubPlan 2: Index Scan on memberships ×250"],
        executionMs: 4.5,
      });
    });

    it("needs a direct connection for --explain (BS212)", async () => {
      const explain = { tables: ["customers"], claims: { role: "anon" } };
      const rule = RULES.filter((entry) => entry.code === "BS212");
      const database: LiveDatabase = {
        describe: "management",
        session: false,
        query: () => Promise.resolve([]),
      };
      expect(
        await runRules(context(base, { database, explain }), rule),
      ).toMatchObject([
        {
          severity: "warning",
          message: expect.stringContaining("direct database connection"),
        },
      ]);
      expect(await runRules(context(base, { database }), rule)).toEqual([]);
    });
  });

  describe("Auth hooks", () => {
    const HOOK_TOML = `[auth.hook.custom_access_token]
enabled = true
uri = "pg-functions://postgres/rbac/custom_access_token_hook"
`;
    const hookFn = (
      overrides: Partial<ExtrasHookFunction> = {},
    ): ExtrasHookFunction => ({
      schema: "rbac",
      name: "custom_access_token_hook",
      signature: "event jsonb",
      language: "plpgsql",
      volatility: "stable",
      securityDefiner: false,
      settings: { search_path: '""' },
      execute: ["supabase_auth_admin"],
      publicExecute: false,
      schemaUsage: ["supabase_auth_admin"],
      ...overrides,
    });
    const withHook = (functions: ExtrasHookFunction[]): Snapshot => ({
      ...base,
      extras: {
        ...base.extras,
        hooks: [
          {
            hook: "custom_access_token",
            schema: "rbac",
            name: "custom_access_token_hook",
            functions,
          },
        ],
      },
    });
    const hookContext = (
      snap: Snapshot,
      extra: Partial<DoctorContext> = {},
    ): DoctorContext =>
      context(snap, { configToml: toml(HOOK_TOML), ...extra });
    const only = (code: string) => RULES.filter((rule) => rule.code === code);

    it("parses pg-functions hooks from config.toml", () => {
      expect(
        pgFunctionHooks(
          parseToml(`${HOOK_TOML}
[auth.hook.send_email]
enabled = false
uri = "pg-functions://postgres/public/send"

[auth.hook.send_sms]
enabled = true
uri = "https://example.com/hook"
`),
        ),
      ).toEqual([
        {
          hook: "custom_access_token",
          uri: "pg-functions://postgres/rbac/custom_access_token_hook",
          schema: "rbac",
          name: "custom_access_token_hook",
        },
      ]);
    });

    it("keeps functions, role settings and hooks from saved snapshots", () => {
      expect(base.extras.functions).toContainEqual(
        expect.objectContaining({
          schema: "better_supabase",
          name: "has_org_role",
          securityDefiner: true,
          execute: ["authenticated"],
        }),
      );
      expect(base.extras.hooks?.map((hook) => hook.name)).toEqual([
        "custom_access_token_hook",
      ]);
    });

    it("passes the fixture hook and a well-formed one", async () => {
      expect(await codes(hookContext(base), "BS404")).toEqual([]);
      expect(await codes(hookContext(base), "BS405")).toEqual([]);
      expect(await codes(hookContext(withHook([hookFn()])))).not.toContain(
        "BS404",
      );
    });

    it("flags missing grants and API access (BS404)", async () => {
      const findings = await runRules(
        hookContext(
          withHook([
            hookFn({
              execute: ["anon", "authenticated"],
              publicExecute: true,
              schemaUsage: [],
            }),
          ]),
        ),
        only("BS404"),
      );
      expect(findings).toHaveLength(1);
      expect(findings[0]).toMatchObject({
        code: "BS404",
        severity: "error",
        object: { kind: "function", name: "custom_access_token_hook" },
      });
      const message = findings[0]!.message;
      expect(message).toContain(
        "grant usage on schema rbac to supabase_auth_admin;",
      );
      expect(message).toContain(
        "grant execute on function rbac.custom_access_token_hook(event jsonb) to supabase_auth_admin;",
      );
      expect(message).toContain("authenticated, anon, public may execute it");
      expect(message).toContain("from authenticated, anon, public;");
    });

    it("points PermDock's hook at its grants migration, and an applied-later one at migration up (BS404)", async () => {
      const ungranted = withHook([hookFn({ execute: [], schemaUsage: [] })]);
      const hookFile = {
        path: "supabase/schemas/040_hook.sql",
        text: "-- permdock:hook v1 schema=rbac\ncreate or replace function rbac.custom_access_token_hook(event jsonb)",
      };
      const [permdock] = await runRules(
        hookContext(ungranted, { sqlFiles: [hookFile] }),
        only("BS404"),
      );
      expect(permdock?.message).toContain(
        "permdock supabase hook generate --grants-out",
      );
      expect(permdock?.message).not.toContain("grant usage");

      const grantsFile = {
        path: "supabase/migrations/20261001000001_permdock_hook_grants.sql",
        text: "-- permdock:grants v1 schema=rbac\ngrant execute on function rbac.custom_access_token_hook(jsonb) to supabase_auth_admin;",
      };
      const [migration] = await runRules(
        hookContext(ungranted, { sqlFiles: [hookFile, grantsFile] }),
        only("BS404"),
      );
      expect(migration?.message).toContain(
        `${grantsFile.path} grants it, so the database is behind the migrations`,
      );
    });

    describe("PermDock's hook under pg-delta (BS404)", () => {
      const PGDELTA = toml(
        `${HOOK_TOML}\n[experimental.pgdelta]\nenabled = true\n`,
      );
      const ungranted = withHook([hookFn({ execute: [], schemaUsage: [] })]);
      const hookFile = {
        path: "supabase/schemas/040_hook.sql",
        text: "-- permdock:hook v1 schema=rbac\ncreate or replace function rbac.custom_access_token_hook(event jsonb)",
      };
      const grantedHookFile = {
        ...hookFile,
        text: `${hookFile.text} returns jsonb language plpgsql as $$ begin return event; end $$;\ngrant usage on schema rbac to supabase_auth_admin;\ngrant execute on function rbac.custom_access_token_hook(jsonb) to supabase_auth_admin;`,
      };
      const grantsMigration = {
        path: "supabase/migrations/20261001000001_permdock_hook_grants.sql",
        text: "-- permdock:grants v1 schema=rbac\ngrant execute on function rbac.custom_access_token_hook(jsonb) to supabase_auth_admin;",
      };
      const message = async (
        sqlFiles: NonNullable<DoctorContext["sqlFiles"]>,
        configToml?: SupabaseToml,
      ) =>
        (
          await runRules(
            hookContext(ungranted, {
              sqlFiles,
              ...(configToml ? { configToml } : {}),
            }),
            only("BS404"),
          )
        )[0]?.message;

      it("asks PermDock to keep the grants in the hook's schema file", async () => {
        const text = await message([hookFile], PGDELTA);
        expect(text).toContain(
          "`permdock supabase hook generate --out supabase/schemas/040_hook.sql`",
        );
        expect(text).toContain("without `--grants-out`");
        expect(text).toContain("`supabase db schema declarative sync`");
        expect(text).not.toContain("supabase/migrations/<timestamp>");
        expect(await message([hookFile])).toContain(
          "--grants-out supabase/migrations/<timestamp>_permdock_hook_grants.sql",
        );
      });

      it("accepts grants in the schema file that defines the hook", async () => {
        expect(await message([grantedHookFile], PGDELTA)).toContain(
          `${hookFile.path} grants it, so the database is behind: run \`supabase db schema declarative sync\`, then apply the migrations (\`supabase migration up\`).`,
        );
        // `supabase db diff` drops grants, so the legacy engine doesn't count them.
        expect(await message([grantedHookFile])).toContain(
          "permdock supabase hook generate --grants-out",
        );
      });

      it("names declarative sync for an existing grants migration", async () => {
        expect(await message([hookFile, grantsMigration], PGDELTA)).toContain(
          `${grantsMigration.path} grants it, so the database is behind: run \`supabase db schema declarative sync\``,
        );
        expect(await message([hookFile, grantsMigration])).toContain(
          `${grantsMigration.path} grants it, so the database is behind the migrations: apply them (\`supabase migration up\`).`,
        );
      });

      it("prints the same fixes in --fix-grants", () => {
        const block = (sqlFiles: NonNullable<DoctorContext["sqlFiles"]>) =>
          hookGrantBlock(
            hookGrantProblems(
              hookContext(ungranted, { sqlFiles, configToml: PGDELTA }),
            ),
            "pg-delta",
          );
        expect(block([hookFile])).toContain(
          "is PermDock's hook: permdock supabase hook generate --out supabase/schemas/040_hook.sql (without --grants-out), then supabase db schema declarative sync",
        );
        expect(block([grantedHookFile])).toContain(
          `: ${hookFile.path} grants it; run \`supabase db schema declarative sync\`, then \`supabase migration up\`.`,
        );
        expect(
          hookGrantBlock(
            hookGrantProblems(
              hookContext(ungranted, { sqlFiles: [hookFile, grantsMigration] }),
            ),
          ),
        ).toContain(
          `: ${grantsMigration.path} grants it; run \`supabase migration up\`.`,
        );
      });
    });

    it("points BS404 at the schema file under pg-delta", async () => {
      const ungranted = withHook([
        hookFn({ execute: ["anon"], schemaUsage: [] }),
      ]);
      const [finding] = await runRules(
        hookContext(ungranted, {
          configToml: toml(
            `${HOOK_TOML}\n[experimental.pgdelta]\nenabled = true\n`,
          ),
        }),
        only("BS404"),
      );
      expect(finding?.message).toContain(
        "Add to the schema file that defines the function, then run `supabase db schema declarative sync`",
      );
      expect(
        hookGrantBlock(hookGrantProblems(hookContext(ungranted)), "pg-delta")
          .split("\n")
          .at(1),
      ).toBe(
        "-- Add this to the schema file that defines the function, then run `supabase db schema declarative sync`.",
      );
    });

    it("prints every BS404 fix as one block (--fix-grants)", () => {
      const problems = hookGrantProblems(
        hookContext(withHook([hookFn({ execute: ["anon"], schemaUsage: [] })])),
      );
      expect(hookGrantBlock(problems)).toBe(
        [
          "-- Auth hook grants (better-supabase doctor --fix-grants).",
          "-- `supabase db diff` does not carry function grants; append this to its migration.",
          "",
          "-- rbac.custom_access_token_hook(event jsonb) ([auth.hook.custom_access_token])",
          "grant usage on schema rbac to supabase_auth_admin;",
          "grant execute on function rbac.custom_access_token_hook(event jsonb) to supabase_auth_admin;",
          "revoke execute on function rbac.custom_access_token_hook(event jsonb) from authenticated, anon, public;",
        ].join("\n"),
      );
      expect(hookGrantBlock(hookGrantProblems(hookContext(base)))).toBe(
        "-- Every configured Auth hook function has its grants.",
      );
    });

    it("flags a hook function that does not exist, located in config.toml", async () => {
      const findings = await runRules(hookContext(withHook([])), only("BS404"));
      expect(findings).toMatchObject([
        {
          message: expect.stringContaining("does not exist"),
          location: { file: "supabase/config.toml", line: 1 },
        },
      ]);
    });

    it("skips hooks a snapshot predates", async () => {
      expect(
        await codes(
          hookContext({ ...base, extras: { ...base.extras, hooks: [] } }),
        ),
      ).not.toContain("BS404");
    });

    it("flags a volatile hook without an empty search_path (BS405)", async () => {
      const findings = await runRules(
        hookContext(
          withHook([hookFn({ volatility: "volatile", settings: {} })]),
        ),
        only("BS405"),
      );
      expect(findings).toMatchObject([
        {
          code: "BS405",
          severity: "warning",
          message: expect.stringMatching(/volatile.*search_path/),
        },
      ]);
    });

    it("measures the claims the hook returns with --as (BS405)", async () => {
      const USER_ID = "11111111-1111-4111-8111-111111111111";
      const run = async (
        bytes: number | null,
        user = true,
        extra: Partial<DoctorContext> = {},
        size: {
          memberships?: number;
          attrs?: number;
          truncated?: boolean;
        } = {},
      ) => {
        const queries: string[] = [];
        const database: LiveDatabase = {
          describe: "test",
          session: true,
          async query<R>(sql: string) {
            queries.push(sql);
            if (
              sql.includes("better_supabase.hook_event") &&
              sql.includes("auth.users")
            )
              return (user ? [{ event: "{}" }] : []) as R[];
            if (sql.includes("pg_roles")) return [{ member: true }] as R[];
            if (sql.includes("octet_length"))
              return [
                {
                  bytes,
                  memberships: size.memberships ?? 0,
                  attrs: size.attrs ?? null,
                  truncated: size.truncated ?? false,
                },
              ] as R[];
            return [] as R[];
          },
        };
        const findings = await runRules(
          hookContext(base, { database, hookUser: USER_ID, ...extra }),
          only("BS405"),
        );
        return { findings, queries };
      };
      const big = await run(4096);
      expect(big.findings).toMatchObject([
        {
          severity: "warning",
          message: expect.stringContaining("returns 4096 bytes of claims"),
        },
      ]);
      expect(big.queries[0]).toBe("begin");
      expect(big.queries).toContain("set local role supabase_auth_admin");
      expect(big.queries.at(-1)).toBe("rollback");
      expect((await run(300)).findings).toEqual([]);
      expect((await run(300, false)).findings).toMatchObject([
        { severity: "info", message: expect.stringContaining("no such user") },
      ]);
      expect((await run(1500)).findings).toEqual([]);
      const permdock = { permdock: PERMDOCK };
      // A normal PermDock token: 1.5 KB in total, memberships and attrs within the budget.
      expect(
        (await run(1500, true, permdock, { memberships: 600, attrs: 300 }))
          .findings,
      ).toEqual([]);
      expect(
        (await run(1500, true, permdock, { memberships: 900, attrs: 200 }))
          .findings,
      ).toMatchObject([
        {
          severity: "warning",
          message: expect.stringContaining(
            "1100 bytes of memberships and attrs for 11111111-1111-4111-8111-111111111111, over PermDock's budget of 1024",
          ),
          target: expect.stringMatching(/:budget$/),
        },
      ]);
      expect(
        (await run(2500, true, permdock, { memberships: 400 })).findings,
      ).toMatchObject([
        {
          message: expect.stringContaining("(limit 2048, memberships 400)"),
          target: expect.stringMatching(/:claims$/),
        },
      ]);
      const custom = resolveConfig(
        { doctor: { claimsLimit: 512 } },
        "/project",
      );
      expect((await run(600, true, { config: custom })).findings).toMatchObject(
        [{ message: expect.stringContaining("limit 512") }],
      );
      expect(
        (
          await run(
            1500,
            true,
            { ...permdock, config: custom },
            { memberships: 600 },
          )
        ).findings,
      ).toMatchObject([
        { message: expect.stringContaining("over PermDock's budget of 512") },
      ]);
      expect(
        (await run(300, true, {}, { truncated: true })).findings,
      ).toMatchObject([
        {
          severity: "info",
          message: expect.stringContaining("memberships_truncated"),
        },
      ]);
    });

    it("flags a kit hook next to PermDock (BS407)", async () => {
      const kitHook = hookFn({
        source:
          "begin claims := jsonb_set(claims, '{memberships}', better_supabase.membership_claims(uid)); end",
      });
      expect(await codes(hookContext(withHook([kitHook])), "BS407")).toEqual(
        [],
      );
      expect(
        await codes(
          hookContext(withHook([kitHook]), { permdock: PERMDOCK }),
          "BS407",
        ),
      ).toEqual(["BS407"]);
      const both = hookFn({
        source: `${kitHook.source ?? ""} perform permdock.permdock_claims(event);`,
      });
      expect(await codes(hookContext(withHook([both])), "BS407")).toEqual([
        "BS407",
      ]);
      expect(
        await codes(
          hookContext(withHook([hookFn({ source: "select 1" })]), {
            permdock: PERMDOCK,
          }),
          "BS407",
        ),
      ).toEqual([]);
    });

    it("leaves the features claim and the generated PermDock hook alone (BS407)", async () => {
      const withPermdock = (source: string) =>
        codes(
          hookContext(withHook([hookFn({ source })]), {
            permdock: PERMDOCK,
          }),
          "BS407",
        );
      expect(
        await withPermdock(
          "begin return jsonb_set(event, '{claims,features}', better_supabase.feature_claims(uid)); end",
        ),
      ).toEqual([]);
      expect(
        await withPermdock(
          "begin claims := jsonb_set(claims, '{roles}', held); claims := jsonb_set(claims, '{memberships}', kept); claims := jsonb_set(claims, '{memberships_truncated}', 'true'::jsonb); end",
        ),
      ).toEqual([]);
    });

    it("flags a hook that writes the PermDock claims itself (BS407)", async () => {
      const findings = async (source: string, extra = {}) =>
        runRules(
          hookContext(withHook([hookFn({ source })]), {
            permdock: PERMDOCK,
            ...extra,
          }),
          only("BS407"),
        );
      expect(
        await findings(
          "begin return jsonb_set(event, '{claims,roles}', '[\"admin\"]'); end",
        ),
      ).toMatchObject([{ message: expect.stringContaining("writes roles") }]);
      expect(
        await findings(
          "begin claims := claims || jsonb_build_object('memberships', m, 'tenant_id', t); end",
        ),
      ).toMatchObject([
        { message: expect.stringContaining("writes memberships, tenant_id") },
      ]);
      const renamed = resolveConfig(
        { claims: { tenant: "org_id" } },
        "/project",
      );
      expect(
        await findings(
          "begin return jsonb_set(event, '{claims,org_id}', to_jsonb(t)); end",
          { config: renamed },
        ),
      ).toMatchObject([{ message: expect.stringContaining("writes org_id") }]);
      expect(
        await findings(
          "begin return jsonb_set(event, '{claims,org_id}', to_jsonb(t)); end",
        ),
      ).toEqual([]);
      const wrapped = hookFn({
        source:
          "begin event := public.permdock_hook(event); return jsonb_set(event, '{claims,user_role}', '\"admin\"'); end",
      });
      expect(await codes(hookContext(withHook([wrapped])), "BS407")).toEqual([
        "BS407",
      ]);
    });

    it("treats supabase.hook.claims functions as PermDock's own sources (BS407)", async () => {
      const project: PermdockProject = {
        ...PERMDOCK,
        manifest: {
          ...PERMDOCK.manifest!,
          hook: { schema: "public", function: "permdock_hook" },
          claims: [
            { name: "roles", source: "permdock" },
            { name: "features", source: "better_supabase.feature_claims" },
          ],
        },
      };
      const run = (source: string, extra: Partial<DoctorContext> = {}) =>
        runRules(
          hookContext(withHook([hookFn({ source })]), {
            permdock: project,
            ...extra,
          }),
          only("BS407"),
        );
      // A hook that only adds a registered claim's function is not a second source.
      expect(
        await run(
          "begin return jsonb_set(event, '{claims,features}', better_supabase.feature_claims(uid)); end",
        ),
      ).toEqual([]);
      // Wrapping PermDock's hook and writing features again gives it two writers.
      expect(
        await run(
          "begin event := public.permdock_hook(event); return jsonb_set(event, '{claims,features}', better_supabase.feature_claims(uid)); end",
        ),
      ).toMatchObject([
        {
          message: expect.stringContaining(
            "its hook already writes features from better_supabase.feature_claims",
          ),
        },
      ]);
      // The configured hook is PermDock's own (manifest hook or marker file): never reported.
      const generated = hookFn({
        name: "permdock_hook",
        schema: "public",
        source:
          "begin claims := jsonb_set(claims, '{roles}', held); claims := jsonb_set(claims, '{features}', extra); end",
      });
      expect(
        await runRules(
          hookContext(withHook([generated]), { permdock: project }),
          only("BS407"),
        ),
      ).toEqual([]);
      const marked = hookFn({
        source: "begin claims := jsonb_set(claims, '{roles}', held); end",
      });
      expect(
        await runRules(
          hookContext(withHook([marked]), {
            permdock: PERMDOCK,
            sqlFiles: [
              {
                path: "supabase/migrations/20261001000200_permdock_hook.sql",
                text: '-- permdock:hook v1 schema=rbac tenant=tenant_id budget=1024 claims=roles,features\ncreate or replace function "rbac".custom_access_token_hook(event jsonb)',
              },
            ],
          }),
          only("BS407"),
        ),
      ).toEqual([]);
    });

    it("asks for the manifest when only the PermDock config is there (BS407)", async () => {
      const { manifest: _, ...withoutManifest } = PERMDOCK;
      const noHooks = { ...base, extras: { ...base.extras, hooks: [] } };
      expect(
        await runRules(
          hookContext(noHooks, { permdock: withoutManifest }),
          only("BS407"),
        ),
      ).toMatchObject([
        {
          severity: "info",
          message: expect.stringContaining("permdock supabase inspect --out"),
        },
      ]);
    });
  });

  describe("PermDock helpers for entitlements (BS408)", () => {
    const only = RULES.filter((rule) => rule.code === "BS408");
    const parsed = parseManifest(manifest);
    // The fixture's example fills `features` from its own function; the kit's needs better_supabase.feature_claims.
    const project: PermdockProject = {
      ...PERMDOCK,
      manifest: {
        ...parsed,
        claims: parsed.claims.map((claim) =>
          claim.name === "features"
            ? { ...claim, source: "better_supabase.feature_claims" }
            : claim,
        ),
      },
    };
    const entitlementsConfig: Parameters<typeof resolveConfig>[0] = {
      sql: { kit: ["entitlements"] },
    };
    const check = (
      extra: Partial<DoctorContext> = {},
      config = entitlementsConfig,
    ) =>
      runRules(
        context(base, {
          permdock: project,
          config: resolveConfig(config, "/project"),
          ...extra,
        }),
        only,
      );
    const withHelpers = snapshot((_tables, functions) => {
      for (const name of [
        "member_organization_ids",
        "member_organization_ids_for",
      ])
        functions.push({ ...functions[0]!, schema: "public", name });
    });

    it("passes when the manifest and the database have both helpers", async () => {
      expect(await check({ snapshot: withHelpers })).toEqual([]);
      expect(await check({}, { sql: { kit: ["audit"] } })).toEqual([]);
      expect(
        await check(
          {},
          {
            sql: { kit: ["entitlements"] },
            entitlements: { permdock: false },
          },
        ),
      ).toEqual([]);
      expect(await check({ permdock: PERMDOCK })).toMatchObject([
        {
          target: "entitlements.permdock",
          message: expect.stringContaining("has no rls block"),
        },
      ]);
    });

    it("checks the features claim PermDock's hook registers", async () => {
      const withClaims = (
        claims: { name: string; source: string }[],
      ): PermdockProject => ({
        ...project,
        manifest: { ...project.manifest!, claims },
      });
      expect(
        await messages(
          withClaims([{ name: "features", source: "public.feature_claims" }]),
        ),
      ).toEqual([
        [
          "claims.features",
          expect.stringContaining(
            'fills the "features" claim from public.feature_claims, not better_supabase.feature_claims',
          ),
        ],
      ]);
      expect(
        await messages(
          withClaims([
            { name: "plan", source: "better_supabase.feature_claims" },
          ]),
        ),
      ).toEqual([
        [
          "claims.features",
          expect.stringContaining(
            'registers better_supabase.feature_claims as the "plan" claim, but claims.features is "features"',
          ),
        ],
      ]);
      expect(await messages(withClaims([]))).toEqual([
        [
          "claims.features",
          expect.stringContaining(
            'has no "features" claim, so PermDock\'s hook never writes the plan features',
          ),
        ],
      ]);
    });

    it("warns when rls.memberships maps no table to the scope", async () => {
      const rls = project.manifest!.rls!;
      expect(
        await messages({
          ...project,
          manifest: {
            ...project.manifest!,
            rls: {
              ...rls,
              memberships: rls.memberships!.filter(
                (source) => "value" in source.scope,
              ),
            },
          },
        }),
      ).toEqual([
        [
          "entitlements.permdock.organization",
          expect.stringContaining(
            'permdock.manifest.json maps no rls.memberships table to scope "organization"',
          ),
        ],
      ]);
    });

    it("falls back to the hook's sources without rls.memberships", async () => {
      const { memberships: _, ...rls } = project.manifest!.rls!;
      const older = (
        memberships: NonNullable<PermdockProject["manifest"]>["memberships"],
      ) =>
        messages({
          ...project,
          manifest: { ...project.manifest!, memberships, rls },
        });
      expect(await older(project.manifest!.memberships)).toEqual([
        [
          "entitlements.permdock.organization",
          expect.stringContaining(
            "has no rls.memberships, so entitlement_members() reads the hook's membership sources",
          ),
        ],
      ]);
      expect(
        await older(
          project.manifest!.memberships.filter(
            (source) => "value" in source.scope,
          ),
        ),
      ).toMatchObject([
        { 0: "entitlements.permdock.organization" },
        {
          1: expect.stringContaining(
            'No membership source in permdock.manifest.json covers scope "organization"',
          ),
        },
      ]);
    });

    it("reports helpers missing from the database or the manifest", async () => {
      expect((await check()).map((finding) => finding.message)).toEqual([
        expect.stringContaining(
          "public.member_organization_ids is in permdock.manifest.json but not in the database",
        ),
        expect.stringContaining("public.member_organization_ids_for is in"),
      ]);
      const older: PermdockProject = {
        ...project,
        manifest: {
          ...project.manifest!,
          rls: {
            ...project.manifest!.rls!,
            helpers: project.manifest!.rls!.helpers.filter(
              (helper) => helper.name !== "member_organization_ids_for",
            ),
          },
        },
      };
      expect(
        await check({ permdock: older, snapshot: withHelpers }),
      ).toMatchObject([
        {
          severity: "warning",
          target: "public.member_organization_ids_for",
          message: expect.stringContaining(
            "permdock.manifest.json lists no public.member_organization_ids_for",
          ),
        },
      ]);
    });

    type Helpers = NonNullable<
      NonNullable<PermdockProject["manifest"]>["rls"]
    >["helpers"];
    const editHelpers = (
      edit: (helpers: Helpers) => Helpers,
    ): PermdockProject => ({
      ...project,
      manifest: {
        ...project.manifest!,
        rls: {
          ...project.manifest!.rls!,
          helpers: edit(project.manifest!.rls!.helpers),
        },
      },
    });
    const messages = async (permdock: PermdockProject) =>
      (await check({ permdock, snapshot: withHelpers })).map(
        (finding) => [finding.target, finding.message] as const,
      );

    it("asks for permdock rls generate when member_<scope>_ids is missing", async () => {
      const findings = await messages(
        editHelpers((helpers) =>
          helpers.filter((helper) => helper.name !== "member_organization_ids"),
        ),
      );
      expect(findings).toEqual([
        [
          "public.member_organization_ids",
          expect.stringContaining(
            "has_entitlement calls it. Run `permdock rls generate` with a current PermDock",
          ),
        ],
      ]);
      expect(findings[0]![1]).not.toContain("every scope");
    });

    it("names the membership source setting when member_<scope>_ids_for is missing", async () => {
      expect(
        await messages(
          editHelpers((helpers) =>
            helpers.filter(
              (helper) => helper.name !== "member_organization_ids_for",
            ),
          ),
        ),
      ).toEqual([
        [
          "public.member_organization_ids_for",
          expect.stringMatching(
            /only for a scope with a membership source.*supabase\.hook\.memberships.*rls\.membershipSources.*permdock\.config\.ts/,
          ),
        ],
      ]);
    });

    it("names supabase.hook.claims when supabase_auth_admin can't execute member_<scope>_ids_for", async () => {
      expect(
        await messages(
          editHelpers((helpers) =>
            helpers.map((helper) =>
              helper.name === "member_organization_ids_for"
                ? { ...helper, execute: [] }
                : helper,
            ),
          ),
        ),
      ).toEqual([
        [
          "public.member_organization_ids_for",
          expect.stringMatching(
            /supabase_auth_admin may not execute.*feature_claims runs as its owner.*supabase\.hook\.claims.*permdock\.config\.ts/,
          ),
        ],
      ]);
    });

    it("reports member_<scope>_ids that authenticated may not execute", async () => {
      expect(
        await messages(
          editHelpers((helpers) =>
            helpers.map((helper) =>
              helper.name === "member_organization_ids"
                ? { ...helper, execute: [] }
                : helper,
            ),
          ),
        ),
      ).toEqual([
        [
          "public.member_organization_ids",
          expect.stringContaining("authenticated may not execute"),
        ],
      ]);
    });

    it("checks only the helpers of the chosen scope", async () => {
      expect(
        await messages(
          editHelpers((helpers) =>
            helpers.filter(
              (helper) => !helper.name.startsWith("member_customer"),
            ),
          ),
        ),
      ).toEqual([]);
    });

    it("reports a scope id type the module can't render", async () => {
      const untyped: PermdockProject = {
        ...project,
        manifest: {
          ...project.manifest!,
          rls: {
            ...project.manifest!.rls!,
            scopes: [{ name: "organization", type: "numeric" }],
          },
        },
      };
      expect(await check({ permdock: untyped })).toMatchObject([
        {
          target: "entitlements.permdock",
          message: expect.stringContaining("uuid, text, bigint or integer"),
        },
      ]);
    });

    it("reports a scope the manifest doesn't have", async () => {
      expect(
        await check(
          {},
          {
            sql: { kit: ["entitlements"] },
            entitlements: { permdock: { scope: "team" } },
          },
        ),
      ).toMatchObject([{ target: "entitlements.permdock" }]);
    });
  });

  describe("PermDock row conditions (BS214)", () => {
    const only = RULES.filter((rule) => rule.code === "BS214");
    const withCatalog: PermdockProject = {
      ...PERMDOCK,
      catalog: {
        permissions: [
          { key: "docs.read", rowConditions: true },
          { key: "docs.write", rowConditions: false },
        ],
      },
    };
    const policyFile = {
      path: "supabase/schemas/900_better_supabase_storage.sql",
      text: [
        "-- better-supabase: bucket docs",
        'drop policy if exists "bs_docs_select" on storage.objects;',
        'create policy "bs_docs_select" on storage.objects for select to authenticated',
        `  using (bucket_id = 'docs' and split_part(name, '/', 1) in (select t.id::text from "public"."permitted_organization_ids"('docs.read') as t(id)));`,
        'create policy "bs_docs_insert" on storage.objects for insert to authenticated',
        `  with check (bucket_id = 'docs' and split_part(name, '/', 1) in (select t.id::text from "public"."permitted_organization_ids"('docs.write') as t(id)));`,
        "create policy own_policy on storage.objects for select using ((select public.permdock_has('docs.read')));",
      ].join("\n"),
    };

    it("flags generated policies and configured buckets that name a row-conditioned key", async () => {
      const findings = await runRules(
        context(base, {
          permdock: withCatalog,
          sqlFiles: [policyFile],
          config: resolveConfig(
            {
              buckets: {
                docs: {
                  path: "{orgId}/{file}",
                  policy: {
                    permdock: { read: "docs.read", write: "docs.write" },
                    scope: "organization",
                  },
                },
              },
            },
            "/project",
          ),
        }),
        only,
      );
      expect(findings.map((finding) => finding.target)).toEqual([
        "buckets.docs:docs.read",
        "storage.objects.bs_docs_select:docs.read",
      ]);
      expect(findings[1]).toMatchObject({
        severity: "error",
        location: {
          file: "supabase/schemas/900_better_supabase_storage.sql",
          line: 3,
        },
      });
    });

    it("checks the helper schema and scope against the manifest and catalog", async () => {
      const project: PermdockProject = {
        ...PERMDOCK,
        manifest: parseManifest(manifest),
        catalog: {
          permissions: [
            { key: "docs.read", rowConditions: false, scope: "organization" },
            { key: "docs.write", rowConditions: false, scope: "customer" },
          ],
        },
      };
      const bucket = (policy: { scope: string; schema?: string }) =>
        resolveConfig(
          {
            buckets: {
              docs: {
                path: "{orgId}/{file}",
                policy: {
                  permdock: { read: "docs.read", write: "docs.write" },
                  ...policy,
                },
              },
            },
          },
          "/project",
        );
      const run = async (
        config: ReturnType<typeof resolveConfig>,
        sqlFiles: DoctorContext["sqlFiles"] = [],
      ) =>
        (
          await runRules(
            context(base, { permdock: project, config, sqlFiles }),
            only,
          )
        ).map((finding) => finding.message);
      // The default schema is PermDock's `permdock`; this manifest puts the helpers in `public`.
      expect(await run(bucket({ scope: "organization" }))).toEqual([
        expect.stringContaining(
          "calls PermDock's helpers in schema permdock, but permdock.manifest.json puts them in public",
        ),
        expect.stringContaining(
          'buckets.docs ("docs.write") calls PermDock\'s helpers in schema permdock',
        ),
        expect.stringContaining(
          'checks "docs.write" at scope "organization", but permissions.catalog.json declares it at "customer"',
        ),
      ]);
      expect(await run(bucket({ scope: "tenant", schema: "public" }))).toEqual([
        expect.stringContaining(
          'uses scope "tenant", which permdock.manifest.json doesn\'t declare, so permitted_tenant_ids doesn\'t exist. Use "organization"',
        ),
        expect.stringContaining('uses scope "tenant"'),
      ]);
      expect(
        await run(resolveConfig({}, "/project"), [
          {
            path: "supabase/schemas/900_storage.sql",
            text: `create policy "bs_docs_select" on storage.objects for select using (split_part(name, '/', 1) in (select t.id::text from "authz"."permitted_organization_ids"(p_permission => 'docs.read') as t(id)));`,
          },
        ]),
      ).toEqual([
        expect.stringContaining(
          'Policy "bs_docs_select" on storage.objects calls PermDock\'s helpers in schema authz',
        ),
      ]);
    });

    it("treats a key without a rowConditions flag, or missing from the catalog, as unknown", async () => {
      const findings = await runRules(
        context(base, {
          permdock: {
            ...PERMDOCK,
            catalog: {
              permissions: [{ key: "docs.read" }, { key: "docs.write" }],
            },
          },
          sqlFiles: [policyFile],
          config: resolveConfig(
            {
              buckets: {
                docs: {
                  path: "{orgId}/{file}",
                  policy: {
                    permdock: { read: "docs.read", write: "docs.list" },
                    scope: "organization",
                  },
                },
              },
            },
            "/project",
          ),
        }),
        only,
      );
      expect(
        findings.map((finding) => [finding.severity, finding.target]),
      ).toEqual([
        ["error", "buckets.docs:docs.read"],
        ["error", "buckets.docs:docs.list"],
        ["error", "storage.objects.bs_docs_select:docs.read"],
        ["error", "storage.objects.bs_docs_insert:docs.write"],
      ]);
      expect(findings[0]!.message).toContain(
        "has no rowConditions flag in permissions.catalog.json",
      );
      expect(findings[1]!.message).toContain(
        "is not in permissions.catalog.json",
      );
      expect(findings[0]!.message).toContain("current `permdock catalog`");
    });

    it("asks for the catalog when helpers are used without one", async () => {
      expect(
        await runRules(
          context(base, { permdock: PERMDOCK, sqlFiles: [policyFile] }),
          only,
        ),
      ).toMatchObject([
        {
          severity: "error",
          message: expect.stringContaining(
            "so whether their permissions have row conditions is unknown. Run `permdock catalog`",
          ),
        },
      ]);
      expect(
        await runRules(context(base, { sqlFiles: [policyFile] }), only),
      ).toEqual([]);
    });
  });

  describe("PermDock manifest and config agree (BS409)", () => {
    const only = RULES.filter((rule) => rule.code === "BS409");
    const project: PermdockProject = {
      ...PERMDOCK,
      manifest: parseManifest(manifest),
    };
    const run = async (
      extra: Partial<DoctorContext> = {},
      config: Parameters<typeof resolveConfig>[0] = {},
    ) =>
      runRules(
        context(base, {
          permdock: project,
          config: resolveConfig(config, "/project"),
          ...extra,
        }),
        only,
      );

    it("passes when the claims match the manifest", async () => {
      expect(await run()).toEqual([]);
      expect(await run({}, { claims: { scope: "organization" } })).toEqual([]);
      expect(
        await runRules(
          context(base, { config: resolveConfig({}, "/project") }),
          only,
        ),
      ).toEqual([]);
    });

    it("warns when claims.tenant names another claim than PermDock's", async () => {
      expect(await run({}, { claims: { tenant: "org_id" } })).toMatchObject([
        {
          severity: "warning",
          target: "claims.tenant",
          message: expect.stringContaining(
            'PermDock writes the active tenant to "tenant_id", but claims.tenant is "org_id"',
          ),
        },
      ]);
    });

    it("refuses hook and grants markers it can't read", async () => {
      expect(
        await run({
          sqlFiles: [
            {
              path: "supabase/migrations/1_hook.sql",
              text: "-- permdock:hook v2 schema=public\ncreate function x()",
            },
            {
              path: "supabase/migrations/2_grants.sql",
              text: "-- permdock:grants v1 schema=public\n",
            },
          ],
        }),
      ).toMatchObject([
        {
          severity: "error",
          target: "supabase/migrations/1_hook.sql",
          message: expect.stringContaining("`-- permdock:hook v2` marker"),
        },
      ]);
    });

    it("notes a claims.scope that isn't the manifest's root scope", async () => {
      expect(await run({}, { claims: { scope: "customer" } })).toMatchObject([
        {
          severity: "info",
          target: "claims.scope",
          message: expect.stringContaining(
            'claims.scope is "customer", which stands for "customer" in permdock.manifest.json, whose root scope is "organization"',
          ),
        },
      ]);
    });
  });

  describe("PermDock access model (BS411)", () => {
    const only = RULES.filter((rule) => rule.code === "BS411");
    const allScopeOnly = (): PermdockProject["catalog"] => ({
      permissions: kitPermissionKeys(
        { access: { model: "permdock" } },
        Object.keys(SQL_MODULES),
      ).map((entry) => ({ key: entry.key, rowConditions: false })),
    });
    const project: PermdockProject = {
      ...PERMDOCK,
      manifest: parseManifest(manifest),
      catalog: allScopeOnly()!,
    };
    const withHelpers = snapshot((_tables, functions) => {
      for (const name of ["permitted_organization_ids", "permdock_has"])
        functions.push({ ...functions[0]!, schema: "public", name });
    });
    const run = async (
      access: object = {},
      extra: Partial<DoctorContext> = {},
      kit: string[] = ["access", "organizations"],
    ) =>
      runRules(
        context(withHelpers, {
          permdock: project,
          config: resolveConfig(
            {
              sql: { kit },
              kits: {
                access: {
                  model: "permdock",
                  functions: {
                    canAssign:
                      "public.permdock_can_assign({role}, {tenant}::text)",
                  },
                  ...access,
                },
              },
            },
            "/project",
          ),
          ...extra,
        }),
        only,
      );

    it("passes when the manifest, the catalog and the database back the model", async () => {
      expect(await run()).toMatchObject([
        {
          severity: "info",
          message: expect.stringContaining(
            "doesn't list public.permdock_can_assign",
          ),
        },
      ]);
      expect(
        await run({ model: "roles" }, {}, ["access", "organizations"]),
      ).toEqual([]);
      expect(await run({}, {}, ["profiles"])).toEqual([]);
    });

    it("reports a manifest that can't back the model", async () => {
      expect(await run({}, { permdock: PERMDOCK })).toMatchObject([
        {
          target: "kits.access.permdock",
          message: expect.stringContaining("has no rls block"),
        },
      ]);
      expect(await run({ permdock: { scope: "tenant" } })).toMatchObject([
        {
          target: "kits.access.permdock",
          message: expect.stringContaining(
            'kits.access.permdock.scope is "tenant"',
          ),
        },
      ]);
    });

    it("reports helpers the manifest or the database lacks", async () => {
      const rls = project.manifest!.rls!;
      const older: PermdockProject = {
        ...project,
        manifest: {
          ...project.manifest!,
          rls: {
            ...rls,
            helpers: rls.helpers
              .filter((helper) => helper.name !== "permdock_has")
              .map((helper) =>
                helper.name === "permitted_organization_ids"
                  ? { ...helper, execute: [] }
                  : helper,
              ),
          },
        },
      };
      const findings = await run({}, { permdock: older });
      expect(
        findings.filter((finding) => finding.severity === "error"),
      ).toMatchObject([
        {
          target: "public.permitted_organization_ids",
          message: expect.stringContaining(
            "authenticated may not execute public.permitted_organization_ids",
          ),
        },
        {
          target: "public.permdock_has",
          message: expect.stringContaining("lists no public.permdock_has"),
        },
      ]);
      expect(await run({}, { snapshot: base })).toMatchObject([
        {
          target: "public.permitted_organization_ids",
          message: expect.stringContaining("not in the database"),
        },
        {
          target: "public.permdock_has",
          message: expect.stringContaining("not in the database"),
        },
        { severity: "info" },
      ]);
    });

    it("reports kit permission keys the catalog doesn't mark scope-only", async () => {
      const findings = await run(
        {},
        {
          permdock: {
            ...project,
            catalog: {
              permissions: [
                { key: "organization.update", rowConditions: true },
              ],
            },
          },
        },
      );
      expect(findings).toContainEqual(
        expect.objectContaining({
          severity: "error",
          target: "kits.organizations.permissions.update",
          message: expect.stringContaining("has row conditions"),
        }),
      );
      expect(findings).toContainEqual(
        expect.objectContaining({
          target: "kits.organizations.permissions.delete",
          message: expect.stringContaining(
            "is not in permissions.catalog.json",
          ),
        }),
      );
    });

    it("warns without canAssign and recommends permdock_can_assign", async () => {
      const findings = await run({ functions: {} });
      expect(findings).toMatchObject([
        {
          severity: "warning",
          target: "kits.access.functions.canAssign",
          message: expect.stringContaining(
            'Set canAssign: "public.permdock_can_assign({role}, {tenant}::text)"',
          ),
        },
      ]);
      expect(findings[0]!.message).toContain("PermDock projects don't install");
    });
  });

  it("flags soft delete hidden by a select policy and bucket drift", async () => {
    const snap = snapshot((tables) => {
      edit(table(tables, "customers").policies).push({
        name: "live_only",
        command: "select",
        roles: ["authenticated"],
        permissive: false,
        using: "(archived_at IS NULL)",
        check: null,
      });
    });
    const ctx = context(snap, {
      config: resolveConfig(
        {
          plugins: { softDelete: { column: "archived_at" } },
          buckets: {
            customerLogos: { path: "{orgId}/logo.webp", fileSizeLimit: "1MiB" },
            avatars: { path: "{userId}.png" },
          },
        },
        "/project",
      ),
    });
    const findings = await runRules(
      ctx,
      RULES.filter((rule) => ["BS301", "BS302"].includes(rule.code)),
    );
    // customer-logos differs in public, size limit and MIME types; avatars is missing.
    expect(findings.map((finding) => finding.code)).toEqual([
      "BS301",
      "BS302",
      "BS302",
      "BS302",
      "BS302",
    ]);
    expect(findings.map((finding) => finding.message).join("\n")).toMatch(
      /avatars/,
    );
  });

  it("reads supabase/config.toml", async () => {
    const configToml = toml(
      "[api]\nport = 1\n\n[auth]\njwt_expiry = 7200\nenable_refresh_token_rotation = true\nrefresh_token_reuse_interval = 0\n\n[db]\nport = 2\n",
    );
    const findings = await runRules(
      context(base, { configToml }),
      RULES.filter((rule) => rule.code.startsWith("BS4")),
    );
    expect(
      findings.map((finding) => [finding.code, finding.location?.line]),
    ).toEqual([
      ["BS401", 7],
      ["BS402", 5],
      ["BS403", 4],
    ]);
    const fine = toml(
      '[auth]\nsigning_keys_path = "./signing_keys.json"\nrefresh_token_reuse_interval = 10\n',
    );
    expect(await codes(context(base, { configToml: fine }))).toEqual([]);
  });

  it("compares configured buckets with config.toml", async () => {
    const ctx = context(base, {
      config: resolveConfig(
        {
          buckets: {
            customerLogos: {
              path: "{orgId}/logo.webp",
              fileSizeLimit: "1MiB",
              allowedMimeTypes: ["image/webp"],
            },
          },
        },
        "/project",
      ),
      configToml: toml(
        '[storage]\nenabled = true\n\n[storage.buckets.customer-logos]\npublic = true\nfile_size_limit = "1MiB"\nallowed_mime_types = ["image/webp"] # logos\n',
      ),
    });
    const findings = await runRules(
      ctx,
      RULES.filter((rule) => rule.code === "BS302"),
    );
    expect(
      findings
        .filter(
          (finding) => finding.target === "[storage.buckets.customer-logos]",
        )
        .map((finding) => [finding.message, finding.location?.line]),
    ).toEqual([
      [
        "supabase/config.toml [storage.buckets.customer-logos]: public is true",
        4,
      ],
    ]);
  });

  it("parses the config.toml subset supabase init writes", () => {
    expect(
      parseToml(
        '# c\n[db]\nport = 54_322\n[auth.email]\nenable_confirmations = false\nsite_url = "http://x" # note\nredirects = ["a", \'b\']\n[storage.buckets."my-bucket"]\npublic = true\n',
      ),
    ).toEqual({
      db: { port: 54322 },
      auth: {
        email: {
          enable_confirmations: false,
          site_url: "http://x",
          redirects: ["a", "b"],
        },
      },
      storage: { buckets: { "my-bucket": { public: true } } },
    });
  });

  it("checks env files without printing values", async () => {
    const envFiles = [
      {
        path: ".env.local",
        text: 'NEXT_PUBLIC_SUPABASE_URL=http://x\nNEXT_PUBLIC_SUPABASE_SECRET_KEY="sb_secret_abc"\n',
      },
      { path: ".env", text: "SUPABASE_DB_URL=postgresql://u:p@h/db\n" },
      { path: "apps/web/.env.example", text: "SUPABASE_SECRET_KEY=\n" },
    ];
    const findings = await runRules(
      context(base, { envFiles, gitignore: "# env\n.env*.local\n" }),
      RULES.filter((rule) => rule.code.startsWith("BS5")),
    );
    expect(
      findings.map((finding) => [
        finding.code,
        finding.target,
        finding.location?.line,
      ]),
    ).toEqual([
      ["BS501", ".env.local:NEXT_PUBLIC_SUPABASE_SECRET_KEY", 2],
      ["BS502", ".env", 1],
    ]);
    expect(JSON.stringify(findings)).not.toContain("sb_secret_abc");
  });
});

describe("doctor formats", () => {
  const findings = [
    {
      code: "BS103",
      severity: "error" as const,
      title: "Policy allows anonymous writes",
      message: "public.x has RLS disabled, really: 100%",
      target: "public.x",
      location: { file: "supabase/schemas/x.sql", line: 3 },
      help: "https://bettersupabase.com/docs/cli/doctor#bs103",
    },
    {
      code: "BS403",
      severity: "info" as const,
      title: "Local stack signs tokens with a shared secret",
      message: "No signing keys.",
      help: "https://bettersupabase.com/docs/cli/doctor#bs403",
    },
  ];
  const options = {
    rules: RULES,
    version: "1.0.0",
    fallbackFile: "supabase/config.toml",
  };

  it("writes SARIF 2.1.0 with rules and locations", () => {
    const sarif = JSON.parse(
      formatReport(findings, { ...options, format: "sarif" }),
    ) as {
      version: string;
      runs: {
        tool: { driver: { rules: { id: string; name: string }[] } };
        results: Record<string, unknown>[];
      }[];
    };
    expect(sarif.version).toBe("2.1.0");
    const [runEntry] = sarif.runs;
    expect(runEntry!.tool.driver.rules.map((rule) => rule.id)).toEqual(
      RULE_CODES,
    );
    expect(runEntry!.tool.driver.rules[0]!.name).toBe(
      "SupabaseSecurityAdvisor",
    );
    expect(runEntry!.results[0]).toMatchObject({
      ruleId: "BS103",
      level: "error",
      locations: [
        {
          physicalLocation: {
            artifactLocation: { uri: "supabase/schemas/x.sql" },
            region: { startLine: 3 },
          },
        },
      ],
    });
    expect(runEntry!.results[1]).toMatchObject({
      level: "note",
      locations: [
        {
          physicalLocation: {
            artifactLocation: { uri: "supabase/config.toml" },
          },
        },
      ],
    });
  });

  it("writes GitHub annotations and JSON with a $schema", () => {
    const github = formatReport(findings, {
      ...options,
      format: "github",
    }).split("\n");
    expect(github[0]).toBe(
      "::error file=supabase/schemas/x.sql,line=3,title=BS103 Policy allows anonymous writes::public.x has RLS disabled, really: 100%25 (https://bettersupabase.com/docs/cli/doctor#bs103)",
    );
    expect(github[1]).toMatch(/^::notice title=BS403/);
    const json = JSON.parse(
      formatReport(findings, { ...options, format: "json" }),
    ) as Record<string, unknown>;
    expect(json).toMatchObject({
      $schema:
        "https://unpkg.com/better-supabase/schemas/doctor-report-v1.json",
      summary: { errors: 1, warnings: 0, infos: 1 },
    });
    expect(formatReport([], { ...options, format: "text" })).toBe(
      "No problems found.",
    );
  });

  it("lists text findings by severity, then code", () => {
    const lines = formatReport([...findings].reverse(), {
      ...options,
      format: "text",
    }).split("\n");
    expect(lines[0]).toMatch(/^error\s+BS103 /);
    expect(lines[3]).toMatch(/^info\s+BS403 /);
  });
});

describe("doctor command", () => {
  let dir: string;

  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "better-supabase-doctor-"));
  });

  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  async function write(path: string, contents: string): Promise<void> {
    await mkdir(dirname(join(dir, path)), { recursive: true });
    await writeFile(join(dir, path), contents);
  }

  it("locates findings in SQL files and sets the exit code", async () => {
    const snap = snapshot((tables) => {
      edit(table(tables, "notes").policies).push({
        name: "anyone",
        command: "insert",
        roles: ["anon"],
        permissive: true,
        using: null,
        check: "true",
      });
      const notes = table(tables, "notes");
      notes.indexes = notes.indexes.filter(
        (index) => index.columns[0] !== "organization_id",
      );
    });
    await write("snapshot.json", JSON.stringify(snap));
    await write(
      "supabase/migrations/001_init.sql",
      'create policy "anyone" on public.notes;\n',
    );
    await write(
      "supabase/migrations/002_more.sql",
      '\n\ncreate policy anyone on "public"."notes" (\n);\n',
    );
    await write(
      "better-supabase.config.json",
      JSON.stringify({
        doctor: { ignore: ["BS303"] },
        plugins: { tenant: true },
      }),
    );

    const result = await run([
      "doctor",
      "--snapshot",
      "snapshot.json",
      "--json",
      "--cwd",
      dir,
    ]);
    expect(result.code).toBe(1);
    const report = JSON.parse(result.stdout) as {
      findings: { code: string; location?: unknown }[];
    };
    expect(
      report.findings.find((finding) => finding.code === "BS103")?.location,
    ).toEqual({
      file: "supabase/migrations/002_more.sql",
      line: 3,
    });

    const warnings = await run([
      "doctor",
      "--snapshot",
      "snapshot.json",
      "--only",
      "BS204",
      "--cwd",
      dir,
    ]);
    expect(warnings.code).toBe(0);
    expect(warnings.stdout).toContain("BS204");
    expect(
      (
        await run([
          "doctor",
          "--snapshot",
          "snapshot.json",
          "--only",
          "BS204",
          "--strict",
          "--cwd",
          dir,
        ])
      ).code,
    ).toBe(1);
    expect(
      (
        await run([
          "doctor",
          "--snapshot",
          "snapshot.json",
          "--only",
          "BS999",
          "--cwd",
          dir,
        ])
      ).code,
    ).toBe(2);
    expect(
      (
        await run([
          "doctor",
          "--snapshot",
          "snapshot.json",
          "--format",
          "xml",
          "--cwd",
          dir,
        ])
      ).code,
    ).toBe(2);

    const sarif = await run([
      "doctor",
      "--snapshot",
      "snapshot.json",
      "--format",
      "sarif",
      "--out",
      "doctor.sarif",
      "--cwd",
      dir,
    ]);
    expect(sarif.stdout).toContain("Wrote doctor.sarif: 1 errors");
    expect(
      JSON.parse(await readFile(join(dir, "doctor.sarif"), "utf8")),
    ).toMatchObject({ version: "2.1.0" });
  });

  it("locates functions and policies", () => {
    const files = [
      {
        path: "supabase/schemas/a.sql",
        text: "create or replace function public.do_it()\nreturns void",
      },
      {
        path: "supabase/schemas/b.sql",
        text: '\ncreate policy "Tenant read" on public.x',
      },
    ];
    expect(
      locate(files, { kind: "function", schema: "public", name: "do_it" }),
    ).toEqual({ file: "supabase/schemas/a.sql", line: 1 });
    expect(
      locate(files, { kind: "policy", schema: "public", name: "Tenant read" }),
    ).toEqual({ file: "supabase/schemas/b.sql", line: 2 });
    expect(
      locate(files, { kind: "table", schema: "public", name: "do_it" }),
    ).toBeUndefined();
  });

  it("documents every check", async () => {
    const docs = await readFile(
      new URL(
        "../../../../../apps/docs/content/docs/cli/doctor.mdx",
        import.meta.url,
      ),
      "utf8",
    );
    for (const code of RULE_CODES) expect(docs).toContain(`### ${code}`);
    const schema = JSON.parse(
      await readFile(
        new URL(
          import.meta.resolve("better-supabase/schemas/doctor-report-v1.json"),
        ),
        "utf8",
      ),
    ) as {
      properties: {
        findings: { items: { properties: { code: { enum: string[] } } } };
      };
    };
    expect(schema.properties.findings.items.properties.code.enum).toEqual(
      RULE_CODES,
    );
  });
});
