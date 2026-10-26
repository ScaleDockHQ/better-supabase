import { parseArgs } from "citty";
import { cp, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it } from "vitest";

import type { BetterSupabaseConfig } from "../../../src/config/index.ts";

import { runSql } from "../../../src/cli/commands/sql.ts";
import { readIfExists } from "../../../src/cli/core/io.ts";
import { moduleLayoutFor } from "../../../src/cli/sql-layout.ts";
import { SQL_ARGS } from "../../../src/cli/sql/args.ts";
import { resolveConfig } from "../../../src/config/index.ts";
import { declaredTables } from "../../../src/sql/schema-scan.ts";
import {
  MIXED_SCHEMAS_BLOCKS,
  MIXED_SCHEMAS_CONFIG,
} from "../../fixtures/mixed-schemas/config.ts";
import { moduleSnapshotFixture } from "../fixtures/library.ts";

const FIXTURE = join(import.meta.dirname, "../../fixtures/mixed-schemas");

const SCHEMAS = "supabase/schemas";
const INVOICES = `${SCHEMAS}/900_better_supabase_098_invoices.sql`;
const CONTACTS = `${SCHEMAS}/900_better_supabase_093_contacts.sql`;
const ORGANIZATIONS = `${SCHEMAS}/900_better_supabase_021_organizations.sql`;
const APP_TABLES = `${SCHEMAS}/900_better_supabase_app_tables.sql`;

/** The app's tables, as its own schema files create them. */
const APP = {
  "public.organizations": `${SCHEMAS}/public/tables/organizations.sql`,
  "public.invoices": `${SCHEMAS}/public/tables/invoices.sql`,
  "public.contacts": `${SCHEMAS}/public/tables/contacts.sql`,
  "public.notes": `${SCHEMAS}/public/tables/notes.sql`,
} as const;

const unquote = (text: string): string => text.replaceAll('"', "");

/** The columns `sql` adds to `table` with `add column if not exists`. */
const addedColumns = (sql: string, table: string): string[] =>
  [
    ...unquote(sql).matchAll(
      new RegExp(
        `alter table ${table.replace(".", "\\.")} add column if not exists (\\w+)`,
        "g",
      ),
    ),
  ].map((match) => match[1]!);

