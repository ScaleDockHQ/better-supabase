import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { BetterSupabase } from "../core/define.ts";
import type { RepositoryOf } from "../core/repository-types.ts";
import type { SelectArg } from "../ir/args.ts";
import type { ResourceOperation } from "../openapi/index.ts";
import type {
  AnyFunctions,
  AnyModels,
  Insert,
  TableKey,
  TableMeta,
  Update,
} from "../schema/types.ts";

import { dbError, type ValidationIssue } from "../core/errors.ts";
import { err, ok, type Result } from "../core/result.ts";
import { validate } from "../core/standard.ts";
import { respond, type RespondOptions } from "./respond.ts";

/** What a resource needs from `defineListQuery`. */
export interface ResourceList {
  readonly table: string;
  readonly openapi: readonly unknown[];
  readonly jsonSchema: Readonly<Record<string, unknown>>;
  parse(
    input: never,
  ):
    | { readonly ok: true; readonly value: unknown }
    | { readonly ok: false; readonly issues: readonly ValidationIssue[] };
  run(db: never, query: never, extra?: never): PromiseLike<unknown>;
}

export interface ResourceRouteOptions<
  M extends AnyModels,
  T extends TableKey<M>,
> {
  /** Defaults to every operation for tables, `list` and `get` for views. */
  readonly operations?: readonly ResourceOperation[];
  /** Filters, search and sorts for `list`, from `defineListQuery`. */
  readonly list?: ResourceList;
  /** Columns returned by every operation. */
  readonly select?: SelectArg<M, T>;
  /** Validates request bodies before they reach the repository. */
  readonly input?: {
    readonly create?: StandardSchemaV1<unknown, Insert<M, T>>;
    readonly update?: StandardSchemaV1<unknown, Update<M, T>>;
  };
  /** Largest page for the default `page`/`size` list. Defaults to 200. */
  readonly maxPageSize?: number;
}

export interface ResourceInput {
  /** Primary key value; strings are converted for integer keys. */
  readonly id?: unknown;
  /** Body of `create` and `update`. */
  readonly data?: unknown;
  /** `list` parameters: URL params or typed values. */
  readonly query?: URLSearchParams | Readonly<Record<string, unknown>>;
}

export interface ResourceHandler {
  readonly table: string;
  readonly meta: TableMeta;
  readonly operations: readonly ResourceOperation[];
  /** Name of the key parameter, or `undefined` for tables without a single-column key. */
  readonly keyParam: string | undefined;
  readonly list: ResourceList | undefined;
  readonly maxPageSize: number;
  /** Runs one operation as whoever `db` is bound to. Resolves to a `Result`. */
  execute(
    db: object,
    operation: ResourceOperation,
    input?: ResourceInput,
  ): Promise<Result<unknown>>;
  /** Serves a collection request (`id` undefined) or an item request. */
  handle(
    request: Request,
    db: object,
    id: string | undefined,
    options?: RespondOptions,
  ): Promise<Response>;
}

type AnyRepository = RepositoryOf<AnyModels, string, unknown>;

const INTEGER = new Set(["int2", "int4", "int8"]);

function keyValue(table: TableMeta, raw: unknown): Result<unknown> {
  const invalid = err(
    dbError(
      "invalid_request",
      `${JSON.stringify(raw)} is not a valid ${table.key} key`,
    ),
  );
  const column = table.columns[table.primaryKey[0]!];
  if (column && INTEGER.has(column.type)) {
    const value = typeof raw === "string" ? Number(raw) : raw;
    return typeof value === "number" && Number.isSafeInteger(value)
      ? ok(value)
      : invalid;
  }
  return typeof raw === "string" && raw !== "" ? ok(raw) : invalid;
}

async function readBody(request: Request): Promise<Result<unknown>> {
  try {
    const body: unknown = await request.json();
    if (typeof body === "object" && body !== null && !Array.isArray(body)) {
      return ok(body);
    }
  } catch {
    // Reported below.
  }
  return err(
    dbError("invalid_request", "The request body must be a JSON object"),
  );
}

function pageArgs(
  query: ResourceInput["query"],
  max: number,
): Result<{ page: number; size: number }> {
  const read = (name: string, fallback: number): number | undefined => {
    const raw: unknown =
      query instanceof URLSearchParams ? query.get(name) : query?.[name];
    if (raw === null || raw === undefined || raw === "") return fallback;
    const value = Number(raw);
    return Number.isSafeInteger(value) && value >= 1 ? value : undefined;
  };
  const page = read("page", 1);
  const size = read("size", 50);
  if (page === undefined || size === undefined || size > max) {
    return err(
      dbError("validation", "Invalid page parameters", {
        issues: [
          ...(page === undefined
            ? [{ message: "Must be a positive integer", path: ["page"] }]
            : []),
          ...(size === undefined || size > max
            ? [{ message: `Must be between 1 and ${max}`, path: ["size"] }]
            : []),
        ],
      }),
    );
  }
  return ok({ page, size });
}

function asObject(value: unknown): Result<unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? ok(value)
    : err(dbError("invalid_request", "Expected an object of column values"));
}

async function settled(value: unknown): Promise<Result<unknown>> {
  return (await value) as Result<unknown>;
}

