import type { AppColumnType } from "../../config/index.ts";
import type {
  CatalogForeignKey,
  CatalogIndex,
  CatalogTable,
} from "../introspect/types.ts";
import type { DoctorContext, FindingInput, Rule, TextFile } from "./rules.ts";

import { configFor } from "../gen/shared.ts";
import { splinterTables } from "./advisor-rules.ts";
import { enrichedAppTables } from "./app-table-scope.ts";
import { escape, withoutStrings } from "./rls.ts";
import {
  catalogOf,
  exposed,
  exposedSchemas,
  lineOf,
  qualified,
  tableObject,
} from "./shared.ts";

/** The `format` the database reports for each app column type. */
const APP_COLUMN_FORMAT: Readonly<Record<AppColumnType, string>> = {
  text: "text",
  uuid: "uuid",
  integer: "int4",
  bigint: "int8",
  numeric: "numeric",
  boolean: "bool",
  timestamptz: "timestamptz",
  date: "date",
  jsonb: "jsonb",
  "text[]": "_text",
};

/**
 * Whether a partial index's predicate only skips rows where a key column is
 * null, like `(customer_id IS NOT NULL)`: those rows reference nothing, so the
 * index still serves the key.
 */
const skipsNullKeys = (
  predicate: string | null | undefined,
  columns: readonly string[],
): boolean => {
  if (!predicate) {
    return false;
  }

  return predicate
    .split(/\s+AND\s+/i)
    .every((part) =>
      columns.some((column) =>
        new RegExp(
          `^\\(*\\s*"?${escape(column)}"?\\s+IS\\s+NOT\\s+NULL\\s*\\)*$`,
          "i",
        ).test(part.trim()),
      ),
    );
};

/**
 * Whether the first `columns.length` columns of an index are exactly `columns`,
 * in any order, and it holds every row that references something.
 */
const covers = (index: CatalogIndex, columns: readonly string[]): boolean =>
  (!index.partial || skipsNullKeys(index.predicate, columns)) &&
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

/**
 * `.contains("tags"`, `.containedBy('meta'`, `.overlaps("labels"`, supabase-js
 * filters.
 */
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

/**
 * A Supabase direct (`db.<ref>.supabase.co`) or session-pooler (`:5432`)
 * connection string.
 */
