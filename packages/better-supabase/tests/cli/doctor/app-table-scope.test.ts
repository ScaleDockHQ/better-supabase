import { describe, expect, it } from "vitest";

import type { LiveDatabase } from "../../../src/cli/doctor/live.ts";
import type { DoctorContext } from "../../../src/cli/doctor/rules.ts";
import type {
  Catalog,
  CatalogColumn,
  CatalogPolicy,
  CatalogTable,
  Snapshot,
} from "../../../src/cli/introspect/types.ts";
import type { AppTablesConfig } from "../../../src/config/index.ts";

import { parseSnapshot } from "../../../src/cli/commands/snapshot.ts";
import { LIVE_CODES } from "../../../src/cli/doctor/live-source.ts";
import { RULES, runRules } from "../../../src/cli/doctor/rules.ts";
import { toCatalog } from "../../../src/cli/introspect/catalog.ts";
import { fromCatalog } from "../../../src/cli/introspect/from-catalog.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { moduleSnapshotFixture as fixture } from "../fixtures/library.ts";

const base = await parseSnapshot(fixture);

type Mutable<T> = { -readonly [K in keyof T]: T[K] };

function snapshot(change: (notes: Mutable<CatalogTable>) => void): Snapshot {
  const copy = structuredClone(toCatalog(base)) as Mutable<Catalog>;

  change(
    (copy.tables as Mutable<CatalogTable>[]).find(
      (entry) => entry.name === "notes",
    )!,
  );

  return fromCatalog(copy);
}

const policy = (overrides: Partial<CatalogPolicy>): CatalogPolicy => ({
  name: "notes_select",
  command: "select",
  roles: ["authenticated"],
  permissive: true,
  using: "true",
  check: null,
  ...overrides,
});

const column = (name: string): CatalogColumn => ({
  name,
  udt: "uuid",
  format: "uuid",
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
});

/** The app tables file better-supabase wrote, creating `tables`. */
const blockFile = (...tables: string[]) => ({
  path: "supabase/schemas/_better_supabase/900_better_supabase_app_tables.sql",
  text: `-- @bsb-tables\n${tables.map((name) => `create table if not exists "public"."${name}" (id uuid primary key);`).join("\n")}`,
});

const appFile = {
  path: "supabase/schemas/010_app.sql",
  text: "create table public.notes (id uuid primary key, body text not null);",
};

const context = (
  snap: Snapshot,
  tables: AppTablesConfig,
  extra: Partial<DoctorContext> = {},
): DoctorContext => ({
  config: resolveConfig(
    { auth: { organization: { column: "organization_id" } }, tables },
    "/project",
  ),
  snapshot: snap,
  configToml: undefined,
  envFiles: [],
  gitignore: "",
  sources: [],
  sqlFiles: [appFile, blockFile()],
  ...extra,
});

const run = (ctx: DoctorContext, ...codes: string[]) =>
  runRules(
    ctx,
    RULES.filter((rule) => codes.includes(rule.code)),
  );

const scoped = (notes: Mutable<CatalogTable>, restrictive: boolean) => {
  notes.policies = [
    ...["select", "insert", "update", "delete"].map((command) =>
      policy({
        name: `notes_${command}`,
        command: command as CatalogPolicy["command"],
      }),
    ),
    ...(restrictive
      ? [
          policy({
            name: "bsb_tenant_scope",
            command: "all",
            permissive: false,
          }),
        ]
      : []),
    policy({ name: "notes_app_read" }),
  ];
};