function notAllowed(allowed: readonly string[]): Response {
  return new Response(null, {
    status: 405,
    headers: { allow: allowed.join(", ") },
  });
}

/**
 * Operations over one table, matching the paths and responses of
 * `createOpenApi`: `GET/POST /<table>` and `GET/PATCH/DELETE /<table>/{id}`.
 * Shared by the HTTP adapters and the MCP table tools.
 */
export function defineResource<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  T extends TableKey<M>,
>(
  sb: BetterSupabase<M, D, F, E>,
  table: T,
  options: ResourceRouteOptions<M, T> = {},
): ResourceHandler {
  const meta = sb.meta.tables[table];
  if (!meta) throw new TypeError(`Unknown table "${table}"`);
  if (options.list && options.list.table !== table) {
    throw new TypeError(
      `The list query is for "${options.list.table}", not "${table}"`,
    );
  }
  const operations: readonly ResourceOperation[] =
    options.operations ??
    (meta.kind === "view"
      ? ["list", "get"]
      : ["list", "get", "create", "update", "delete"]);
  const keyParam =
    meta.primaryKey.length === 1 ? meta.primaryKey[0] : undefined;
  const has = (operation: ResourceOperation): boolean =>
    operations.includes(operation);
  const extra = options.select === undefined ? {} : { select: options.select };
  const maxPageSize = options.maxPageSize ?? 200;
  const list = options.list;

  const execute = async (
    db: object,
    operation: ResourceOperation,
    input: ResourceInput = {},
  ): Promise<Result<unknown>> => {
    const repository = (db as Record<string, AnyRepository>)[table];
    if (!repository) throw new TypeError(`The db has no "${table}" repository`);
    if (!has(operation)) {
      return err(
        dbError("forbidden", `${operation} is not enabled for ${table}`),
      );
    }
    const key = (): Result<unknown> =>
      keyParam
        ? keyValue(meta, input.id)
        : err(dbError("invalid_request", `${table} has no single-column key`));

    switch (operation) {
      case "list": {
        if (list) {
          const query = list.parse((input.query ?? {}) as never);
          if (!query.ok) {
            return err(
              dbError("validation", "Invalid list query", {
                issues: query.issues,
              }),
            );
          }
          return settled(
            list.run(db as never, query.value as never, extra as never),
          );
        }
        const page = pageArgs(input.query, maxPageSize);
        if (!page.ok) return page;
        return settled(
          repository.paginate({
            ...extra,
            ...page.data,
            count: "exact",
          } as never),
        );
      }
      case "get": {
        const id = key();
        if (!id.ok) return id;
        return settled(repository.findById(id.data as never, extra as never));
      }
      case "create": {
        const body = asObject(input.data);
        if (!body.ok) return body;
        const data = options.input?.create
          ? await validate(options.input.create, body.data, "data")
          : body;
        if (!data.ok) return data;
        return settled(repository.create(data.data as never, extra as never));
      }
      case "update": {
        const id = key();
        if (!id.ok) return id;
        const body = asObject(input.data);
        if (!body.ok) return body;
        const data = options.input?.update
          ? await validate(options.input.update, body.data, "data")
          : body;
        if (!data.ok) return data;
        return settled(
          repository.update(
            id.data as never,
            data.data as never,
            extra as never,
          ),
        );
      }
      case "delete": {
        const id = key();
        if (!id.ok) return id;
        return settled(repository.delete(id.data as never));
      }
      default: {
        const unknown: never = operation;
        throw new TypeError(`Unknown operation ${String(unknown)}`);
      }
    }
  };

  const collectionMethods = [
    ...(has("list") ? ["GET"] : []),
    ...(has("create") ? ["POST"] : []),
  ];
  const itemMethods = [
    ...(has("get") ? ["GET"] : []),
    ...(has("update") ? ["PATCH"] : []),
    ...(has("delete") ? ["DELETE"] : []),
  ];

  const route = async (
    request: Request,
    db: object,
    id: string | undefined,
  ): Promise<unknown> => {
    if (id === undefined) {
      if (request.method === "GET" && has("list")) {
        return execute(db, "list", {
          query: new URL(request.url).searchParams,
        });
      }
      if (request.method === "POST" && has("create")) {
        const body = await readBody(request);
        return body.ok ? execute(db, "create", { data: body.data }) : body;
      }
      return notAllowed(collectionMethods);
    }
    if (!keyParam) return new Response(null, { status: 404 });
    if (request.method === "GET" && has("get"))
      return execute(db, "get", { id });
    if (request.method === "PATCH" && has("update")) {
      const body = await readBody(request);
      return body.ok ? execute(db, "update", { id, data: body.data }) : body;
    }
    if (request.method === "DELETE" && has("delete")) {
      return execute(db, "delete", { id });
    }
    return notAllowed(itemMethods);
  };

  return {
    table,
    meta,
    operations,
    keyParam,
    list,
    maxPageSize,
    execute,
    handle(request, db, id, respondOptions = {}) {
      const status =
        id === undefined && request.method === "POST" ? 201 : undefined;
      return respond(
        () => route(request, db, id),
        status === undefined ? respondOptions : { ...respondOptions, status },
      );
    },
  };
}
