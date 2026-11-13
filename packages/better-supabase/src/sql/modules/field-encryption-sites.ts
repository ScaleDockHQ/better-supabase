import type { BlockSqlContext } from "../context.ts";
import type { BlockSqlLayout } from "../module-types.ts";

import { encryptedColumns } from "../../config/app-access.ts";
import { sqlIdent } from "../../core/template.ts";
import { appTableScope } from "./app-table-scope.ts";

/** Whose key encrypts a row: a tenant's, a user's or the app's. */
export type FieldKeyOwnerKind = "tenant" | "user" | "app";

/** An app table whose columns hold ciphertext under the field keys. */
export interface AppCipherTable {
  /** The table name in `public`. */
  readonly name: string;
  /** `public.<name>`, quoted. */
  readonly table: string;
  /** The encrypted column names. */
  readonly columns: readonly string[];
  readonly kind: FieldKeyOwnerKind;
  /** The key owner of row `x`, as text. */
  readonly owner: string;
}

/** The key owner of row `x` as text; `column` holds its tenant or user. */
function ownerOf(kind: FieldKeyOwnerKind, column: string): string {
  switch (kind) {
    case "tenant": {
      return `'tenant:' || (x.${sqlIdent(column)})::text`;
    }

    case "user": {
      return `'user:' || (x.${sqlIdent(column)})::text`;
    }

    case "app": {
      return "'app'";
    }

    default: {
      const never: never = kind;

      return never;
    }
  }
}

/** The default scope column of a kind of owner. */
const scopeColumn = (ctx: BlockSqlContext, kind: FieldKeyOwnerKind): string =>
  kind === "tenant" ? ctx.naming.rename("organization_id") : "user_id";

const IDENT = /^[a-z_][a-z0-9_$]{0,62}$/u;
const KINDS: readonly FieldKeyOwnerKind[] = ["tenant", "user", "app"];
const WHERE = "blocks.field-encryption.options.sealed";

const identOf = (value: unknown, where: string): string => {
  if (typeof value !== "string" || !IDENT.test(value)) {
    throw new TypeError(`${where} must be a lowercase SQL name`);
  }

  return value;
};

/** One `sealed` entry, checked. */
function sealedEntry(
  ctx: BlockSqlContext,
  entry: unknown,
  index: number,
): AppCipherTable {
  const where = `${WHERE}[${String(index)}]`;

  if (typeof entry !== "object" || entry === null || Array.isArray(entry)) {
    throw new TypeError(
      `${where} must be { table, columns, owner, column? }, such as { table: "public.client_notes", columns: ["diagnosis"], owner: "tenant" }`,
    );
  }

  const fields = new Map<string, unknown>(Object.entries(entry));
  const table = fields.get("table");

  const [schema, name, extra]: readonly (string | undefined)[] =
    typeof table === "string" ? table.split(".") : [];

  if (name === undefined || extra !== undefined) {
    throw new TypeError(`${where}.table must be schema.table`);
  }

  const columns = fields.get("columns");

  if (!Array.isArray(columns) || columns.length === 0) {
    throw new TypeError(`${where}.columns must list at least one column`);
  }

  const owner = KINDS.find((kind) => kind === fields.get("owner"));

  if (owner === undefined) {
    throw new TypeError(`${where}.owner must be tenant, user or app`);
  }

  const scope = fields.get("column");

  const column =
    scope === undefined
      ? scopeColumn(ctx, owner)
      : identOf(scope, `${where}.column`);

  return {
    name: schema === "public" ? name : `${schema}.${name}`,
    table: `${sqlIdent(identOf(schema, `${where}.table`))}.${sqlIdent(identOf(name, `${where}.table`))}`,
    columns: columns.map((each, at) =>
      identOf(each, `${where}.columns[${String(at)}]`),
    ),
    kind: owner,
    owner: ownerOf(owner, column),
  };
}

/** The columns `options.sealed` lists, which the app's own SQL seals. */
export function sealedColumns(ctx: BlockSqlContext): readonly AppCipherTable[] {
  const sealed = ctx.option("sealed");

  if (sealed === undefined) {
    return [];
  }

  if (!Array.isArray(sealed)) {
    throw new TypeError(`${WHERE} must be a list of { table, columns, owner }`);
  }

  return sealed.map((entry: unknown, index) => sealedEntry(ctx, entry, index));
}

/** The app tables that encrypt columns, with the owner of each row. */
export function encryptedAppTables(
  ctx: BlockSqlContext,
  layout: BlockSqlLayout,
): readonly AppCipherTable[] {
  return Object.entries(layout.appTables ?? {}).flatMap(
    ([name, config]): AppCipherTable[] => {
      const columns = encryptedColumns(config);

      if (columns.length === 0) {
        return [];
      }

      const scope = appTableScope(config, layout);
      const kind: FieldKeyOwnerKind = scope === "none" ? "app" : scope;

      return [
        {
          name,
          table: `${sqlIdent("public")}.${sqlIdent(name)}`,
          columns,
          kind,
          owner: ownerOf(kind, scopeColumn(ctx, kind)),
        },
      ];
    },
  );
}
