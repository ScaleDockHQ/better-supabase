import type { OpenApiParameter } from "../list/index.ts";
import type { SchemaMeta, TableMeta } from "../schema/types.ts";

import { PROBLEM_CONTENT_TYPE, PROBLEM_TYPE_BASE } from "../core/problem.ts";
import { SPEC_PINS } from "../core/spec-pins.ts";
import { buildJsonSchema } from "../generators/json-schema.ts";

type Json = Record<string, unknown>;

export type ResourceOperation = "list" | "get" | "create" | "update" | "delete";

export interface ResourceOptions {
  /** Defaults to every operation for tables, `list` and `get` for views. */
  readonly operations?: readonly ResourceOperation[];
  /** Parameters for `list`, from `defineListQuery`. */
  readonly list?: {
    readonly openapi: readonly OpenApiParameter[];
    readonly pagination?: "offset" | "cursor";
  };
  /** Paging of the default list, as in `defineResource`. Defaults to `offset`. */
  readonly pagination?: "offset" | "cursor";
  /** Largest page of the default list. Defaults to 200. */
  readonly maxPageSize?: number;
  /** Path of the collection. Defaults to `/<table>`. */
  readonly path?: string;
  readonly tag?: string;
  readonly description?: string;
}

export interface OpenApiOptions {
  readonly info: {
    readonly title: string;
    readonly version: string;
    readonly description?: string;
  };
  readonly servers?: readonly {
    readonly url: string;
    readonly description?: string;
  }[];
  /** Prefix for every path, e.g. `/api`. */
  readonly basePath?: string;
  /** Tables to publish, by app key. */
  readonly resources: Readonly<Record<string, ResourceOptions | true>>;
  /**
   * Security schemes. `bearer` is a Supabase access token; `oauth2` uses the
   * Supabase OAuth server and needs `supabaseUrl`. Defaults to `['bearer']`.
   */
  readonly security?: readonly ("bearer" | "oauth2")[];
  readonly supabaseUrl?: string;
  /** Tables with a JSON column typed in `better-supabase.config.ts`. */
  readonly json?: Readonly<Record<string, unknown>>;
}

export interface OpenApiDocument {
  readonly openapi: string;
  readonly info: OpenApiOptions["info"];
  readonly jsonSchemaDialect: string;
  readonly servers?: OpenApiOptions["servers"];
  readonly tags: readonly {
    readonly name: string;
    readonly description?: string;
  }[];
  readonly paths: Readonly<Record<string, Json>>;
  readonly components: {
    readonly schemas: Readonly<Record<string, Json>>;
    readonly responses: Readonly<Record<string, Json>>;
    readonly securitySchemes: Readonly<Record<string, Json>>;
  };
  readonly security: readonly Readonly<Record<string, readonly string[]>>[];
}

/** JSON Schema for RFC 9457 Problem Details as better-supabase sends them. */
export const PROBLEM_SCHEMA: Json = {
  type: "object",
  required: ["type", "title", "status"],
  properties: {
    type: {
      type: "string",
      format: "uri-reference",
      examples: [`${PROBLEM_TYPE_BASE}not-found`],
    },
    title: { type: "string" },
    status: { type: "integer", minimum: 100, maximum: 599 },
    detail: { type: "string" },
    instance: { type: "string" },
    kind: { type: "string" },
    code: { type: "string" },
    hint: { type: "string" },
    constraint: { type: "string" },
    column: { type: "string" },
    columns: { type: "array", items: { type: "string" } },
    issues: {
      type: "array",
      items: {
        type: "object",
        required: ["message"],
        properties: {
          message: { type: "string" },
          path: { type: "array", items: { type: ["string", "integer"] } },
        },
      },
    },
  },
};

const ERRORS: readonly [string, number, string][] = [
  ["BadRequest", 400, "The request is invalid."],
  ["Unauthorized", 401, "Missing or invalid credentials."],
  ["Forbidden", 403, "Row-level security or a plugin denied the request."],
  ["NotFound", 404, "No row matches."],
  ["Conflict", 409, "A unique or foreign key constraint failed."],
  ["Unprocessable", 422, "Validation or a check constraint failed."],
];

const pascal = (value: string): string =>
  value.replaceAll(/(^|[_-])(\w)/g, (_, _sep: string, char: string) =>
    char.toUpperCase(),
  );
