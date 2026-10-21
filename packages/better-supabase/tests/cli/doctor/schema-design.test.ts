import { describe, expect, it } from "vitest";

import type { Lint } from "../../../src/cli/doctor/advisors.ts";
import type {
  Catalog,
  CatalogColumn,
  CatalogTable,
  Snapshot,
} from "../../../src/cli/introspect/types.ts";

import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import {
  type DoctorContext,
  RULES,
  runRules,
} from "../../../src/cli/doctor/rules.ts";
import { toCatalog } from "../../../src/cli/introspect/catalog.ts";
import { fromCatalog } from "../../../src/cli/introspect/from-catalog.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { moduleSnapshotFixture as fixture } from "../fixtures/library.ts";

const base = await parseSnapshot(fixture);

type Mutable<T> = { -readonly [K in keyof T]: T[K] };

function snapshot(change: (tables: Mutable<CatalogTable>[]) => void): Snapshot {
  const copy = structuredClone(toCatalog(base)) as Mutable<Catalog>;
  change(copy.tables as Mutable<CatalogTable>[]);

  return fromCatalog(copy);
}

const table = (tables: Mutable<CatalogTable>[], name: string) =>
  tables.find((entry) => entry.name === name)!;

const context = (
  snap: Snapshot,
  extra: Partial<DoctorContext> = {},
): DoctorContext => ({
  config: resolveConfig({ plugins: { tenant: true } }, "/project"),
  snapshot: snap,
  configToml: undefined,
  envFiles: [],
  gitignore: "",
  sources: [],
  ...extra,
});

const run = (ctx: DoctorContext, code: string) =>
  runRules(
    ctx,
    RULES.filter((rule) => rule.code === code),
  );

const column = (overrides: Partial<CatalogColumn>): CatalogColumn => ({
  name: "meta",
  udt: "jsonb",
  format: "jsonb",
  typeSchema: "pg_catalog",
  isArray: false,
  isEnum: false,
  nullable: true,
  hasDefault: false,
  default: null,
  identity: null,
  generated: false,
  updatable: true,
  comment: null,
  ...overrides,
});

