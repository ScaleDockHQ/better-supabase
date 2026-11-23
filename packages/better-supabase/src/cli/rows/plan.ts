import type { DeclaredFile, DeclaredRow } from "./read.ts";

import { migrationFile } from "../sql/migration-names.ts";
import { deleteStatement, readDeclaredFile, rowLabel } from "./read.ts";

/** The line a data migration carries, so a later run finds it. */
const STAMP = /^-- @bsb-rows (\S+) sha256:([0-9a-f]{64})$/m;

/** Where the statements end and the removals begin in a migration. */
const REMOVALS = "-- @bsb-rows-removed";

/** `<stamp>_declared_rows_<name>.sql` without the stamp and the hash. */
const suffixOf = (name: string): string =>
  `_declared_rows_${name.replaceAll(/[^a-z0-9]+/gi, "_").toLowerCase()}.sql`;

export interface RowsMigration {
  /** The rows file, such as `priorities`. */
  readonly source: string;
  /** The migration file to write. */
  readonly file: string;
  readonly text: string;
}

export interface RowsPlan {
  /** Migrations to write, one per rows file whose hash no migration carries. */
  readonly migrations: readonly RowsMigration[];
  /** Rows files whose latest migration carries their current hash. */
  readonly current: readonly string[];
  /** One line per row a file no longer declares. */
  readonly review: readonly string[];
}

interface Stamped {
  readonly file: string;
  readonly hash: string;
  readonly text: string;
}

/** The migrations a rows file stamped, oldest first. */
function stampedFor(
  name: string,
  migrations: ReadonlyMap<string, string>,
): readonly Stamped[] {
  return [...migrations]
    .toSorted(([a], [b]) => a.localeCompare(b))
    .flatMap(([file, text]) => {
      const match = STAMP.exec(text);

      return match?.[1] === name && match[2] !== undefined
        ? [{ file, hash: match[2], text }]
        : [];
    });
}

/** The rows the statements of a stamped migration declared. */
async function rowsOf(
  name: string,
  text: string,
): Promise<readonly DeclaredRow[]> {
  const statements = text.split(REMOVALS)[0] ?? "";

  const file = await readDeclaredFile(
    name,
    statements
      .split("\n")
      .filter((line) => !line.startsWith("--"))
      .join("\n"),
  );

  return file.upserts.flatMap((upsert) => upsert.rows);
}

const keyOf = (row: DeclaredRow): string =>
  JSON.stringify([row.table, row.key]);

function migrationText(
  file: DeclaredFile,
  removed: readonly DeclaredRow[],
): string {
  const header = `-- better-supabase db rows: supabase/rows/${file.name}.sql
-- @bsb-rows ${file.name} sha256:${file.hash}
-- Never edit this file. Change the rows file and run \`better-supabase db rows\`.`;

  const body = file.upserts.map((upsert) => `${upsert.text};`).join("\n\n");

  if (removed.length === 0) {
    return `${header}\n\n${body}\n`;
  }

  const lines = file.deleteRemoved
    ? removed.map((row) => deleteStatement(row))
    : removed.map(
        (row) => `-- review: ${rowLabel(row)} is no longer declared and stays`,
      );

  return `${header}\n\n${body}\n\n${REMOVALS}\n${lines.join("\n")}\n`;
}

/**
 * What `db rows` writes. `files` maps a rows file name to its text and
 * `migrations` maps a migration file name to its text. A rows file whose
 * statements hash like its latest stamped migration needs nothing; any other
 * gets a new migration (one that sorts after every existing name), so a
 * migration that was pushed is never changed. A row the file no longer declares
 * is reported, and deleted only when the file carries `-- bsb-rows:
 * delete-removed`.
 */
export async function planRows(
  files: ReadonlyMap<string, string>,
  migrations: ReadonlyMap<string, string>,
  now: Date,
): Promise<RowsPlan> {
  const planned: RowsMigration[] = [];
  const current: string[] = [];
  const review: string[] = [];
  const names = [...migrations.keys()];

  for (const [name, text] of [...files].toSorted(([a], [b]) =>
    a.localeCompare(b),
  )) {
    const file = await readDeclaredFile(name, text);
    const stamped = stampedFor(name, migrations);
    const latest = stamped.at(-1);

    if (latest?.hash === file.hash) {
      current.push(name);
      continue;
    }

    const declared = new Set(
      file.upserts.flatMap((upsert) => upsert.rows.map(keyOf)),
    );

    const removed =
      latest === undefined
        ? []
        : (await rowsOf(name, latest.text)).filter(
            (row) => !declared.has(keyOf(row)),
          );

    for (const row of removed) {
      review.push(
        file.deleteRemoved
          ? `${name}: ${rowLabel(row)} is removed from the file; the migration deletes it`
          : `${name}: ${rowLabel(row)} is removed from the file and stays in the database; add \`-- bsb-rows: delete-removed\` to the file to delete it, or write a migration`,
      );
    }

    const body = migrationText(file, removed);

    const target = await migrationFile(
      [...names, ...planned.map((each) => each.file)],
      now,
      suffixOf(name),
      body,
      false,
    );

    planned.push({ source: name, file: target.name, text: body });
  }

  return { migrations: planned, current, review };
}
