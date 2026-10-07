import type {
  CatalogForeignKey,
  CatalogIndex,
  CatalogTable,
} from "../introspect/types.ts";
import type { DoctorContext, FindingInput, Rule, TextFile } from "./rules.ts";

import { configFor } from "../gen/shared.ts";
import { splinterTables } from "./advisor-rules.ts";
import { escape, withoutStrings } from "./rls.ts";
import { catalogOf, exposed, qualified, tableObject } from "./shared.ts";

/** Whether the first `columns.length` columns of a non-partial index are exactly `columns`, in any order. */
const covers = (index: CatalogIndex, columns: readonly string[]): boolean =>
  !index.partial &&
  index.columns.length >= columns.length &&
  index.columns
    .slice(0, columns.length)
    .every((column) => columns.includes(column));

/** Foreign keys of `table` that no index starts with. */
const unindexedForeignKeys = (table: CatalogTable): CatalogForeignKey[] =>
  table.foreignKeys.filter(
    (key) => !table.indexes.some((index) => covers(index, key.columns)),
  );

const SOFT_DELETE = /^(?:deleted|archived)_at$/;

/** Operators that need a GIN index on jsonb or array columns. */
const CONTAINS = String.raw`(?:@>|<@|\?\||\?&|\?|&&)`;

/** `.contains("tags"`, `.containedBy('meta'`, `.overlaps("labels"`, supabase-js filters. */
const CLIENT_CONTAINS =
  /\.(?:contains|containedBy|overlaps)\(\s*["'`]([A-Za-z_]\w*)["'`]/g;

/** Column types Postgres' wiki and the Supabase skills advise against. */
const AVOID: Readonly<Record<string, string>> = {
  timestamp: "timestamptz",
  varchar: "text with a check constraint",
  bpchar: "text",
  money: "numeric",
  json: "jsonb",
};

/** A Supabase direct (`db.<ref>.supabase.co`) or session-pooler (`:5432`) connection string. */
const DIRECT_URL =
  /postgres(?:ql)?:\/\/[^\s"'`]*@(?:db\.[a-z0-9]+\.supabase\.co(?::5432)?|[\w.-]+\.pooler\.supabase\.com:5432)\b/i;

/** Files that show the app runs on serverless or edge functions. */
const SERVERLESS =
  /\bexport\s+(?:const\s+runtime|async\s+function\s+(?:GET|POST|PUT|PATCH|DELETE)|default\s+\{\s*(?:async\s+)?fetch)\b|\bDeno\.serve\(/;

function lines(file: TextFile): { line: number; text: string }[] {
  return file.text
    .split("\n")
    .map((text, index) => ({ line: index + 1, text }));
}

export const SCHEMA_DESIGN_RULES: readonly Rule[] = [
  {
    code: "BS216",
    severity: "info",
    title: "Foreign key without an index",
    description:
      "Deletes and updates on the referenced table scan the referencing table for each row, and joins on the key can't use an index. Add an index that starts with the key's columns. When the performance advisor (BS200) runs, splinter's `unindexed_foreign_keys` reports a table it covers and this rule skips it; on a saved snapshot this rule reports every table.",
    check: async (context) => {
      const splinter = await splinterTables(context, "unindexed_foreign_keys");
      return exposed(context).flatMap((table): FindingInput[] => {
        if (table.kind !== "table" || splinter?.has(qualified(table)))
          return [];
        return unindexedForeignKeys(table).map((key) => ({
          message: `${qualified(table)}.${key.name} (${key.columns.join(", ")}) has no index that starts with its columns, so deletes on ${key.refSchema}.${key.refTable} scan ${qualified(table)}. Run \`create index on ${qualified(table)} (${key.columns.join(", ")});\`.`,
          target: `${qualified(table)}.${key.name}`,
          object: tableObject(table),
        }));
      });
    },
  },
  {
    code: "BS217",
    severity: "warning",
    title: "Tenant foreign key that can cross tenants",
    description:
      "When a tenant table references another tenant table by `id` alone, a row can point at a parent in another organization; RLS checks each row, not the pair. Reference `(id, organization_id)` with a composite foreign key, backed by `unique (id, organization_id)` on the parent.",
    check: (context) => {
      const column = context.config.plugins.tenant?.column;
      if (!column) return [];
      const tables = new Map(
        catalogOf(context).tables.map((table) => [qualified(table), table]),
      );
      const hasTenant = (table: CatalogTable | undefined): boolean =>
        table?.columns.some((entry) => entry.name === column) ?? false;
      return exposed(context).flatMap((table): FindingInput[] => {
        if (table.kind !== "table" || !hasTenant(table)) return [];
        return table.foreignKeys.flatMap((key): FindingInput[] => {
          if (key.columns.includes(column)) return [];
          const parent = tables.get(`${key.refSchema}.${key.refTable}`);
          if (!hasTenant(parent) || parent === table) return [];
          return [
            {
              message: `${qualified(table)}.${key.name} references ${key.refSchema}.${key.refTable} (${key.refColumns.join(", ")}) without ${column}, so a row can point at another tenant's ${key.refTable}. Add \`unique (${[...key.refColumns, column].join(", ")})\` to ${key.refTable} and reference \`(${[...key.columns, column].join(", ")})\`.`,
              target: `${qualified(table)}.${key.name}`,
              object: tableObject(table),
            },
          ];
        });
      });
    },
  },
  {
    code: "BS218",
    severity: "info",
    title: "Soft-delete table without a partial index",
    description:
      "Queries on a table with `deleted_at` or `archived_at` read the live rows (`where deleted_at is null`). A partial index with that predicate stays small and matches those queries.",
    check: (context) =>
      exposed(context).flatMap((table): FindingInput[] => {
        if (table.kind !== "table") return [];
        const column = table.columns.find(
          (entry) => SOFT_DELETE.test(entry.name) && entry.nullable,
        );
        if (!column) return [];
        const isNull = new RegExp(
          `"?${escape(column.name)}"?\\s+IS\\s+NULL`,
          "i",
        );
        const indexed = table.indexes.some(
          (index) =>
            index.partial &&
            (index.predicate === undefined ||
              (index.predicate !== null && isNull.test(index.predicate))),
        );
        if (indexed) return [];
        return [
          {
            message: `${qualified(table)} soft-deletes with ${column.name}, but no index has \`where ${column.name} is null\`. Index the live rows you list, for example \`create index on ${qualified(table)} (created_at desc) where ${column.name} is null;\`.`,
            target: `${qualified(table)}.${column.name}`,
            object: tableObject(table),
          },
        ];
      }),
  },
  {
    code: "BS219",
    severity: "warning",
    title: "Containment filter on a column without a GIN index",
    description:
      "`@>`, `<@`, `?` and `&&` on jsonb and array columns, and the `.contains()`, `.containedBy()` and `.overlaps()` filters, can only use a GIN index. Without one, every query reads the whole table. Doctor looks in policies, exposed functions and `doctor.sources`.",
    check: (context) => {
      const tables = exposed(context).filter((table) => table.kind === "table");
      const policyText = (table: CatalogTable): string =>
        withoutStrings(
          table.policies
            .map((policy) => `${policy.using ?? ""} ${policy.check ?? ""}`)
            .join(" "),
        );
      const functions = context.snapshot.generator.functions
        .filter(
          (fn) => context.config.schemas.includes(fn.schema) && fn.definition,
        )
        .map((fn) => withoutStrings(fn.definition))
        .join("\n");
      const filtered = new Set<string>();
      for (const file of context.sources) {
        for (const match of file.text.matchAll(CLIENT_CONTAINS))
          filtered.add(match[1]!);
      }
      return tables.flatMap((table): FindingInput[] => {
        const own = policyText(table);
        const columns = table.columns.filter((column) => {
          if (!column.isArray && column.udt !== "jsonb") return false;
          const gin = table.indexes.some(
            (index) =>
              index.columns[0] === column.name &&
              (index.method === undefined || index.method === "gin"),
          );
          if (gin) return false;
          const used = new RegExp(
            `"?${escape(column.name)}"?\\s*${CONTAINS}|${CONTAINS}\\s*[\\w."]*\\b${escape(column.name)}\\b`,
          );
          return (
            filtered.has(column.name) ||
            used.test(own) ||
            (functions.includes(table.name) && used.test(functions))
          );
        });
        return columns.map((column) => ({
          message: `${qualified(table)}.${column.name} is filtered by containment but has no GIN index, so each query scans the table. Run \`create index on ${qualified(table)} using gin (${column.name}${column.udt === "jsonb" ? " jsonb_path_ops" : ""});\`${column.udt === "jsonb" ? " (`jsonb_path_ops` supports `@>` only; drop it for `?`)" : ""}.`,
          target: `${qualified(table)}.${column.name}`,
          object: tableObject(table),
        }));
      });
    },
  },
  {
    code: "BS220",
    severity: "info",
    title: "Column type to avoid",
    description:
      "`timestamp` drops the time zone, `varchar(n)` and `char(n)` only add a length check `text` does with a constraint, `money` rounds by locale and `json` reparses on every read. Use `timestamptz`, `text`, `numeric` and `jsonb`.",
    check: (context) =>
      exposed(context).flatMap((table): FindingInput[] => {
        if (table.kind !== "table") return [];
        const columns = table.columns.filter(
          (column) => column.typeSchema === "pg_catalog" && column.udt in AVOID,
        );
        if (columns.length === 0) return [];
        return [
          {
            message: `${qualified(table)}: ${columns.map((column) => `${column.name} is ${column.udt}, use ${AVOID[column.udt]}`).join("; ")}.`,
            target: qualified(table),
            object: tableObject(table),
          },
        ];
      }),
  },
  {
    code: "BS221",
    severity: "warning",
    title: "Direct database connection in a serverless app",
    description:
      "Each serverless or edge invocation opens its own connection. Through the direct host or the session pooler on port 5432 they exhaust `max_connections`; the transaction pooler on port 6543 shares them. The direct host is also IPv6 only.",
    check: (context: DoctorContext) => {
      const serverless =
        context.sources.some((file) => SERVERLESS.test(file.text)) ||
        context.envFiles.some((file) => /^\s*VERCEL\w*=/m.test(file.text));
      if (!serverless) return [];
      return context.envFiles.flatMap((file): FindingInput[] =>
        lines(file).flatMap(({ line, text }): FindingInput[] => {
          if (/^\s*#/.test(text) || !DIRECT_URL.test(text)) return [];
          const key = /^\s*(?:export\s+)?(\w+)\s*=/.exec(text)?.[1];
          return [
            {
              message: `${file.path}${key ? `:${key}` : ""} connects through port 5432 or the direct host, but the app runs on serverless functions. Use the transaction pooler: \`postgres://postgres.<ref>:<password>@<region>.pooler.supabase.com:6543/postgres\`.`,
              target: `${file.path}${key ? `:${key}` : ""}`,
              location: { file: file.path, line },
            },
          ];
        }),
      );
    },
  },
  {
    code: "BS222",
    severity: "warning",
    title: "Column that can exceed a JavaScript number",
    description:
      "`int8` and `numeric` decode as `number` by default, which matches `supabase gen types` but loses precision past 2^53 (or 15 to 17 significant digits). An `int8` identity or sequence keeps growing toward that limit, and `numeric` usually holds exact amounts. Set `codecs.int8` to `bigint` or `string`, or `codecs.numeric` to `string`.",
    check: (context) => {
      const { int8, numeric } = context.config.codecs;
      if (int8 !== "number" && numeric !== "number") return [];
      return exposed(context).flatMap((table): FindingInput[] => {
        if (configFor(context.config.tables, table.schema, table.name)?.exclude)
          return [];
        const columns = table.columns.filter((column) =>
          column.udt === "int8"
            ? int8 === "number" &&
              !column.isArray &&
              (column.identity !== null ||
                (column.default?.includes("nextval(") ?? false))
            : column.udt === "numeric" && numeric === "number",
        );
        if (columns.length === 0) return [];
        const codecs = [
          ...(columns.some((column) => column.udt === "int8")
            ? ['`int8: "bigint"`']
            : []),
          ...(columns.some((column) => column.udt === "numeric")
            ? ['`numeric: "string"`']
            : []),
        ];
        return [
          {
            message: `${qualified(table)} ${columns.map((column) => `${column.name} (${column.udt})`).join(", ")} decode as number and lose precision past 2^53. Set ${codecs.join(" and ")} in \`codecs\`.`,
            target: qualified(table),
            object: tableObject(table),
          },
        ];
      });
    },
  },
];