const DIRECT_URL =
  /postgres(?:ql)?:\/\/[^\s"'`]*@(?:db\.[a-z0-9]+\.supabase\.co(?::5432)?|[\w.-]+\.pooler\.supabase\.com:5432)\b/i;

/** Files that show the app runs on serverless or edge functions. */
const SERVERLESS =
  /\bexport\s+(?:const\s+runtime|async\s+function\s+(?:GET|POST|PUT|PATCH|DELETE)|default\s+\{\s*(?:async\s+)?fetch)\b|\bDeno\.serve\(/;

/** A connection string through Supavisor's transaction pooler (port 6543). */
const TRANSACTION_POOLER = /postgres(?:ql)?:\/\/[^\s"'`]*:6543\b/i;

/** `import postgres from "postgres"` or `require("postgres")`: postgres.js. */
const POSTGRES_JS =
  /\bfrom\s+["']postgres["']|\brequire\(\s*["']postgres["']\s*\)/;

const PREPARE_OFF = /\bprepare\s*:\s*false\b/;

const PRISMA = /["']@prisma\/client["']|\bnew\s+PrismaClient\b/;

const OFFSET_PAGINATION = /\bpagination\s*:\s*["'`]offset["'`]/;

const EXACT_COUNT = /\bcount\s*:\s*["'`]exact["'`]/;

/** `format_type` names of scalar results that a JSON number can't hold exactly. */
const WIDE_RESULT = /^(?:bigint|numeric)(?:\[\])?$/;

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
      "Deletes and updates on the referenced table scan the referencing table for each row, and joins on the key can't use an index. Add an index that starts with the key's columns; a partial index counts when its `where` only skips rows whose key is null (`where customer_id is not null`). When the performance advisor (BS200) runs, splinter's `unindexed_foreign_keys` reports a table it covers and this rule skips it; on a saved snapshot this rule reports every table.",
    check: async (context) => {
      const splinter = await splinterTables(context, "unindexed_foreign_keys");

      return exposed(context).flatMap((table): FindingInput[] => {
        if (table.kind !== "table" || splinter?.has(qualified(table))) {
          return [];
        }

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
      const column = context.config.extensions.tenant?.column;

      if (!column) {
        return [];
      }

      const tables = new Map(
        catalogOf(context).tables.map((table) => [qualified(table), table]),
      );

      const hasTenant = (table: CatalogTable | undefined): boolean =>
        table?.columns.some((entry) => entry.name === column) ?? false;

      return exposed(context).flatMap((table): FindingInput[] => {
        if (table.kind !== "table" || !hasTenant(table)) {
          return [];
        }

        return table.foreignKeys.flatMap((key): FindingInput[] => {
          if (key.columns.includes(column)) {
            return [];
          }

          const parent = tables.get(`${key.refSchema}.${key.refTable}`);

          if (!hasTenant(parent) || parent === table) {
            return [];
          }

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
        if (table.kind !== "table") {
          return [];
        }

        const column = table.columns.find(
          (entry) => SOFT_DELETE.test(entry.name) && entry.nullable,
        );

        if (!column) {
          return [];
        }

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

        if (indexed) {
          return [];
        }

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
      "`@>`, `<@`, `?` and `&&` on jsonb and array columns, and the `.contains()`, `.containedBy()` and `.overlaps()` filters, can only use a GIN index. Without one, every query reads the whole table. Doctor looks in policies, exposed functions and `tooling.doctor.sources`.",
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
        for (const match of file.text.matchAll(CLIENT_CONTAINS)) {
          filtered.add(match[1]!);
        }
      }

      return tables.flatMap((table): FindingInput[] => {
        const own = policyText(table);

        const columns = table.columns.filter((column) => {
          if (!column.isArray && column.udt !== "jsonb") {
            return false;
          }

          const gin = table.indexes.some(
            (index) =>
              index.columns[0] === column.name &&
              (index.method === undefined || index.method === "gin"),
          );

          if (gin) {
            return false;
          }

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
        if (table.kind !== "table") {
          return [];
        }

        const columns = table.columns.filter(
          (column) => column.typeSchema === "pg_catalog" && column.udt in AVOID,
        );

        if (columns.length === 0) {
          return [];
        }

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

      if (!serverless) {
        return [];
      }

      return context.envFiles.flatMap((file): FindingInput[] =>
        lines(file).flatMap(({ line, text }): FindingInput[] => {
          if (/^\s*#/.test(text) || !DIRECT_URL.test(text)) {
            return [];
          }

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
      "`int8` and `numeric` decode as `number` by default, which matches `supabase gen types` but loses precision past 2^53 (or 15 to 17 significant digits). An `int8` identity or sequence keeps growing toward that limit, and `numeric` usually holds exact amounts. Set `gen.codecs.int8` to `bigint` or `string`, or `gen.codecs.numeric` to `string`.",
    check: (context) => {
      const { int8, numeric } = context.config.codecs;

      if (int8 !== "number" && numeric !== "number") {
        return [];
      }

      return exposed(context).flatMap((table): FindingInput[] => {
        if (
          configFor(context.config.tables, table.schema, table.name)?.exclude
        ) {
          return [];
        }

        const columns = table.columns.filter((column) =>
          column.udt === "int8"
            ? int8 === "number" &&
              !column.isArray &&
              (column.identity !== null ||
                (column.default?.includes("nextval(") ?? false))
            : column.udt === "numeric" && numeric === "number",
        );

        if (columns.length === 0) {
          return [];
        }

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
  {
    code: "BS223",
    severity: "info",
    title: "Function returns an int8 or numeric scalar",
    description:
      "PostgREST sends a scalar `int8` or `numeric` function result as a JSON number, which loses precision past 2^53 (or 15 to 17 significant digits) before any codec sees it. `$rpc` casts codec columns of table and record results to text, but a scalar has no column to cast. Return it as `text` when it can be that large.",
    check: (context) => {
      const schemas = exposedSchemas(context);

      return context.snapshot.generator.functions
        .filter(
          (fn) =>
            schemas.includes(fn.schema) && WIDE_RESULT.test(fn.return_type),
        )
        .map((fn) => ({
          message: `${fn.schema}.${fn.name}(${fn.identity_argument_types}) returns ${fn.is_set_returning_function ? "setof " : ""}${fn.return_type}, which PostgREST sends as a JSON number and \`$rpc\` can't cast. Return it as text (\`returns ${fn.return_type.replace("bigint", "text").replace("numeric", "text")}\`, \`select total::text\`) when it can pass 2^53, or add BS223 to \`tooling.doctor.ignore\` when it stays small.`,
          target: `${fn.schema}.${fn.name}`,
          object: { kind: "function", schema: fn.schema, name: fn.name },
        }));
    },
  },
  {
    code: "BS226",
    severity: "warning",
    title: "Prepared statements through the transaction pooler",
    description:
      "The transaction pooler on port 6543 hands each transaction to any server connection, so a named prepared statement from one transaction is missing in the next and the query fails with `prepared statement does not exist`. postgres.js prepares statements unless `prepare: false`, and Prisma does unless the URL has `pgbouncer=true`. `pg` (and `better-supabase/postgres`) sends unnamed statements, which are safe. Doctor looks for a `:6543` URL in the env files and `tooling.doctor.sources`.",
    check: (context) => {
      const urls = [...context.envFiles, ...context.sources].flatMap((file) =>
        lines(file)
          .filter(
            ({ text }) =>
              !/^\s*(?:#|\/\/)/.test(text) && TRANSACTION_POOLER.test(text),
          )
          .map(({ line, text }) => ({ file, line, text })),
      );

      if (urls.length === 0) {
        return [];
      }

      const findings: FindingInput[] = [];

      for (const file of context.sources) {
        if (!POSTGRES_JS.test(file.text) || PREPARE_OFF.test(file.text)) {
          continue;
        }

        findings.push({
          message: `${file.path} creates a postgres.js client without \`prepare: false\`, and the project connects through the transaction pooler on port 6543, so its prepared statements fail on the next transaction. Pass \`postgres(url, { prepare: false })\`.`,
          target: `${file.path}:postgres`,
          location: {
            file: file.path,
            line: lineOf(file.text, POSTGRES_JS) ?? 1,
          },
        });
      }

      if (!context.sources.some((file) => PRISMA.test(file.text))) {
        return findings;
      }

      for (const { file, line, text } of urls) {
        if (/[?&]pgbouncer=true\b/.test(text)) {
          continue;
        }

        const key = /^\s*(?:export\s+)?(\w+)\s*=/.exec(text)?.[1];
        const target = `${file.path}${key ? `:${key}` : `:${line}`}`;

        findings.push({
          message: `${target} connects Prisma through the transaction pooler on port 6543 without \`pgbouncer=true\`, so Prisma's prepared statements fail on the next transaction. Add \`?pgbouncer=true\` to the URL, and use the session pooler or direct URL as \`directUrl\` for migrations.`,
          target,
          location: { file: file.path, line },
        });
      }

      return findings;
    },
  },
  {
    code: "BS227",
    severity: "info",
    title: "Offset pagination or exact counts",
    description:
      '`pagination: "offset"` on a resource or list reads and discards every row before the page, so late pages get slower as the table grows, and rows written between requests shift the pages. `count: "exact"` counts every matching row on each request. Use `pagination: "cursor"`, and `count: "planned"` or `"estimated"` on large tables. Doctor looks in `tooling.doctor.sources`.',
    check: (context) =>
      context.sources.flatMap((file): FindingInput[] =>
        lines(file).flatMap(({ line, text }): FindingInput[] => {
          if (/^\s*(?:\/\/|\*)/.test(text)) {
            return [];
          }

          const found: FindingInput[] = [];

          if (OFFSET_PAGINATION.test(text)) {
            found.push({
              message: `${file.path}:${line} uses \`pagination: "offset"\`, so each page reads and skips every earlier row. Use \`pagination: "cursor"\` unless the UI needs page numbers, and keep \`[api] max_rows\` set so no request reads the whole table.`,
              target: `${file.path}:${line}:pagination`,
              location: { file: file.path, line },
            });
          }

          if (EXACT_COUNT.test(text)) {
            found.push({
              message: `${file.path}:${line} uses \`count: "exact"\`, which counts every matching row on each request. Use \`count: "planned"\` or \`"estimated"\` when the table can grow large.`,
              target: `${file.path}:${line}:count`,
              location: { file: file.path, line },
            });
          }

          return found;
        }),
      ),
  },
  {
    code: "BS228",
    severity: "warning",
    title: "App table column drifted from appTables",
    description:
      "A column of an app table has a different type or nullability in the database than `appTables` gives it, usually after an edit by hand or a migration that wasn't regenerated. `gen` types the column from `appTables`, so the app reads values the database doesn't hold. A table or column the database doesn't have yet is left out: that is a migration not applied.",
    check: (context) => {
      const columns = new Map(
        context.snapshot.generator.columns
          .filter((column) => column.schema === "public")
          .map((column) => [`${column.table}.${column.name}`, column]),
      );

      const enriched = enrichedAppTables(context);

      return Object.entries(context.config.appTables).flatMap(
        ([table, config]) =>
          Object.entries(config.columns ?? {}).flatMap(
            ([name, column]): FindingInput[] => {
              const found = columns.get(`${table}.${name}`);

              if (found === undefined) {
                return [];
              }

              const encrypted = column.encrypted === true;

              // An encrypted column holds ciphertext, so the database type is text.
              const format = encrypted
                ? "text"
                : APP_COLUMN_FORMAT[column.type];

              // An enriched table's existing rows have no value for a required
              // column without a default, so the entry adds it nullable.
              const nullable =
                column.nullable !== false ||
                (enriched.has(table) &&
                  found.is_nullable &&
                  column.default === undefined &&
                  column.identity !== true);

              const drift = [
                ...(found.format === format
                  ? []
                  : [
                      `is ${found.format} in the database and ${encrypted ? "encrypted text" : column.type} in appTables`,
                    ]),
                ...(found.is_nullable === nullable
                  ? []
                  : [
                      nullable
                        ? "is not null in the database and nullable in appTables"
                        : "is nullable in the database and required in appTables",
                    ]),
              ];

              return drift.length === 0
                ? []
                : [
                    {
                      message: `public.${table}.${name} ${drift.join(", and ")}. Change appTables to match the database, or regenerate the migration with \`better-supabase upgrade\` and apply it. Follow the expand-and-contract steps from \`better-supabase add\` when rows depend on the old shape.`,
                      target: `public.${table}.${name}`,
                      object: { kind: "table", schema: "public", name: table },
                    },
                  ];
            },
          ),
      );
    },
  },
];