describe("BS237", () => {
  it("is a hint when bsb_tenant_scope narrows the app's own policies", async () => {
    const snap = snapshot((notes) => {
      scoped(notes, true);
    });

    expect(await run(context(snap, { notes: {} }), "BS237")).toMatchObject([
      {
        code: "BS237",
        severity: "info",
        target: "public.notes",
        message: expect.stringContaining(
          "public.notes has permissive policies of its own (notes_app_read). bsb_tenant_scope keeps rows inside the member's tenants",
        ),
      },
    ]);
  });

  it("warns in user scope, where nothing narrows them", async () => {
    const snap = snapshot((notes) => {
      scoped(notes, false);
    });

    expect(
      await run(context(snap, { notes: { scope: "user" } }), "BS237"),
    ).toMatchObject([
      {
        severity: "warning",
        message: expect.stringContaining(
          "nothing narrows them to the signed-in user's rows",
        ),
      },
    ]);
  });

  it("skips tables in none scope and tables with only the scope's policies", async () => {
    const extra = snapshot((notes) => {
      scoped(notes, true);
    });

    expect(
      await run(context(extra, { notes: { scope: "none" } }), "BS237"),
    ).toEqual([]);

    const clean = snapshot((notes) => {
      scoped(notes, true);
      notes.policies = notes.policies.filter(
        (entry) => entry.name !== "notes_app_read",
      );
    });

    expect(await run(context(clean, { notes: {} }), "BS237")).toEqual([]);
  });
});

const database = (missing: number, seen: string[] = []): LiveDatabase => ({
  describe: "test",
  session: true,
  // SAFETY: each rule reads the rows it asks for, and these match its columns.
  query: (async (sql: string) => {
    seen.push(sql);

    if (sql.includes("pg_constraint")) {
      return [
        {
          schema: "public",
          table: "notes",
          name: "notes_organization_id_not_null",
          expression: "(organization_id IS NOT NULL)",
        },
      ];
    }

    if (sql.includes("count(*)")) {
      return [{ missing: String(missing) }];
    }

    return [{ failing: missing > 0 }];
  }) as LiveDatabase["query"],
});

describe("BS238", () => {
  const snap = snapshot((notes) => {
    if (!notes.columns.some((entry) => entry.name === "organization_id")) {
      notes.columns = [...notes.columns, column("organization_id")];
    }
  });

  it("is a live check", () => {
    expect(LIVE_CODES.has("BS238")).toBe(true);
  });

  it("counts the rows of an enriched table without an owner and defers BS236 to it", async () => {
    const seen: string[] = [];

    const findings = await run(
      context(snap, { notes: {} }, { database: database(3, seen) }),
      "BS236",
      "BS238",
    );

    expect(findings).toMatchObject([
      {
        code: "BS238",
        severity: "warning",
        target: "public.notes.organization_id",
        message: expect.stringContaining(
          "public.notes has 3 rows without organization_id, which no member reads or writes, and updates to them fail notes_organization_id_not_null. Fill it with `better-supabase db backfill notes.organization_id --from <table.column> via <column>`",
        ),
      },
    ]);
    expect(seen).toContain(
      'select count(*) as missing from "public"."notes" where "organization_id" is null',
    );
  });

  it("reports nothing once every row has an owner, or for a table it created", async () => {
    expect(
      await run(
        context(snap, { notes: {} }, { database: database(0) }),
        "BS238",
      ),
    ).toEqual([]);

    expect(
      await run(
        context(
          snap,
          { notes: {} },
          { database: database(3), sqlFiles: [blockFile("notes")] },
        ),
        "BS238",
      ),
    ).toEqual([]);
  });

  it("skips a saved snapshot", async () => {
    expect(
      await run(
        context(snap, { notes: {} }, { database: { skipped: "snapshot" } }),
        "BS238",
      ),
    ).toEqual([]);
  });
});

describe("BS228 over an enriched table", () => {
  it("expects a required column without a default to stay nullable", async () => {
    const snap = snapshot((notes) => {
      notes.columns = [...notes.columns, column("reviewer_id")];
    });

    const tables: AppTablesConfig = {
      notes: { columns: { reviewer_id: { type: "uuid", nullable: false } } },
    };

    expect(await run(context(snap, tables), "BS228")).toEqual([]);

    expect(
      await run(
        context(snap, tables, { sqlFiles: [blockFile("notes")] }),
        "BS228",
      ),
    ).toMatchObject([
      {
        target: "public.notes.reviewer_id",
        message: expect.stringContaining(
          "is nullable in the database and required in appTables",
        ),
      },
    ]);
  });
});
