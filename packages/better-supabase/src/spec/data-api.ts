import type {
  FunctionMeta,
  FunctionSignature,
  SchemaMeta,
  TableMeta,
} from "../schema/types.ts";
import type { BuildContext, DraftOperation } from "./build-resource.ts";
import type {
  DataApiOperation,
  HttpMethod,
  JsonSchema,
  ModelParameter,
  ModelResponseOrRef,
  ModelServer,
  OperationSource,
  SecurityRequirement,
} from "./model.ts";
import type { ResolvedSecurity } from "./presets.ts";

import { isPlainObject } from "../core/clone.ts";
import { jsonContent, jsonResponse } from "./build-resource.ts";
import { resolveSecurity } from "./presets.ts";
import { pascal, schemaRef, tableSchemas } from "./schemas.ts";

type Json = Record<string, unknown>;

/** Which tables and functions the Data API (PostgREST) section documents. */
export interface DataApiOptions {
  /** Tables and views by app key, or `true` for all of them. */
  readonly tables?: true | readonly string[];
  /** Functions by key, or `true` for all of them, as `POST /rest/v1/rpc/<name>`. */
  readonly functions?: true | readonly string[];
  /**
   * The operations per table, by app key. Defaults to all four for a table and
   * to the ones its columns allow for a view.
   */
  readonly operations?: Readonly<Record<string, readonly DataApiOperation[]>>;
  /** The tag of every Data API operation. Defaults to `Data API`. */
  readonly tag?: string;
}

const REST = "/rest/v1";
const DEFAULT_TAG = "Data API";
const ERROR = "DataApiError";

/** The error body PostgREST answers with. */
const ERROR_SCHEMA: Json = {
  type: "object",
  required: ["message"],
  properties: {
    code: { type: "string" },
    message: { type: "string" },
    details: { type: ["string", "null"] },
    hint: { type: ["string", "null"] },
  },
};

/**
 * Query parameters PostgREST reserves, so a column with the name gets no
 * filter.
 */
const RESERVED = new Set([
  "select",
  "order",
  "limit",
  "offset",
  "columns",
  "on_conflict",
  "or",
  "and",
  "not",
]);

const INTEGER = new Set(["int2", "int4", "int8"]);
const NUMBER = new Set(["float4", "float8", "numeric", "oid", "money"]);

/** The scheme names the `apiKey` and `bearer` presets register. */
const DATA_API_SECURITY: readonly SecurityRequirement[] = [
  { supabaseApiKey: [], supabaseJwt: [] },
  { supabaseApiKey: [] },
];

/** JSON Schema for a Postgres type as PostgREST writes it. */
function typeSchema(meta: SchemaMeta, type: string): JsonSchema {
  if (type.startsWith("_")) {
    return { type: "array", items: typeSchema(meta, type.slice(1)) };
  }

  const values = meta.enums[type];

  if (values) {
    return { type: "string", enum: [...values] };
  }

  if (INTEGER.has(type)) {
    return { type: "integer" };
  }

  if (NUMBER.has(type)) {
    return { type: "number" };
  }

  switch (type) {
    case "bool": {
      return { type: "boolean" };
    }

    case "uuid": {
      return { type: "string", format: "uuid" };
    }

    case "timestamptz": {
      return { type: "string", format: "date-time" };
    }

    case "date": {
      return { type: "string", format: "date" };
    }

    case "json":
    case "jsonb":
    case "record":
    case "void": {
      return {};
    }

    default: {
      return { type: "string" };
    }
  }
}

/**
 * A table schema with database column names, as the Data API reads and writes
 * them.
 */
function databaseCased(schema: JsonSchema, table: TableMeta): Json {
  const dbName = (name: string): string => table.columns[name]?.db ?? name;
  const properties = schema["properties"];
  const required = schema["required"];

  return {
    ...schema,
    ...(isPlainObject(properties)
      ? {
          properties: Object.fromEntries(
            Object.entries(properties).map(([name, value]) => [
              dbName(name),
              value,
            ]),
          ),
        }
      : {}),
    ...(Array.isArray(required)
      ? {
          required: required.map((name: unknown) =>
            typeof name === "string" ? dbName(name) : name,
          ),
        }
      : {}),
  };
}