describe("an app's own declarative schema with blocks over it", () => {
  let root: string;

  beforeEach(async () => {
    root = await mkdtemp(join(tmpdir(), "bsb-mixed-schemas-"));
    await cp(join(FIXTURE, "supabase"), join(root, "supabase"), {
      recursive: true,
    });
  });

  afterEach(async () => {
    await rm(root, { recursive: true, force: true });
  });

  const sql = (
    argv: string[],
    config: BetterSupabaseConfig = MIXED_SCHEMAS_CONFIG,
  ) => runSql(resolveConfig(config, root), parseArgs(argv, SQL_ARGS));

  const read = (path: string): Promise<string> =>
    readFile(join(root, path), "utf-8");

  it("finds the app's tables and their columns in its schema files", async () => {
    const layout = await moduleLayoutFor(
      resolveConfig(MIXED_SCHEMAS_CONFIG, root),
      { names: Object.keys(MIXED_SCHEMAS_BLOCKS) },
    );

    expect(layout.ownTables).toEqual(APP);
    expect(layout.ownColumns).toMatchObject({
      "public.invoices": [
        "id",
        "organization_id",
        "number",
        "status",
        "currency",
        "issued_on",
        "due_on",
        "note",
        "created_at",
      ],
      "public.contacts": [
        "id",
        "organization_id",
        "name",
        "email",
        "created_at",
      ],
      "public.notes": ["id", "body"],
    });
    expect(layout.ownIndexes?.["public.contacts"]).toContainEqual({
      columns: ["id"],
    });
  });

  it("adds the saved snapshot's tables, while the app's files still win", async () => {
    await writeFile(
      join(root, "supabase/snapshot.json"),
      JSON.stringify(moduleSnapshotFixture),
    );

    const layout = await moduleLayoutFor(
      resolveConfig(
        {
          ...MIXED_SCHEMAS_CONFIG,
          database: { source: { snapshot: "supabase/snapshot.json" } },
        },
        root,
      ),
      { names: Object.keys(MIXED_SCHEMAS_BLOCKS) },
    );

    expect(layout.ownTables).toMatchObject({
      ...APP,
      "public.customers": "database",
    });
    expect(layout.ownTables).not.toHaveProperty("better_supabase.memberships");
    expect(layout.ownColumns?.["public.customers"]).toContain(
      "organization_id",
    );
    expect(layout.ownUpdatedAtTriggers).toMatchObject({
      "public.customers": "customers_set_updated_at",
    });
    expect(layout.ownUpdatedAtTriggers).not.toHaveProperty(
      "public.notifications",
    );
    expect(layout.ownIndexes?.["public.customers"]).toBeInstanceOf(Array);
    expect(layout.ownIndexes?.["public.contacts"]).toContainEqual({
      columns: ["id"],
    });
  });

  it("takes the snapshot's views as the app's, with whether Postgres writes through them", async () => {
    const view = (id: number, name: string, updatable: boolean) => ({
      id,
      schema: "public",
      name,
      is_updatable: updatable,
      comment: null,
    });

    const column = (tableId: number, table: string, name: string) => ({
      ...moduleSnapshotFixture.generator.columns[0]!,
      table_id: tableId,
      schema: "public",
      table,
      id: `${String(tableId)}.1`,
      name,
    });

    await writeFile(
      join(root, "supabase/snapshot.json"),
      JSON.stringify({
        ...moduleSnapshotFixture,
        generator: {
          ...moduleSnapshotFixture.generator,
          views: [
            view(9_000_001, "member_roles", false),
            view(9_000_002, "open_invoices", true),
          ],
          columns: [
            ...moduleSnapshotFixture.generator.columns,
            column(9_000_001, "member_roles", "role"),
            column(9_000_002, "open_invoices", "id"),
          ],
        },
      }),
    );

    const layout = await moduleLayoutFor(
      resolveConfig(
        {
          ...MIXED_SCHEMAS_CONFIG,
          database: { source: { snapshot: "supabase/snapshot.json" } },
        },
        root,
      ),
      { names: Object.keys(MIXED_SCHEMAS_BLOCKS) },
    );

    expect(layout.ownViews).toMatchObject({
      "public.member_roles": { updatable: false },
      "public.open_invoices": { updatable: true },
    });
    expect(layout.ownColumns?.["public.member_roles"]).toEqual(["role"]);
  });

  it("creates the block tables the app lacks and none of the app's", async () => {
    expect((await sql(["sync"])).code).toBe(0);

    const files = await Promise.all(
      [ORGANIZATIONS, INVOICES, CONTACTS, APP_TABLES].map(async (path) => ({
        text: await read(path),
      })),
    );

    const created = declaredTables(files, ["public", "better_supabase"]);

    expect(created.filter((table) => table in APP)).toEqual([]);
    expect(created).toEqual(
      expect.arrayContaining([
        "better_supabase.invoice_lines",
        "better_supabase.companies",
        "better_supabase.company_people",
      ]),
    );
  });

  it("adds only the columns the app's tables lack", async () => {
    await sql(["sync"]);

    const invoices = addedColumns(await read(INVOICES), "public.invoices");
    expect(invoices).toEqual(expect.arrayContaining(["kind", "updated_at"]));
    expect(invoices).not.toEqual(
      expect.arrayContaining(["status", "number", "currency", "note"]),
    );
    expect(invoices).not.toContain("organization_id");

    const contacts = addedColumns(await read(CONTACTS), "public.contacts");
    expect(contacts).toEqual(
      expect.arrayContaining(["phone", "lifecycle", "updated_at"]),
    );
    expect(contacts).not.toEqual(expect.arrayContaining(["name"]));
    expect(contacts).not.toContain("email");

    expect(
      addedColumns(await read(ORGANIZATIONS), "public.organizations"),
    ).not.toContain("name");
  });

  it("casts its writes to the app's enum status", async () => {
    await sql(["sync"]);

    expect(unquote(await read(INVOICES))).toMatch(
      /status = better_supabase\.as_column_type\(/,
    );
  });

  it("names its policies and triggers on the app's tables bsb_ and keeps the app's", async () => {
    await sql(["sync"]);

    const text = unquote(
      (
        await Promise.all(
          [ORGANIZATIONS, INVOICES, CONTACTS, APP_TABLES].map(read),
        )
      ).join("\n"),
    );

    const named = [
      ...text.matchAll(
        /(?:create|drop|alter) policy (?:if exists )?(\S+) on ([\w.]+)/gi,
      ),
      ...text.matchAll(
        /(?:create (?:or replace )?(?:constraint )?|drop |alter )trigger (?:if exists )?(\S+)\s[\s\S]*?\bon ([\w.]+)/gi,
      ),
    ]
      .filter((match) => (match[2] ?? "") in APP)
      .map((match) => `${match[2]!}: ${match[1]!}`);

    expect(named.length).toBeGreaterThan(0);
    expect(named.filter((name) => !name.includes(": bsb_"))).toEqual([]);
    expect(text).toContain(
      "create policy bsb_tenant_scope_select on public.invoices as restrictive",
    );
    expect(text).not.toMatch(
      /(?:create|drop|alter) policy (?:if exists )?members read invoices/,
    );
    expect(text).toContain(
      "-- public.invoices: the app's policy members read invoices already allows what bsb_invoices_select would, so the block adds none.",
    );
    expect(text).not.toContain("create policy bsb_invoices_select");

    for (const table of Object.keys(APP)) {
      expect(text).not.toContain(`revoke all on ${table} from`);
    }
  });

  it("enriches the app's notes with an owner, a not valid check and the scope", async () => {
    await sql(["sync"]);

    const text = unquote(await read(APP_TABLES));

    expect(addedColumns(text, "public.notes")).toEqual([
      "organization_id",
      "created_at",
      "updated_at",
    ]);
    expect(text).not.toContain("create table if not exists public.notes");
    expect(text).toMatch(
      /add constraint notes_organization_id_not_null\s+check \(organization_id is not null\) not valid/,
    );
    expect(text).toContain(
      "public.notes keeps the app's own grants; these add what the scope needs.",
    );
    expect(text).toContain(
      "create policy bsb_tenant_scope_select on public.notes as restrictive",
    );
  });

  it("creates a table once the app's schema no longer has it", async () => {
    await rm(join(root, APP["public.contacts"]));
    await sql(["sync"]);

    const text = unquote(await read(CONTACTS));

    expect(text).toContain("create table if not exists public.contacts (");
    expect(addedColumns(text, "public.contacts")).toEqual([]);
    expect(unquote(await read(INVOICES))).not.toContain(
      "create table if not exists public.invoices",
    );
  });

  it("leaves a block file edited by hand alone until --force", async () => {
    await sql(["sync"]);

    const edited = `${await read(INVOICES)}\n-- mine\n`;
    await writeFile(join(root, INVOICES), edited);

    const kept = await sql(["sync"]);
    expect(kept.code).toBe(1);
    expect(kept.error).toContain("was edited by hand");
    expect(await read(INVOICES)).toBe(edited);

    expect((await sql(["sync", "--force"])).code).toBe(0);
    expect(await read(INVOICES)).not.toContain("-- mine");
  });

  it("removes a dropped block's file and never the app's schema files", async () => {
    await sql(["sync"]);

    const { contacts: _dropped, ...blocks } = MIXED_SCHEMAS_BLOCKS;

    const removed = await sql(["sync"], { ...MIXED_SCHEMAS_CONFIG, blocks });

    expect(removed.output).toContain(`Removed ${CONTACTS}`);
    expect(await readIfExists(join(root, CONTACTS))).toBeUndefined();

    for (const path of Object.values(APP)) {
      expect(await readIfExists(join(root, path))).toBeDefined();
    }
  });
});
