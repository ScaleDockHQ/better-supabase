import { resolveConfig } from "better-supabase/config";
import { describe, expect, it } from "vitest";

import type { Lint } from "../../src/doctor/advisors.ts";
import type {
  Catalog,
  CatalogColumn,
  CatalogTable,
  Snapshot,
} from "../../src/introspect/types.ts";

import { parseSnapshot } from "../../src/commands/snapshot.ts";
import { type DoctorContext, RULES, runRules } from "../../src/doctor/rules.ts";
import { toCatalog } from "../../src/introspect/catalog.ts";
import { fromCatalog } from "../../src/introspect/from-catalog.ts";
import { kitSnapshotFixture as fixture } from "../fixtures/library.ts";

const base = parseSnapshot(fixture);

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
    for (const code of ["BS216", "BS217", "BS218", "BS219", "BS220", "BS221"])
      expect(await run(context(base), code)).toEqual([]);
  });

  it("flags foreign keys without an index and drops splinter's duplicate (BS216)", async () => {
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
    const advisors = {
      describe: "test",
      lints: () => Promise.resolve([lint]),
    };
    const both = await runRules(
      context(snap, { advisors }),
      RULES.filter((rule) => ["BS200", "BS216"].includes(rule.code)),
    );
    expect(both.map((finding) => finding.code)).toEqual(["BS216"]);
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
});