const qualified = (schema: string, name: string): string =>
  schema === "public" ? name : `${schema}.${name}`;

const STRING: JsonSchema = { type: "string" };

const header = (
  name: string,
  description: string,
  schema?: JsonSchema,
  required = false,
): ModelParameter => ({
  name,
  in: "header",
  required,
  description,
  schema: schema ?? STRING,
});

const query = (
  name: string,
  description: string,
  schema?: JsonSchema,
): ModelParameter => ({
  name,
  in: "query",
  required: false,
  description,
  schema: schema ?? STRING,
});

/**
 * The `Accept-Profile` or `Content-Profile` header a table outside `public`
 * needs.
 */
function profile(schema: string, write: boolean): ModelParameter[] {
  return schema === "public"
    ? []
    : [
        header(
          write ? "Content-Profile" : "Accept-Profile",
          `The schema of the table, \`${schema}\`.`,
          { type: "string", enum: [schema] },
          true,
        ),
      ];
}

const PREFER_WRITE = header(
  "Prefer",
  "`return=representation` answers with the written rows; `return=minimal` (the default) answers without a body.",
);

/**
 * Documents the Data API: table operations under `/rest/v1/<table>` and RPCs
 * under `/rest/v1/rpc/<name>`.
 */
export function buildDataApi<Ref>(
  ctx: BuildContext<Ref>,
  dataApi: DataApiOptions,
): void {
  const { meta, options, operations, report, addTag, addComponent, responses } =
    ctx;

  const tag = dataApi.tag ?? DEFAULT_TAG;
  const origin = options.supabaseUrl?.replace(/\/$/, "");

  if (!origin) {
    report({
      code: "data-api-server-missing",
      severity: "warning",
      message:
        "dataApi needs supabaseUrl: without it the /rest/v1 paths resolve against the document's servers",
    });
  }

  const servers: readonly ModelServer[] | undefined = origin
    ? [{ url: origin, description: "The Supabase project." }]
    : undefined;

  const defs = tableSchemas(meta, options.json ?? {});
  const tableKeys = new Set<string>();

  const unknownTable = (key: string, where: string): void => {
    report({
      code: "data-api-table-unknown",
      severity: "error",
      message: `${where}: no table or view "${key}"`,
    });
  };

  if (dataApi.tables === true) {
    for (const key of Object.keys(meta.tables).toSorted()) {
      tableKeys.add(key);
    }
  } else {
    for (const key of dataApi.tables ?? []) {
      if (meta.tables[key]) {
        tableKeys.add(key);
      } else {
        unknownTable(key, "dataApi.tables");
      }
    }
  }

  for (const key of Object.keys(dataApi.operations ?? {})) {
    if (!meta.tables[key]) {
      unknownTable(key, "dataApi.operations");
    } else if (!tableKeys.has(key)) {
      tableKeys.add(key);
    }
  }

  const functionKeys: string[] = [];

  if (dataApi.functions === true) {
    functionKeys.push(...Object.keys(meta.functions).toSorted());
  } else {
    for (const key of dataApi.functions ?? []) {
      if (meta.functions[key]) {
        functionKeys.push(key);
      } else {
        report({
          code: "data-api-function-unknown",
          severity: "error",
          message: `dataApi.functions: no function "${key}"`,
        });
      }
    }
  }

  if (tableKeys.size === 0 && functionKeys.length === 0) {
    return;
  }

  addTag(
    tag,
    "The Supabase Data API (PostgREST). Every request runs under row-level security.",
  );
  addComponent(ERROR, structuredClone(ERROR_SCHEMA));
  responses[ERROR] ??= {
    description: "PostgREST rejected the request.",
    content: jsonContent(schemaRef(ERROR)),
  };

  const errors: Record<string, ModelResponseOrRef> = { "4XX": { ref: ERROR } };

  /**
   * The database-cased component of a table variant, or `undefined` when the
   * table has none.
   */
  const component = (
    key: string,
    variant: "Row" | "Insert" | "Update",
  ): JsonSchema | undefined => {
    const table = meta.tables[key];
    const schema = defs[`${key}${variant}`];

    if (!table || !schema) {
      return undefined;
    }

    const name = `DataApi${pascal(table.schema === "public" ? "" : `${table.schema}_`)}${pascal(table.name)}${variant}`;
    addComponent(name, databaseCased(structuredClone(schema), table));

    return schemaRef(name);
  };

  const push = (
    draft: Omit<DraftOperation, "id" | "tags" | "extensions" | "source"> & {
      readonly defaultId: string;
      readonly source: OperationSource;
    },
  ): void => {
    const { defaultId, ...rest } = draft;

    operations.push({
      ...rest,
      id:
        options.operationId?.({
          source: draft.source,
          method: draft.method,
          path: draft.path,
          defaultId,
        }) ?? defaultId,
      tags: [tag],
      ...(servers ? { servers } : {}),
      security: DATA_API_SECURITY,
      extensions: {},
    });
  };

  for (const key of tableKeys) {
    const table = meta.tables[key];

    if (table) {
      buildTable(key, table);
    }
  }

  for (const key of functionKeys) {
    const fn = meta.functions[key];

    if (fn) {
      buildFunction(key, fn);
    }
  }

  function buildTable(key: string, table: TableMeta): void {
    const row = component(key, "Row") ?? {};
    const insert = component(key, "Insert");
    const update = component(key, "Update");
    const rows = { type: "array", items: row };
    const path = `${REST}/${table.name}`;

    const name = pascal(
      table.schema === "public" ? table.name : `${table.schema}_${table.name}`,
    );

    const label = qualified(table.schema, table.name);

    const filters = Object.values(table.columns)
      .filter((column) => !RESERVED.has(column.db))
      .map((column) =>
        query(
          column.db,
          `Filters on \`${column.db}\` with an operator and a value: \`eq.<value>\`, \`in.(a,b)\`, \`is.null\`.`,
        ),
      );

    const viewOperations: DataApiOperation[] = ["select"];

    if (insert) {
      viewOperations.push("insert");
    }

    if (update) {
      viewOperations.push("update", "delete");
    }

    const allowed: readonly DataApiOperation[] =
      dataApi.operations?.[key] ??
      (table.kind === "view"
        ? viewOperations
        : ["select", "insert", "update", "delete"]);

    const source = (operation: DataApiOperation): OperationSource => ({
      kind: "data-api",
      table: key,
      operation,
    });

    const written = (status: string, description: string) => ({
      [status]: jsonResponse(
        rows,
        `${description} The body holds the rows with \`Prefer: return=representation\`.`,
      ),
    });

    for (const operation of allowed) {
      switch (operation) {
        case "select": {
          push({
            defaultId: `dataApiSelect${name}`,
            method: "get",
            path,
            summary: `Read rows of ${label}`,
            parameters: [
              query(
                "select",
                "The columns to return, comma separated, and embedded relations as `relation(columns)`. Defaults to `*`.",
              ),
              query("order", "Sort order, such as `created_at.desc,id`."),
              query("limit", "The most rows to return.", {
                type: "integer",
                minimum: 0,
              }),
              query("offset", "The rows to skip.", {
                type: "integer",
                minimum: 0,
              }),
              ...filters,
              header("Range", "A row range, such as `0-24`."),
              header(
                "Prefer",
                "`count=exact`, `count=planned` or `count=estimated` adds the total to `Content-Range`.",
              ),
              ...profile(table.schema, false),
            ],
            responses: {
              "200": {
                ...jsonResponse(rows, "The rows."),
                headers: {
                  "Content-Range": {
                    description:
                      "The returned range and the total, such as `0-24/100`.",
                    schema: { type: "string" },
                  },
                },
              },
              "206": jsonResponse(
                rows,
                "Part of the rows, for a `Range` request.",
              ),
              ...errors,
            },
            source: source("select"),
          });
          break;
        }

        case "insert": {
          push({
            defaultId: `dataApiInsert${name}`,
            method: "post",
            path,
            summary: `Insert rows into ${label}`,
            parameters: [
              query(
                "columns",
                "The columns to read from the body, comma separated.",
              ),
              query(
                "on_conflict",
                "The unique columns an upsert matches on, comma separated.",
              ),
              PREFER_WRITE,
              ...profile(table.schema, true),
            ],
            requestBody: {
              required: true,
              content: jsonContent(
                insert
                  ? { oneOf: [insert, { type: "array", items: insert }] }
                  : {},
              ),
            },
            responses: { ...written("201", "Created."), ...errors },
            source: source("insert"),
          });
          break;
        }

        case "update": {
          push({
            defaultId: `dataApiUpdate${name}`,
            method: "patch",
            path,
            summary: `Update rows of ${label}`,
            description: "Updates every row the filters match.",
            parameters: [
              ...filters,
              PREFER_WRITE,
              ...profile(table.schema, true),
            ],
            requestBody: { required: true, content: jsonContent(update ?? {}) },
            responses: {
              ...written("200", "Updated."),
              "204": { description: "Updated, without a body." },
              ...errors,
            },
            source: source("update"),
          });
          break;
        }

        case "delete": {
          push({
            defaultId: `dataApiDelete${name}`,
            method: "delete",
            path,
            summary: `Delete rows of ${label}`,
            description: "Deletes every row the filters match.",
            parameters: [
              ...filters,
              PREFER_WRITE,
              ...profile(table.schema, true),
            ],
            responses: {
              ...written("200", "Deleted."),
              "204": { description: "Deleted, without a body." },
              ...errors,
            },
            source: source("delete"),
          });
          break;
        }

        default: {
          const exhaustive: never = operation;

          throw new TypeError(
            `Unknown Data API operation "${String(exhaustive)}"`,
          );
        }
      }
    }
  }

  function argumentsSchema(signature: FunctionSignature): JsonSchema {
    const required = signature.args
      .filter((arg) => arg.optional !== true)
      .map((arg) => arg.name);

    return {
      type: "object",
      properties: Object.fromEntries(
        signature.args.map((arg) => [arg.name, typeSchema(meta, arg.type)]),
      ),
      ...(required.length > 0 ? { required } : {}),
      additionalProperties: false,
    };
  }

  function resultSchema(fn: FunctionMeta): JsonSchema {
    const { result } = fn;
    let one: JsonSchema;

    if (result && "table" in result) {
      one = component(result.table, "Row") ?? {};
    } else if (result) {
      one = {
        type: "object",
        properties: Object.fromEntries(
          result.columns.map((column) => [column.db, {}]),
        ),
        required: result.columns.map((column) => column.db),
      };
    } else {
      const rowTable = Object.entries(meta.tables).find(
        ([, table]) => table.name === fn.returns && table.schema === fn.schema,
      );

      one = rowTable
        ? (component(rowTable[0], "Row") ?? {})
        : typeSchema(meta, fn.returns);
    }

    return fn.returnsSet ? { type: "array", items: one } : one;
  }

  function buildFunction(key: string, fn: FunctionMeta): void {
    const signatures = fn.overloads ?? [fn];
    const bodies = signatures.map(argumentsSchema);
    const [only] = bodies;
    const body = bodies.length === 1 && only ? only : { oneOf: bodies };
    const takesArgs = signatures.some((signature) => signature.args.length > 0);
    const method: HttpMethod = "post";

    push({
      defaultId: `dataApiRpc${pascal(fn.schema === "public" ? fn.name : `${fn.schema}_${fn.name}`)}`,
      method,
      path: `${REST}/rpc/${fn.name}`,
      summary: `Call ${qualified(fn.schema, fn.name)}`,
      description: `A ${fn.volatility} function.${fn.volatility === "volatile" ? "" : " A GET with the arguments as query parameters calls it too."}`,
      parameters: profile(fn.schema, true),
      requestBody: { required: takesArgs, content: jsonContent(body) },
      responses: {
        ...(fn.returns === "void" && !fn.returnsSet
          ? { "204": { description: "Done." } }
          : { "200": jsonResponse(resultSchema(fn), "The result.") }),
        ...errors,
      },
      source: { kind: "data-api", function: key, operation: "rpc" },
    });
  }
}

/** Adds the `apiKey` and `bearer` schemes the Data API operations require. */
export function withDataApiSchemes(
  security: ResolvedSecurity,
  operations: readonly DraftOperation[],
  supabaseUrl: string | undefined,
): ResolvedSecurity {
  if (!operations.some((operation) => operation.source.kind === "data-api")) {
    return security;
  }

  const { schemes } = resolveSecurity(["apiKey", "bearer"], supabaseUrl);

  return {
    schemes: { ...schemes, ...security.schemes },
    requirements: security.requirements,
  };
}
