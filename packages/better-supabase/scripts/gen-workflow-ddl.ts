/**
 * Generates `src/sql/modules/workflow-sdk-world-ddl.generated.ts`, the `workflow` schema
 * the Supabase World stores runs in, from the migrations
 * `@workflow/world-postgres` ships.
 *
 * The migrations aren't idempotent and some rewrite data, so they can't go
 * into a SQL module as they are. This applies them to a scratch database on
 * the local stack, reads the resulting catalog and renders it as
 * `create ... if not exists` DDL. It also records each migration's SHA-256;
 * `tests/sql/modules/workflow-sdk-world-ddl.test.ts` fails when the installed
 * package's migrations no longer match.
 *
 * `node scripts/gen-workflow-ddl.ts` writes the file; `--check` only compares.
 * Needs `$SUPABASE_DB_URL` (defaults to the repo stack on 55422).
 */
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Client } from "pg";

export const WORLD_POSTGRES_PACKAGE = "@workflow/world-postgres";

export interface WorldMigration {
  readonly tag: string;
  readonly sha256: string;
  readonly sql: string;
}

export function migrationsDir(): string {
  const entry = fileURLToPath(import.meta.resolve(WORLD_POSTGRES_PACKAGE));
  return join(dirname(entry), "..", "src", "drizzle", "migrations");
}

export async function worldPostgresVersion(): Promise<string> {
  const pkg: unknown = JSON.parse(
    await readFile(
      join(migrationsDir(), "..", "..", "..", "package.json"),
      "utf8",
    ),
  );
  if (typeof pkg === "object" && pkg !== null && "version" in pkg) {
    return String(pkg.version);
  }
  throw new Error(`no version in ${WORLD_POSTGRES_PACKAGE}/package.json`);
}

export async function readMigrations(): Promise<WorldMigration[]> {
  const dir = migrationsDir();
  const journal: unknown = JSON.parse(
    await readFile(join(dir, "meta", "_journal.json"), "utf8"),
  );
  const entries =
    typeof journal === "object" && journal !== null && "entries" in journal
      ? journal.entries
      : undefined;
  if (!Array.isArray(entries))
    throw new Error("the migration journal has no entries");
  const list: unknown[] = entries;
  const migrations: WorldMigration[] = [];
  for (const entry of list) {
    const tag: unknown =
      typeof entry === "object" && entry !== null && "tag" in entry
        ? entry.tag
        : undefined;
    if (typeof tag !== "string") throw new Error("a journal entry has no tag");
    const sql = await readFile(join(dir, `${tag}.sql`), "utf8");
    migrations.push({
      tag,
      sha256: createHash("sha256").update(sql).digest("hex"),
      sql,
    });
  }
  return migrations;
}

/** Runs the migrations in one transaction, the way drizzle's migrator does. */
export async function applyMigrations(
  client: Client,
  migrations: readonly WorldMigration[],
): Promise<void> {
  await client.query("begin");
  try {
    for (const migration of migrations) {
      for (const statement of migration.sql.split("--> statement-breakpoint")) {
        if (statement.trim() !== "") await client.query(statement);
      }
    }
    await client.query("commit");
  } catch (error) {
    await client.query("rollback");
    throw error;
  }
}

interface Row {
  readonly [column: string]: unknown;
}

const text = (row: Row, key: string): string => String(row[key]);

/**
 * The `workflow` schema as idempotent DDL. Tables get `create table if not
 * exists` and then `add column if not exists` per column, so an older install
 * picks up new columns; a changed key or type needs a module upgrade step.
 */