describe("schema design rules", () => {
  it("pass the fixture schema", async () => {
    for (const code of [
      "BS216",
      "BS217",
      "BS218",
      "BS219",
      "BS220",
      "BS221",
      "BS226",
      "BS227",
    ]) {
      expect(await run(context(base), code)).toEqual([]);
    }
  });

  it("flags foreign keys without an index and defers to splinter's lint (BS216)", async () => {
    const snap = snapshot((tables) => {
      const notes = table(tables, "notes");
      notes.indexes = notes.indexes.filter(
        (index) => index.columns[0] !== "customer_id",
      );
    });

    expect(await run(context(snap), "BS216")).toMatchObject([
      {
        target: "public.notes.notes_customer_id_fkey",
        message: expect.stringContaining(
          "create index on public.notes (customer_id, organization_id);",
        ),
      },
    ]);

    const lint = {
      name: "unindexed_foreign_keys",
      title: "Unindexed foreign keys",
      level: "INFO",
      facing: "EXTERNAL",
      categories: ["PERFORMANCE"],
      description: "",
      detail: "notes has an unindexed foreign key",
      remediation: "",
      metadata: { schema: "public", name: "notes", type: "table" },
      cache_key: "unindexed_foreign_keys_public_notes",
    } satisfies Lint;

    const advisors = { describe: "test", lints: () => Promise.resolve([lint]) };

    const both = await runRules(
      context(snap, { advisors }),
      RULES.filter((rule) => ["BS200", "BS216"].includes(rule.code)),
    );

    expect(both.map((finding) => finding.code)).toEqual(["BS200"]);
    expect(
      (await run(context(snap, { advisors }), "BS216")).map(
        (finding) => finding.target,
      ),
    ).toEqual(["public.notes.notes_customer_id_fkey"]);
  });

  it("accepts partial indexes that only skip null keys (BS216)", async () => {
    const partial = (predicate: string | undefined) =>
      snapshot((tables) => {
        const notes = table(tables, "notes");
        notes.indexes = [
          ...notes.indexes.filter(
            (index) => index.columns[0] !== "customer_id",
          ),
          {
            name: "notes_customer_partial",
            columns: ["customer_id", "organization_id"],
            unique: false,
            primary: false,
            partial: true,
            ...(predicate === undefined ? {} : { predicate }),
          },
        ];
      });

    for (const predicate of [
      "(customer_id IS NOT NULL)",
      "((customer_id IS NOT NULL) AND (organization_id IS NOT NULL))",
      '("customer_id" is not null)',
    ]) {
      expect(await run(context(partial(predicate)), "BS216")).toEqual([]);
    }

    for (const predicate of [
      "(archived_at IS NULL)",
      "((customer_id IS NOT NULL) AND (archived_at IS NULL))",
      undefined,
    ]) {
      expect(
        (await run(context(partial(predicate)), "BS216")).map(
          (finding) => finding.target,
        ),
      ).toEqual(["public.notes.notes_customer_id_fkey"]);
    }
  });

  it("flags tenant foreign keys without the tenant column (BS217)", async () => {
    const snap = snapshot((tables) => {
      const notes = table(tables, "notes");
      notes.foreignKeys = notes.foreignKeys.map((key) =>
        key.refTable === "customers"
          ? { ...key, columns: ["customer_id"], refColumns: ["id"] }
          : key,
      );
    });

    expect(await run(context(snap), "BS217")).toMatchObject([
      {
        target: "public.notes.notes_customer_id_fkey",
        message: expect.stringContaining(
          "reference `(customer_id, organization_id)`",
        ),
      },
    ]);
  });

  it("flags soft-delete tables without a partial index (BS218)", async () => {
    const snap = snapshot((tables) => {
      const customers = table(tables, "customers");
      customers.indexes = customers.indexes.filter((index) => !index.partial);
    });

    expect(await run(context(snap), "BS218")).toMatchObject([
      { target: "public.customers.archived_at" },
    ]);

    const other = snapshot((tables) => {
      const customers = table(tables, "customers");
      customers.indexes = customers.indexes.map((index) =>
        index.partial ? { ...index, predicate: "(status = 'x'::text)" } : index,
      );
    });

    expect(await run(context(other), "BS218")).toHaveLength(1);
  });

  it("flags containment filters on columns without GIN (BS219)", async () => {
    const snap = snapshot((tables) => {
      const notes = table(tables, "notes");
      notes.columns = [...notes.columns, column({})];
    });

    const sources = [
      { path: "src/notes.ts", text: 'q.contains("meta", { pinned: true })' },
    ];

    expect(await run(context(snap, { sources }), "BS219")).toMatchObject([
      {
        target: "public.notes.meta",
        message: expect.stringContaining("using gin (meta jsonb_path_ops)"),
      },
    ]);
    expect(await run(context(snap), "BS219")).toEqual([]);

    const indexed = snapshot((tables) => {
      const notes = table(tables, "notes");
      notes.columns = [...notes.columns, column({})];
      notes.indexes = [
        ...notes.indexes,
        {
          name: "notes_meta_idx",
          columns: ["meta"],
          unique: false,
          primary: false,
          partial: false,
          method: "gin",
          predicate: null,
        },
      ];
    });

    expect(await run(context(indexed, { sources }), "BS219")).toEqual([]);
  });

  it("flags column types to avoid (BS220)", async () => {
    const snap = snapshot((tables) => {
      const notes = table(tables, "notes");
      notes.columns = [
        ...notes.columns,
        column({ name: "sent", udt: "timestamp", format: "timestamp" }),
        column({ name: "raw", udt: "json", format: "json" }),
      ];
    });

    expect(await run(context(snap), "BS220")).toMatchObject([
      {
        message:
          "public.notes: sent is timestamp, use timestamptz; raw is json, use jsonb.",
      },
    ]);
  });

  it("flags direct connections in serverless apps (BS221)", async () => {
    const envFiles = [
      {
        path: ".env.local",
        text: "# DATABASE_URL=postgres://postgres:x@db.abcdefgh.supabase.co:5432/postgres\nDATABASE_URL=postgres://postgres:x@db.abcdefgh.supabase.co:5432/postgres\nPOOLED_URL=postgres://postgres.abc:x@aws-0-eu-central-1.pooler.supabase.com:6543/postgres\n",
      },
    ];

    const sources = [
      { path: "app/api/route.ts", text: "export async function GET() {}" },
    ];

    const findings = await run(context(base, { envFiles, sources }), "BS221");
    expect(findings).toMatchObject([
      {
        target: ".env.local:DATABASE_URL",
        location: { file: ".env.local", line: 2 },
      },
    ]);
    expect(findings[0]!.message).not.toContain("postgres:x@");
    expect(await run(context(base, { envFiles }), "BS221")).toEqual([]);
  });

  it("flags prepared statements through the transaction pooler (BS226)", async () => {
    const pooled = {
      path: ".env.local",
      text: "# DIRECT=postgres://postgres:x@db.abcdefgh.supabase.co:5432/postgres\nDATABASE_URL=postgres://postgres.abc:x@aws-0-eu-central-1.pooler.supabase.com:6543/postgres\nPRISMA_URL=postgres://postgres.abc:x@aws-0-eu-central-1.pooler.supabase.com:6543/postgres?pgbouncer=true\n",
    };

    const sources = [
      {
        path: "src/db.ts",
        text: 'import postgres from "postgres";\n\nexport const sql = postgres(process.env.DATABASE_URL!);\n',
      },
      {
        path: "src/db-safe.ts",
        text: 'import postgres from "postgres";\n\nexport const sql = postgres(url, { prepare: false });\n',
      },
      {
        path: "src/prisma.ts",
        text: 'import { PrismaClient } from "@prisma/client";\n\nexport const prisma = new PrismaClient();\n',
      },
    ];

    const findings = await run(
      context(base, { envFiles: [pooled], sources }),
      "BS226",
    );

    expect(findings).toMatchObject([
      {
        severity: "warning",
        target: "src/db.ts:postgres",
        location: { file: "src/db.ts", line: 1 },
      },
      {
        target: ".env.local:DATABASE_URL",
        location: { file: ".env.local", line: 2 },
      },
    ]);
    expect(findings[1]!.message).not.toContain("postgres.abc:x@");

    expect(
      await run(
        context(base, {
          envFiles: [{ path: ".env.local", text: pooled.text.split("\n")[0]! }],
          sources,
        }),
        "BS226",
      ),
    ).toEqual([]);
    expect(
      await run(
        context(base, { envFiles: [pooled], sources: [sources[1]!] }),
        "BS226",
      ),
    ).toEqual([]);
  });

  it("reports app table columns that drifted from appTables (BS228)", async () => {
    const snap = snapshot((tables) => {
      const notes = table(tables, "notes");
      notes.columns = [
        ...notes.columns,
        column({ name: "meta" }),
        column({
          name: "rating",
          udt: "int4",
          format: "int4",
          nullable: false,
        }),
      ];
    });

    const withTables = (
      columns: Record<
        string,
        { type: "jsonb" | "text" | "integer"; nullable?: boolean }
      >,
    ): DoctorContext =>
      context(snap, {
        config: resolveConfig(
          { plugins: { tenant: true }, appTables: { notes: { columns } } },
          "/project",
        ),
      });

    expect(
      await run(
        withTables({
          meta: { type: "jsonb" },
          rating: { type: "integer", nullable: false },
          later: { type: "text" },
        }),
        "BS228",
      ),
    ).toEqual([]);

    expect(
      await run(
        withTables({
          meta: { type: "text", nullable: false },
          rating: { type: "integer" },
        }),
        "BS228",
      ),
    ).toMatchObject([
      {
        severity: "warning",
        target: "public.notes.meta",
        message: expect.stringContaining(
          "is jsonb in the database and text in appTables, and is nullable in the database and required in appTables",
        ),
      },
      {
        target: "public.notes.rating",
        message: expect.stringContaining(
          "is not null in the database and nullable in appTables",
        ),
      },
    ]);
  });

  it("reports offset pagination and exact counts (BS227)", async () => {
    const sources = [
      {
        path: "src/lists.ts",
        text: [
          "export const customers = defineList({",
          '  pagination: "offset",',
          "});",
          "// pagination: 'offset' was the old default",
          "const { count } = await supabase",
          '  .from("notes")',
          "  .select(\"*\", { count: 'exact' });",
          'export const notes = defineList({ pagination: "cursor", count: "planned" });',
        ].join("\n"),
      },
    ];

    expect(await run(context(base, { sources }), "BS227")).toMatchObject([
      {
        severity: "info",
        target: "src/lists.ts:2:pagination",
        location: { file: "src/lists.ts", line: 2 },
        message: expect.stringContaining('Use `pagination: "cursor"`'),
      },
      {
        target: "src/lists.ts:7:count",
        location: { file: "src/lists.ts", line: 7 },
        message: expect.stringContaining('`count: "planned"`'),
      },
    ]);
  });

  it("flags int8 sequences and numeric columns decoded as number (BS222)", async () => {
    const snap = snapshot((tables) => {
      const notes = table(tables, "notes");
      notes.columns = [
        ...notes.columns,
        column({
          name: "seq",
          udt: "int8",
          format: "int8",
          identity: "always",
        }),
        column({
          name: "counter",
          udt: "int8",
          format: "int8",
          default: "nextval('notes_counter_seq'::regclass)",
        }),
        column({ name: "views", udt: "int8", format: "int8" }),
        column({ name: "amount", udt: "numeric", format: "numeric" }),
      ];
    });

    expect(await run(context(snap), "BS222")).toMatchObject([
      {
        target: "public.notes",
        message:
          'public.notes id (int8), seq (int8), counter (int8), amount (numeric) decode as number and lose precision past 2^53. Set `int8: "bigint"` and `numeric: "string"` in `codecs`.',
      },
      { target: "public.notifications" },
    ]);

    const exact = context(snap, {
      config: resolveConfig(
        {
          plugins: { tenant: true },
          codecs: { int8: "bigint", numeric: "string" },
        },
        "/project",
      ),
    });

    expect(await run(exact, "BS222")).toEqual([]);
  });

  it("flags exposed functions returning an int8 or numeric scalar (BS223)", async () => {
    const template = base.generator.functions[0]!;

    const fn = (
      name: string,
      returnType: string,
      extra: Partial<typeof template> = {},
    ) => ({
      ...template,
      name,
      schema: "public",
      return_type: returnType,
      identity_argument_types: "",
      is_set_returning_function: false,
      ...extra,
    });

    const snap: Snapshot = {
      ...base,
      generator: {
        ...base.generator,
        functions: [
          fn("total_cents", "bigint"),
          fn("scores", "numeric", { is_set_returning_function: true }),
          fn("ids", "bigint[]", { identity_argument_types: "p uuid" }),
          fn("label", "text"),
          fn("rows", "record"),
          fn("hidden_total", "bigint", { schema: "private" }),
        ],
      },
    };

    expect(await run(context(snap), "BS223")).toMatchObject([
      {
        target: "public.total_cents",
        severity: "info",
        message: expect.stringContaining(
          "public.total_cents() returns bigint, which PostgREST sends as a JSON number",
        ),
      },
      {
        target: "public.scores",
        message: expect.stringContaining("returns setof numeric"),
      },
      {
        target: "public.ids",
        message: expect.stringContaining(
          "public.ids(p uuid) returns bigint[], which PostgREST sends as a JSON number and `$rpc` can't cast. Return it as text (`returns text[]`",
        ),
      },
    ]);
  });
});
