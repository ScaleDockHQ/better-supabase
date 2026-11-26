import { createHash } from "node:crypto";

import type { Obj } from "../schema-reader/ast.ts";

import {
  bodyOf,
  list,
  obj,
  str,
  strings,
  unwrap,
} from "../schema-reader/ast.ts";
import { parseStatements } from "../schema-reader/index.ts";

/** A literal in a natural key. */
export type KeyValue = string | number | boolean;

/** One row an upsert declares, identified by its natural key. */
export interface DeclaredRow {
  /** `schema.table`, schema `public` when the file names none. */
  readonly table: string;
  readonly keyColumns: readonly string[];
  readonly key: readonly KeyValue[];
}

/** One upsert statement: its rows and the text a migration repeats. */
export interface DeclaredUpsert {
  readonly table: string;
  readonly rows: readonly DeclaredRow[];
  /** The statement as written, without the closing `;`. */
  readonly text: string;
}

/** What `supabase/rows/<name>.sql` declares. */
export interface DeclaredFile {
  readonly name: string;
  readonly upserts: readonly DeclaredUpsert[];
  /** The file asks to delete a row that was removed from it. */
  readonly deleteRemoved: boolean;
  /** SHA-256 of the statements, comments and whitespace left out. */
  readonly hash: string;
}

/** A file that is not a list of upserts. */
export class DeclaredRowsError extends Error {
  override readonly name = "DeclaredRowsError";
}

/** The line that lets a removed row delete its database row. */
const DELETE_REMOVED = "-- bsb-rows: delete-removed";

/** Function calls a value may use; every one is deterministic. */
const ALLOWED_CALLS: ReadonlySet<string> = new Set([
  "jsonb_build_object",
  "jsonb_build_array",
  "to_jsonb",
]);

/** The hash a migration stamps: the statements, normalized. */
function statementsHash(texts: readonly string[]): string {
  return createHash("sha256")
    .update(
      texts.map((text) => text.replaceAll(/\s+/g, " ").trim()).join(";\n"),
    )
    .digest("hex");
}

/** A literal's value, or undefined when the node is not one. */
function literalOf(node: unknown): KeyValue | undefined {
  const cast = bodyOf(node, "TypeCast");

  if (cast !== undefined) {
    return literalOf(cast["arg"]);
  }

  const constant = bodyOf(node, "A_Const");

  if (constant === undefined || constant["isnull"] === true) {
    return undefined;
  }

  const text = str(obj(constant["sval"])["sval"]);

  if (text !== undefined) {
    return text;
  }

  const integer = obj(constant["ival"])["ival"];

  if (typeof integer === "number") {
    return integer;
  }

  const real = str(obj(constant["fval"])["fval"]);

  if (real !== undefined) {
    return Number(real);
  }

  const flag = obj(constant["boolval"])["boolval"];

  return typeof flag === "boolean" ? flag : undefined;
}

/** The first node in `tree` a value must not contain, or undefined. */
function forbidden(tree: unknown): string | undefined {
  if (Array.isArray(tree)) {
    for (const item of tree) {
      const found = forbidden(item);

      if (found !== undefined) {
        return found;
      }
    }

    return undefined;
  }

  if (typeof tree !== "object" || tree === null) {
    return undefined;
  }

  for (const [key, child] of Object.entries(tree)) {
    if (key === "SubLink") {
      return "a subquery";
    }

    if (key === "FuncCall") {
      const name = strings(obj(child)["funcname"]).at(-1);

      if (name === undefined || !ALLOWED_CALLS.has(name)) {
        return `the function ${name ?? "call"}`;
      }
    }

    const found = forbidden(child);

    if (found !== undefined) {
      return found;
    }
  }

  return undefined;
}

const qualified = (relation: Obj): string =>
  `${str(relation["schemaname"]) ?? "public"}.${str(relation["relname"]) ?? ""}`;