export async function renderSchema(
  client: Client,
  schema = "workflow",
): Promise<string> {
  await client.query("set search_path = pg_catalog");
  const out: string[] = [`create schema if not exists ${schema};`];

  const enums = await client.query<Row>(
    `select t.typname as name,
            array_agg(e.enumlabel order by e.enumsortorder)::text[] as labels
       from pg_type t
       join pg_namespace n on n.oid = t.typnamespace
       join pg_enum e on e.enumtypid = t.oid
      where n.nspname = $1
      group by t.typname
      order by t.typname`,
    [schema],
  );
  for (const row of enums.rows) {
    const labels = (Array.isArray(row["labels"]) ? row["labels"] : [])
      .map((label) => `'${String(label)}'`)
      .join(", ");
    out.push(
      [
        "do $$ begin",
        `  create type ${schema}.${text(row, "name")} as enum (${labels});`,
        "exception when duplicate_object then null;",
        "end $$;",
      ].join("\n"),
    );
  }

  const tables = await client.query<Row>(
    `select c.oid, c.relname as name
       from pg_class c
       join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = $1 and c.relkind = 'r'
      order by c.relname`,
    [schema],
  );
  for (const table of tables.rows) {
    const qualified = `${schema}.${text(table, "name")}`;
    const columns = await client.query<Row>(
      `select a.attname as name,
              format_type(a.atttypid, a.atttypmod) as type,
              a.attnotnull as not_null,
              pg_get_expr(d.adbin, d.adrelid) as default_expr,
              pg_get_serial_sequence($2, a.attname) as serial
         from pg_attribute a
         left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
        where a.attrelid = $1 and a.attnum > 0 and not a.attisdropped
        order by a.attnum`,
      [table["oid"], qualified],
    );
    const definitions = columns.rows.map((column) => {
      const serial = column["serial"] !== null;
      const type = serial
        ? text(column, "type") === "bigint"
          ? "bigserial"
          : "serial"
        : text(column, "type");
      const parts = [`"${text(column, "name")}"`, type];
      if (column["not_null"] === true && !serial) parts.push("not null");
      if (column["default_expr"] !== null && !serial) {
        parts.push(`default ${text(column, "default_expr")}`);
      }
      return parts.join(" ");
    });
    const constraints = await client.query<Row>(
      `select conname as name, pg_get_constraintdef(oid) as definition
         from pg_constraint
        where conrelid = $1
        order by contype, conname`,
      [table["oid"]],
    );
    const body = [
      ...definitions,
      ...constraints.rows.map(
        (row) => `constraint "${text(row, "name")}" ${text(row, "definition")}`,
      ),
    ];
    out.push(
      `create table if not exists ${qualified} (\n  ${body.join(",\n  ")}\n);`,
      `alter table ${qualified}\n  ${definitions
        .map((definition) => `add column if not exists ${definition}`)
        .join(",\n  ")};`,
    );

    const indexes = await client.query<Row>(
      `select pg_get_indexdef(i.indexrelid) as definition
         from pg_index i
         join pg_class c on c.oid = i.indexrelid
        where i.indrelid = $1
          and not exists (select 1 from pg_constraint k where k.conindid = i.indexrelid)
        order by c.relname`,
      [table["oid"]],
    );
    for (const row of indexes.rows) {
      out.push(
        `${text(row, "definition")
          .replace(
            /^CREATE UNIQUE INDEX /,
            "create unique index if not exists ",
          )
          .replace(/^CREATE INDEX /, "create index if not exists ")};`,
      );
    }
  }
  return `${out.join("\n\n")}\n`;
}

/** Applies the migrations to a scratch database and renders the result. */
export async function generateDdl(
  dbUrl: string,
  migrations: readonly WorldMigration[],
): Promise<string> {
  const scratch = `bs_workflow_ddl_${process.pid}`;
  const admin = new Client({ connectionString: dbUrl });
  await admin.connect();
  try {
    await admin.query(`drop database if exists ${scratch}`);
    await admin.query(`create database ${scratch}`);
    const url = new URL(dbUrl);
    url.pathname = `/${scratch}`;
    const client = new Client({ connectionString: url.toString() });
    await client.connect();
    try {
      await applyMigrations(client, migrations);
      return await renderSchema(client);
    } finally {
      await client.end();
    }
  } finally {
    await admin.query(`drop database if exists ${scratch} with (force)`);
    await admin.end();
  }
}

export function renderModuleFile(
  version: string,
  migrations: readonly WorldMigration[],
  ddl: string,
): string {
  const manifest = migrations
    .map(
      (migration) =>
        `  { tag: "${migration.tag}", sha256: "${migration.sha256}" },`,
    )
    .join("\n");
  return `// Generated by scripts/gen-workflow-ddl.ts from ${WORLD_POSTGRES_PACKAGE} ${version}. Do not edit.

/** The \`${WORLD_POSTGRES_PACKAGE}\` version the DDL below was generated from. */
export const WORLD_POSTGRES_VERSION = "${version}";

/** The migrations the DDL reproduces, in journal order. */
export const WORLD_POSTGRES_MIGRATIONS: readonly { readonly tag: string; readonly sha256: string }[] = [
${manifest}
];

/** The \`workflow\` schema after every migration above, as idempotent DDL. */
export const WORLD_POSTGRES_DDL = \`${ddl.replaceAll("\\", "\\\\").replaceAll("`", "\\`").replaceAll("${", "\\${")}\`;
`;
}

export const OUTPUT: string = fileURLToPath(
  new URL(
    "../src/sql/modules/workflow-sdk-world-ddl.generated.ts",
    import.meta.url,
  ),
);

if (import.meta.main) {
  const dbUrl =
    process.env["SUPABASE_DB_URL"] ??
    "postgresql://postgres:postgres@127.0.0.1:55422/postgres";
  const migrations = await readMigrations();
  const contents = renderModuleFile(
    await worldPostgresVersion(),
    migrations,
    await generateDdl(dbUrl, migrations),
  );
  if (process.argv.includes("--check")) {
    const current = await readFile(OUTPUT, "utf8").catch(() => "");
    if (current !== contents) {
      console.error(`stale: ${OUTPUT}`);
      process.exitCode = 1;
    }
  } else {
    await writeFile(OUTPUT, contents);
    console.log(`wrote ${OUTPUT}`);
  }
}