const ref = (name: string): Json => ({ $ref: `#/components/schemas/${name}` });
const response = (name: string): Json => ({
  $ref: `#/components/responses/${name}`,
});

function errorResponses(codes: readonly number[]): Json {
  const out: Json = {};
  for (const [name, status] of ERRORS)
    if (codes.includes(status)) out[String(status)] = response(name);
  return out;
}

function jsonBody(schema: Json, description: string): Json {
  return { description, content: { "application/json": { schema } } };
}

function pageParameters(
  cursor: boolean,
  maxPageSize: number,
): OpenApiParameter[] {
  return [
    cursor
      ? {
          name: "after",
          in: "query",
          required: false,
          description:
            "`nextCursor` of the previous page. Leave it out for the first page.",
          schema: { type: "string" },
        }
      : {
          name: "page",
          in: "query",
          required: false,
          description: "1-based page number.",
          schema: { type: "integer", minimum: 1, default: 1 },
        },
    {
      name: "size",
      in: "query",
      required: false,
      description: "Page size.",
      schema: {
        type: "integer",
        minimum: 1,
        maximum: maxPageSize,
        default: 50,
      },
    },
  ];
}

function pageSchema(row: Json, cursor: boolean): Json {
  const items = { type: "array", items: row };
  return cursor
    ? {
        type: "object",
        required: ["items", "nextCursor", "hasMore"],
        properties: {
          items,
          nextCursor: { type: ["string", "null"] },
          hasMore: { type: "boolean" },
        },
      }
    : {
        type: "object",
        required: ["items", "page"],
        properties: {
          items,
          page: {
            type: "object",
            required: ["number", "size", "total", "pages", "hasMore"],
            properties: {
              number: { type: "integer" },
              size: { type: "integer" },
              total: { type: ["integer", "null"] },
              pages: { type: ["integer", "null"] },
              hasMore: { type: "boolean" },
            },
          },
        },
      };
}

/**
 * An OpenAPI 3.1 document for REST resources over your tables, with schemas
 * from the generated metadata, list-query parameters, Supabase security
 * schemes and Problem Details errors.
 *
 * ```ts
 * const doc = createOpenApi(sb, {
 *   info: { title: 'CRM API', version: '1.0.0' },
 *   resources: { customers: { list: customerList }, notes: { operations: ['list', 'get'] } },
 * });
 * ```
 */