function upsertOf(
  file: string,
  index: number,
  insert: Obj,
  text: string,
): DeclaredUpsert {
  const where = `${file}: statement ${String(index + 1)}`;
  const table = qualified(obj(insert["relation"]));
  const conflict = obj(insert["onConflictClause"]);

  if (
    insert["withClause"] !== undefined ||
    insert["returningList"] !== undefined
  ) {
    throw new DeclaredRowsError(
      `${where} must be a plain insert ... on conflict (...) do update; remove the with or returning clause.`,
    );
  }

  if (conflict["action"] !== "ONCONFLICT_UPDATE") {
    throw new DeclaredRowsError(
      `${where} is not an upsert: ${table} needs on conflict (<natural key>) do update set ..., so a changed row reaches the database.`,
    );
  }

  const keyColumns = list(obj(conflict["infer"])["indexElems"]).flatMap(
    (element) => {
      const name = str(bodyOf(element, "IndexElem")?.["name"]);

      return name === undefined ? [] : [name];
    },
  );

  if (keyColumns.length === 0) {
    throw new DeclaredRowsError(
      `${where} names no natural key: write on conflict (<columns>) do update.`,
    );
  }

  const columns = list(insert["cols"]).flatMap((column) => {
    const name = str(bodyOf(column, "ResTarget")?.["name"]);

    return name === undefined ? [] : [name];
  });

  const select = obj(obj(insert["selectStmt"])["SelectStmt"]);
  const lists = list(select["valuesLists"]);

  if (lists.length === 0) {
    throw new DeclaredRowsError(
      `${where} must insert literal rows with values (...), not a select.`,
    );
  }

  const missing = keyColumns.filter((column) => !columns.includes(column));

  if (missing.length > 0) {
    throw new DeclaredRowsError(
      `${where} names ${missing.join(", ")} in on conflict but does not insert it.`,
    );
  }

  const rows = lists.map((entry, position): DeclaredRow => {
    const items = list(obj(unwrap(entry)?.[1])["items"]);

    if (items.length !== columns.length) {
      throw new DeclaredRowsError(
        `${where} row ${String(position + 1)} has ${String(items.length)} values for ${String(columns.length)} columns.`,
      );
    }

    const problem = forbidden(items);

    if (problem !== undefined) {
      throw new DeclaredRowsError(
        `${where} row ${String(position + 1)} uses ${problem}; a declared row holds literals, casts and jsonb_build_object.`,
      );
    }

    const key = keyColumns.map((column) => {
      const value = literalOf(items[columns.indexOf(column)]);

      if (value === undefined) {
        throw new DeclaredRowsError(
          `${where} row ${String(position + 1)}: ${column} is part of the natural key and must be a literal that is not null.`,
        );
      }

      return value;
    });

    return { table, keyColumns, key };
  });

  return { table, rows, text };
}

/**
 * Reads one rows file. Every statement must be an upsert of literal rows by a
 * natural key: `insert into t (...) values (...) on conflict (key) do update
 * set ...`. Anything else throws a `DeclaredRowsError`, because a rows file is
 * data the app owns, and a statement that is not an upsert cannot be repeated.
 */
export async function getDeclaredFile(
  name: string,
  text: string,
): Promise<DeclaredFile> {
  const bytes = Buffer.from(text, "utf-8");
  const statements = await parseStatements(text, { path: name });

  const upserts = statements.map((statement, index) => {
    const unwrapped = unwrap(statement.stmt);

    if (unwrapped?.[0] !== "InsertStmt") {
      throw new DeclaredRowsError(
        `${name}: statement ${String(index + 1)} is not an insert. A rows file holds upserts only.`,
      );
    }

    const end =
      statement.length === 0
        ? bytes.length
        : statement.start + statement.length;

    const slice = bytes.toString("utf-8", statement.start, end);

    // The text a migration repeats starts at the insert, not at a comment before it.
    const at = slice.search(/\binsert\b/i);

    return upsertOf(
      name,
      index,
      unwrapped[1],
      slice.slice(Math.max(at, 0)).trim(),
    );
  });

  return {
    name,
    upserts,
    deleteRemoved: text
      .split("\n")
      .some((line) => line.trim() === DELETE_REMOVED),
    hash: statementsHash(upserts.map((upsert) => upsert.text)),
  };
}

/** The key as the text that identifies the row in a report. */
export const rowLabel = (row: DeclaredRow): string =>
  `${row.table} (${row.key.map(String).join(", ")})`;

const sqlIdent = (name: string): string => `"${name.replaceAll('"', '""')}"`;

const literal = (value: KeyValue): string =>
  typeof value === "string"
    ? `'${value.replaceAll("'", "''")}'`
    : String(value);

/** `delete from <table> where <key columns> = <key>;` for a removed row. */
export function deleteStatement(row: DeclaredRow): string {
  const [schema, table] = row.table.split(".");

  return `delete from ${sqlIdent(schema ?? "public")}.${sqlIdent(table ?? "")} where ${row.keyColumns
    .map(
      (column, index) =>
        `${sqlIdent(column)} = ${literal(row.key[index] ?? "")}`,
    )
    .join(" and ")};`;
}