export function createOpenApi(
  sb: { readonly meta: SchemaMeta },
  options: OpenApiOptions,
): OpenApiDocument {
  // SAFETY: buildJsonSchema always returns a $defs object of JSON schemas.
  const defs = buildJsonSchema({
    meta: sb.meta,
    config: { json: options.json ?? {} },
  })["$defs"] as Record<string, Json>;
  const schemas: Record<string, Json> = { Problem: PROBLEM_SCHEMA };
  const paths: Record<string, Json> = {};
  const tags: { name: string; description?: string }[] = [];
  const base = (options.basePath ?? "").replace(/\/$/, "");
  const security = options.security ?? ["bearer"];

  for (const [key, raw] of Object.entries(options.resources)) {
    const table: TableMeta | undefined = sb.meta.tables[key];
    if (!table) throw new TypeError(`createOpenApi: unknown table "${key}"`);
    const resource: ResourceOptions = raw === true ? {} : raw;
    const operations =
      resource.operations ??
      (table.kind === "view"
        ? ["list", "get"]
        : ["list", "get", "create", "update", "delete"]);
    const name = pascal(key);
    const tag = resource.tag ?? key;
    if (!tags.some((entry) => entry.name === tag))
      tags.push({
        name: tag,
        ...(resource.description ? { description: resource.description } : {}),
      });
    const extensions = {
      "x-better-supabase-table": `${table.schema}.${table.name}`,
    };

    for (const variant of ["Row", "Insert", "Update"] as const) {
      const schema = defs[`${key}${variant}`];
      if (schema) schemas[`${name}${variant}`] = schema;
    }
    const cursor =
      (resource.list ? resource.list.pagination : resource.pagination) ===
      "cursor";
    schemas[`${name}Page`] = pageSchema(ref(`${name}Row`), cursor);

    const collection = `${base}${resource.path ?? `/${key}`}`;
    const keyColumn =
      table.primaryKey.length === 1 ? table.primaryKey[0]! : undefined;
    // SAFETY: every Row definition from buildJsonSchema is an object schema with properties.
    const idSchema = keyColumn
      ? ((
          defs[`${key}Row`]?.["properties"] as Record<string, Json> | undefined
        )?.[keyColumn] ?? { type: "string" })
      : undefined;
    const item = keyColumn ? `${collection}/{${keyColumn}}` : undefined;
    const idParameter = keyColumn
      ? [{ name: keyColumn, in: "path", required: true, schema: idSchema }]
      : [];
    const op = (
      operation: ResourceOperation,
      summary: string,
      body: Json,
    ): Json => ({
      operationId: `${operation}${name}`,
      tags: [tag],
      summary,
      ...extensions,
      "x-better-supabase-operation": operation,
      ...body,
    });

    for (const operation of operations) {
      switch (operation) {
        case "list":
          (paths[collection] ??= {})["get"] = op("list", `List ${key}`, {
            parameters:
              resource.list?.openapi ??
              pageParameters(cursor, resource.maxPageSize ?? 200),
            responses: {
              "200": jsonBody(ref(`${name}Page`), `A page of ${key}.`),
              ...errorResponses([400, 401, 403]),
            },
          });
          break;
        case "create":
          (paths[collection] ??= {})["post"] = op(
            "create",
            `Create a ${key} row`,
            {
              requestBody: {
                required: true,
                content: {
                  "application/json": { schema: ref(`${name}Insert`) },
                },
              },
              responses: {
                "201": jsonBody(ref(`${name}Row`), "Created."),
                ...errorResponses([400, 401, 403, 409, 422]),
              },
            },
          );
          break;
        case "get":
        case "update":
        case "delete": {
          if (!item) break;
          const path = (paths[item] ??= { parameters: idParameter });
          if (operation === "get") {
            path["get"] = op("get", `Get a ${key} row`, {
              responses: {
                "200": jsonBody(ref(`${name}Row`), "The row."),
                ...errorResponses([401, 403, 404]),
              },
            });
          } else if (operation === "update") {
            path["patch"] = op("update", `Update a ${key} row`, {
              requestBody: {
                required: true,
                content: {
                  "application/json": { schema: ref(`${name}Update`) },
                },
              },
              responses: {
                "200": jsonBody(ref(`${name}Row`), "Updated."),
                ...errorResponses([400, 401, 403, 404, 409, 422]),
              },
            });
          } else {
            path["delete"] = op("delete", `Delete a ${key} row`, {
              responses: {
                "204": { description: "Deleted." },
                ...errorResponses([401, 403, 404, 409]),
              },
            });
          }
          break;
        }
        default: {
          const unknown: never = operation;
          throw new TypeError(
            `createOpenApi: unknown operation "${String(unknown)}"`,
          );
        }
      }
    }
  }

  const securitySchemes: Record<string, Json> = {};
  if (security.includes("bearer")) {
    securitySchemes["supabaseJwt"] = {
      type: "http",
      scheme: "bearer",
      bearerFormat: "JWT",
      description:
        "A Supabase access token. Requests run as that user under row-level security.",
    };
  }
  if (security.includes("oauth2")) {
    if (!options.supabaseUrl)
      throw new TypeError("createOpenApi: oauth2 security needs supabaseUrl");
    const auth = `${options.supabaseUrl.replace(/\/$/, "")}/auth/v1`;
    securitySchemes["supabaseOAuth"] = {
      type: "oauth2",
      description: "The Supabase OAuth 2.1 server.",
      flows: {
        authorizationCode: {
          authorizationUrl: `${auth}/oauth/authorize`,
          tokenUrl: `${auth}/oauth/token`,
          scopes: {},
        },
      },
    };
  }

  const responses: Record<string, Json> = {};
  for (const [name, , description] of ERRORS) {
    responses[name] = {
      description,
      content: { [PROBLEM_CONTENT_TYPE]: { schema: ref("Problem") } },
    };
  }

  return {
    openapi: SPEC_PINS.openapi,
    info: options.info,
    jsonSchemaDialect: "https://json-schema.org/draft/2020-12/schema",
    ...(options.servers ? { servers: options.servers } : {}),
    tags,
    paths,
    components: { schemas, responses, securitySchemes },
    security: Object.keys(securitySchemes).map((name) => ({ [name]: [] })),
  };
}
