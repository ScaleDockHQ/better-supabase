import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { BetterSupabase } from "../core/define.ts";
import type { RequestContext } from "../core/plugin.ts";
import type { RepositoryOf } from "../core/repository-types.ts";
import type { SelectArg } from "../ir/args.ts";
import type {
  AnyFunctions,
  AnyModels,
  Insert,
  Row,
  TableKey,
  TableMeta,
  Update,
} from "../schema/types.ts";
import type { ResourceOperation } from "../spec/model.ts";

import {
  checkEach,
  checkPermission,
  type AuthorizationResource,
  type Authorizer,
} from "../core/authorizer.ts";
import { dbError, isDbError, type ValidationIssue } from "../core/errors.ts";
import { methodNotAllowed } from "../core/problem.ts";
import { err, ok, toDbError, type Result } from "../core/result.ts";
import { validate } from "../core/standard.ts";
import {
  matchAction,
  planResource,
  type PlannedAction,
  type ResourceActionSpec,
  type ResourceDescription,
  type ResourcePagination,
  type ResourcePlan,
} from "../spec/resource.ts";
import { isResult, respond, type RespondOptions } from "./respond.ts";

export type { ResourcePagination } from "../spec/resource.ts";

/** What a resource needs from `defineListQuery`. */
export interface ResourceList {
  readonly table: string;
  readonly pagination?: ResourcePagination;
  readonly openapi: readonly unknown[];
  readonly jsonSchema: Readonly<Record<string, unknown>>;
  parse(
    input: never,
  ):
    | { readonly ok: true; readonly value: unknown }
    | { readonly ok: false; readonly issues: readonly ValidationIssue[] };
  run(db: never, query: never, extra?: never): PromiseLike<unknown>;
}

/** What hooks and action handlers receive. */
export interface ResourceContext<DbT = unknown> {
  /** The repositories, bound to the caller (RLS applies). */
  readonly db: DbT;
  readonly table: string;
  /** The HTTP request, when the call came from one. */
  readonly request: Request | undefined;
  /** The verified request context: actor, tenant and claims. */
  readonly context: RequestContext;
}

type HookResult<T> = Result<T> | PromiseLike<Result<T>>;

/** The target of an item operation or action. `row` is set when a permission check fetched it. */
export interface ResourceTarget<R> {
  readonly id?: unknown;
  readonly data?: unknown;
  readonly query?: unknown;
  readonly row?: R;
}

/** A list response: the page's rows plus its paging fields. */
export interface ResourcePage<R> {
  readonly items: readonly R[];
  readonly [field: string]: unknown;
}

/**
 * Business logic around the repository. Every hook returns a `Result`; an
 * error `Result` ends the request with that error, and a throw becomes an
 * `unexpected` error. Hooks run after the authorizer.
 */
export interface ResourceHooks<
  M extends AnyModels,
  T extends TableKey<M>,
  DbT = unknown,
> {
  /** Runs before every operation and action; an error denies it. */
  authorize?(
    ctx: ResourceContext<DbT>,
    operation: ResourceOperation | (string & {}),
    target: ResourceTarget<Row<M, T>>,
  ): HookResult<unknown>;
  /** Returns the values to insert. */
  beforeCreate?(
    ctx: ResourceContext<DbT>,
    data: Insert<M, T>,
  ): HookResult<Insert<M, T>>;
  /** Returns the values to update. */
  beforeUpdate?(
    ctx: ResourceContext<DbT>,
    data: Update<M, T>,
    target: ResourceTarget<Row<M, T>>,
  ): HookResult<Update<M, T>>;
  beforeDelete?(
    ctx: ResourceContext<DbT>,
    target: ResourceTarget<Row<M, T>>,
  ): HookResult<unknown>;
  /** Returns the response; describe a changed shape in `output.list`. */
  afterList?(
    ctx: ResourceContext<DbT>,
    page: ResourcePage<Row<M, T>>,
  ): HookResult<unknown>;
  afterGet?(ctx: ResourceContext<DbT>, row: Row<M, T>): HookResult<unknown>;
  afterCreate?(ctx: ResourceContext<DbT>, row: Row<M, T>): HookResult<unknown>;
  afterUpdate?(ctx: ResourceContext<DbT>, row: Row<M, T>): HookResult<unknown>;
}

/** What an action handler receives besides the context: values already validated. */
export interface ActionArgs<I = unknown, Q = unknown> {
  /** The parsed key, for item actions (`/{id}/send`). */
  readonly id: unknown;
  readonly data: I;
  readonly query: Q;
}

/**
 * A custom operation (`POST /<table>/{id}/send`). The handler returns a
 * `Result`, a plain value or a `Response`; a throw becomes an `unexpected`
 * error.
 */
export interface ResourceAction<
  Ref = string,
  DbT = unknown,
> extends ResourceActionSpec<Ref> {
  handler(ctx: ResourceContext<DbT>, args: ActionArgs): unknown;
}

type Parsed<S> = S extends StandardSchemaV1
  ? StandardSchemaV1.InferOutput<S>
  : undefined;

/** Defines an action and types its handler's `data` and `query` from the schemas. */
export function defineAction<
  DbT = unknown,
  Ref = string,
  I extends StandardSchemaV1 | undefined = undefined,
  Q extends StandardSchemaV1 | undefined = undefined,
>(
  action: Omit<ResourceActionSpec<Ref>, "input" | "query"> & {
    readonly input?: I;
    readonly query?: Q;
    handler(
      ctx: ResourceContext<DbT>,
      args: ActionArgs<Parsed<I>, Parsed<Q>>,
    ): unknown;
  },
): ResourceAction<Ref, DbT> {
  // SAFETY: the handler only receives data and query validated by these schemas.
  return action as ResourceAction<Ref, DbT>;
}

export interface ResourceRouteOptions<
  M extends AnyModels,
  T extends TableKey<M>,
  Ref = string,
  DbT = unknown,
> extends Omit<
  ResourceDescription<Ref>,
  "list" | "input" | "actions" | "operations" | "pagination" | "maxPageSize"
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
  /**
   * Paging of the default list: `offset` (`page` and `size`) or `cursor`
   * (`after` and `size`, keyset). A `list` query brings its own. Defaults
   * to `offset`.
   */
  readonly pagination?: ResourcePagination;
  /** Largest page for the default list. Defaults to 200. */
  readonly maxPageSize?: number;
  readonly hooks?: ResourceHooks<M, T, DbT>;
  readonly actions?: Readonly<Record<string, ResourceAction<Ref, DbT>>>;
}

export interface ResourceInput {
  /** Primary key value; strings are converted for integer keys. */
  readonly id?: unknown;
  /** Body of `create`, `update` and actions. */
  readonly data?: unknown;
  /** `list` and action parameters: URL params or typed values. */
  readonly query?: URLSearchParams | Readonly<Record<string, unknown>>;
  /** The HTTP request, passed on to hooks and actions. */
  readonly request?: Request;
}

export interface ResourceHandler<Ref = string> {
  readonly table: string;
  readonly meta: TableMeta;
  readonly operations: readonly ResourceOperation[];
  /** Name of the key parameter, or `undefined` for tables without a single-column key. */
  readonly keyParam: string | undefined;
  readonly list: ResourceList | undefined;
  readonly pagination: ResourcePagination;
  readonly maxPageSize: number;
  /** What the resource serves; `defineApi` documents the same plan. */
  readonly plan: ResourcePlan<Ref>;
  /** Runs one operation as whoever `db` is bound to. Resolves to a `Result`. */
  execute(
    db: object,
    operation: ResourceOperation,
    input?: ResourceInput,
  ): Promise<Result<unknown>>;
  /** Runs one action by name. Resolves to a `Result`. */
  action(
    db: object,
    name: string,
    input?: ResourceInput,
  ): Promise<Result<unknown>>;
  /** Serves a collection request (`id` undefined) or an item request. Actions are not routed. */
  handle(
    request: Request,
    db: object,
    id: string | undefined,
    options?: RespondOptions,
  ): Promise<Response>;
  /**
   * Serves the collection (`[]`), an item (`[id]`) or an action path
   * (`[id, "send"]`), below the resource's own path. A string is split on `/`
   * and decoded.
   */
  serve(
    request: Request,
    db: object,
    subpath: string | readonly string[],
    options?: RespondOptions,
  ): Promise<Response>;
}

type AnyRepository = RepositoryOf<AnyModels, string, unknown>;

const INTEGER = new Set(["int2", "int4", "int8"]);

function keyValue(table: TableMeta, raw: unknown): Result<unknown> {
  const invalid = err(
    dbError(
      "invalid_input",
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

/**
 * A cross-site browser request that needed no CORS preflight: a form post
 * riding on the session cookie. Bearer requests and JSON bodies (which need a
 * preflight) pass, as do requests without an `Origin` (not a browser).
 */
function crossSiteSimpleRequest(request: Request): boolean {
  if (request.method === "GET" || request.method === "HEAD") return false;
  if (request.headers.has("authorization")) return false;
  const origin = request.headers.get("origin");
  if (!origin || origin === new URL(request.url).origin) return false;
  if (request.headers.get("sec-fetch-site") === "same-origin") return false;
  const type = request.headers.get("content-type") ?? "";
  return !/^application\/(?:[\w.+-]+\+)?json\b/iu.test(type);
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
    dbError("invalid_input", "The request body must be a JSON object"),
  );
}

/** Any JSON body; an empty body is `undefined`. */
async function readJson(request: Request): Promise<Result<unknown>> {
  const text = await request.text();
  if (text.trim() === "") return ok(undefined);
  try {
    return ok(JSON.parse(text));
  } catch {
    return err(dbError("invalid_input", "The request body must be JSON"));
  }
}

/** URL parameters as an object; a repeated name becomes an array. */
function queryObject(
  query: ResourceInput["query"],
): Readonly<Record<string, unknown>> {
  if (!(query instanceof URLSearchParams)) return query ?? {};
  const values: Record<string, string | string[]> = {};
  for (const [name, value] of query) {
    const seen = values[name];
    values[name] =
      seen === undefined
        ? value
        : [...(Array.isArray(seen) ? seen : [seen]), value];
  }
  return values;
}

function pageArgs(
  query: ResourceInput["query"],
  max: number,
  pagination: ResourcePagination,
): Result<
  { page: number; size: number } | { after: string | null; size: number }
> {
  const raw = (name: string): unknown => {
    const value: unknown =
      query instanceof URLSearchParams ? query.get(name) : query?.[name];
    return value === null || value === "" ? undefined : value;
  };
  const read = (name: string, fallback: number): number | undefined => {
    const value = raw(name);
    if (value === undefined) return fallback;
    const number = Number(value);
    return Number.isSafeInteger(number) && number >= 1 ? number : undefined;
  };
  const issues: ValidationIssue[] = [];
  const size = read("size", 50);
  if (size === undefined || size > max)
    issues.push({ message: `Must be between 1 and ${max}`, path: ["size"] });
  const [used, unused] =
    pagination === "cursor" ? ["after", "page"] : ["page", "after"];
  if (raw(unused) !== undefined)
    issues.push({
      message: `This list pages with \`${used}\``,
      path: [unused],
    });
  const page = read("page", 1);
  if (pagination === "offset" && page === undefined)
    issues.push({ message: "Must be a positive integer", path: ["page"] });
  const after = raw("after");
  if (
    pagination === "cursor" &&
    after !== undefined &&
    typeof after !== "string"
  )
    issues.push({ message: "Must be text", path: ["after"] });
  if (issues.length > 0 || size === undefined) {
    return err(dbError("validation", "Invalid page parameters", { issues }));
  }
  return pagination === "cursor"
    ? ok({ after: typeof after === "string" ? after : null, size })
    : ok({ page: page ?? 1, size });
}

function asObject(value: unknown): Result<unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? ok(value)
    : err(dbError("invalid_input", "Expected an object of column values"));
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

async function settled(value: unknown): Promise<Result<unknown>> {
  // SAFETY: repository methods resolve to a Result, and every caller passes one.
  return (await value) as Result<unknown>;
}

function failure(cause: unknown, message: string): Result<never> {
  if (isDbError(cause)) return err(cause);
  const error = toDbError(cause);
  return err(
    error.kind === "unexpected" ? dbError("unexpected", message) : error,
  );
}

/** Runs a hook: its `Result` passes through, anything else is an `unexpected` error. */
async function runHook(
  name: string,
  call: () => unknown,
): Promise<Result<unknown>> {
  try {
    const value: unknown = await call();
    if (!isResult(value)) {
      return err(
        dbError("unexpected", `The ${name} hook must return a Result`),
      );
    }
    return value.ok
      ? ok(value.data)
      : failure(value.error, `The ${name} hook failed`);
  } catch (cause) {
    return failure(cause, `The ${name} hook failed`);
  }
}

/** Runs an action handler: a `Result` unwraps, a plain value is the data. */
async function runHandler(
  name: string,
  call: () => unknown,
): Promise<Result<unknown>> {
  try {
    const value: unknown = await call();
    if (!isResult(value)) return ok(value);
    return value.ok
      ? ok(value.data)
      : failure(value.error, `The ${name} action failed`);
  } catch (cause) {
    return failure(cause, `The ${name} action failed`);
  }
}

function contextOf(db: object): RequestContext {
  const value = "$context" in db ? db.$context : undefined;
  return isRecord(value) ? value : {};
}

function splitPath(
  subpath: string | readonly string[],
): Result<readonly string[]> {
  if (typeof subpath !== "string") return ok(subpath);
  try {
    return ok(
      subpath
        .split("/")
        .filter((segment) => segment !== "")
        .map((segment) => decodeURIComponent(segment)),
    );
  } catch {
    return err(dbError("invalid_input", `Malformed path ${subpath}`));
  }
}

/** Whether an action's path fits these segments, whatever the method. */
export function actionFits(
  action: PlannedAction<unknown>,
  segments: readonly string[],
): boolean {
  return (
    action.segments.length === segments.length &&
    action.segments.every((segment, index) =>
      segment.startsWith("{")
        ? segments[index] !== ""
        : segment === segments[index],
    )
  );
}

/**
 * Operations over one table, matching the paths and responses of the API
 * model: `GET/POST /<table>`, `GET/PATCH/DELETE /<table>/{id}` and each
 * action's path. Shared by the HTTP adapters and the MCP table tools.
 *
 * With permissions, the authorizer decides before the repository runs:
 * `get`, `update` and `delete` fetch the row first (under RLS) and pass it
 * as the resource's properties, and `list` keeps only the rows it grants.
 */
export function defineResource<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  T extends TableKey<M>,
  Ref = string,
  DbT = unknown,
>(
  betterSupabase: BetterSupabase<M, D, F, E>,
  table: T,
  options: ResourceRouteOptions<M, T, NoInfer<Ref>, DbT> = {},
  authorizer?: Authorizer<Ref>,
): ResourceHandler<Ref> {
  if (options.list && options.list.table !== table) {
    throw new TypeError(
      `The list query is for "${options.list.table}", not "${table}"`,
    );
  }
  const plan = planResource<Ref>(
    betterSupabase.meta,
    table,
    options,
    authorizer,
  );
  const { meta, operations, keyParam, pagination, maxPageSize } = plan;
  const has = (operation: ResourceOperation): boolean =>
    operations.includes(operation);
  const extra = options.select === undefined ? {} : { select: options.select };
  const list = options.list;
  // SAFETY: hooks are typed per table for callers; here the table generics are erased.
  const hooks = (options.hooks ?? {}) as ResourceHooks<AnyModels, string>;

  const resourceOf = (id: unknown, row: unknown): AuthorizationResource => ({
    type: table,
    ...(id === undefined ? {} : { id: String(id) }),
    ...(isRecord(row) ? { properties: row } : {}),
  });
  const permit = (
    name: string,
    db: object,
    resource: AuthorizationResource,
  ): Promise<Result<void>> | Result<void> => {
    const permission = plan.permissions[name];
    if (permission === undefined) return ok(undefined);
    return checkPermission({
      authorizer,
      permission,
      resource,
      context: contextOf(db),
    });
  };
  const ctxOf = (db: object, input: ResourceInput): ResourceContext => ({
    db,
    table,
    request: input.request,
    context: contextOf(db),
  });
  const after = async (
    name: "afterList" | "afterGet" | "afterCreate" | "afterUpdate",
    ctx: ResourceContext,
    result: Result<unknown>,
  ): Promise<Result<unknown>> => {
    const run = hooks[name];
    if (!run || !result.ok) return result;
    // SAFETY: the hook takes the row (or page) the repository just returned.
    return runHook(name, () => run.call(hooks, ctx, result.data as never));
  };
  const authorize = async (
    ctx: ResourceContext,
    operation: string,
    target: ResourceTarget<unknown>,
  ): Promise<Result<unknown>> =>
    hooks.authorize
      ? runHook("authorize", () =>
          // SAFETY: the target holds this table's row, typed per table for callers.
          hooks.authorize!(ctx, operation, target as never),
        )
      : ok(undefined);

  const repositoryOf = (db: object): AnyRepository => {
    // SAFETY: the db is indexed by table name, and a missing repository is checked below.
    const repository = (db as Record<string, AnyRepository>)[table];
    if (!repository) throw new TypeError(`The db has no "${table}" repository`);
    return repository;
  };
  const key = (raw: unknown): Result<unknown> =>
    keyParam
      ? keyValue(meta, raw)
      : err(dbError("invalid_request", `${table} has no single-column key`));
  /** Fetches the row a permission decision reads, under the caller's RLS. */
  const rowFor = async (
    name: string,
    db: object,
    id: unknown,
  ): Promise<Result<unknown>> => {
    if (plan.permissions[name] === undefined) return ok(undefined);
    // SAFETY: the resource erases table generics; id was parsed for this key.
    return settled(repositoryOf(db).findById(id as never));
  };

  const filterRows = async (
    db: object,
    result: Result<unknown>,
  ): Promise<Result<unknown>> => {
    const permission = plan.permissions["list"];
    if (permission === undefined || !result.ok) return result;
    if (!authorizer) {
      const denied = await checkPermission({
        authorizer,
        permission,
        resource: { type: table },
        context: contextOf(db),
      });
      if (!denied.ok) return denied;
    }
    const page = result.data;
    if (!isRecord(page) || !Array.isArray(page["items"])) return result;
    const items: readonly unknown[] = page["items"];
    const granted = await checkEach(
      authorizer,
      permission,
      items.map((row) =>
        resourceOf(keyParam && isRecord(row) ? row[keyParam] : undefined, row),
      ),
      contextOf(db),
    );
    return ok({ ...page, items: items.filter((_, index) => granted[index]) });
  };

  const execute = async (
    db: object,
    operation: ResourceOperation,
    input: ResourceInput = {},
  ): Promise<Result<unknown>> => {
    const repository = repositoryOf(db);
    if (!has(operation)) {
      return err(
        dbError("forbidden", `${operation} is not enabled for ${table}`),
      );
    }
    const ctx = ctxOf(db, input);

    switch (operation) {
      case "list": {
        let run: () => Promise<Result<unknown>>;
        let query: unknown = input.query;
        if (list) {
          // SAFETY: the resource erases table generics; the list config and its
          // repository come from the same table.
          const parsed = list.parse((input.query ?? {}) as never);
          if (!parsed.ok) {
            return err(
              dbError("validation", "Invalid list query", {
                issues: parsed.issues,
              }),
            );
          }
          query = parsed.value;
          // SAFETY: the resource erases table generics; the list config and its
          // repository come from the same table.
          run = () =>
            settled(
              list.run(db as never, parsed.value as never, extra as never),
            );
        } else {
          const page = pageArgs(input.query, maxPageSize, pagination);
          if (!page.ok) return page;
          query = page.data;
          run = () =>
            settled(
              // SAFETY: the resource erases table generics; page holds validated
              // paginate options for this table.
              repository.paginate({
                ...extra,
                ...page.data,
                ...("page" in page.data ? { count: "exact" } : {}),
              } as never),
            );
        }
        const allowed = await authorize(ctx, "list", { query });
        if (!allowed.ok) return allowed;
        return after("afterList", ctx, await filterRows(db, await run()));
      }
      case "get": {
        const id = key(input.id);
        if (!id.ok) return id;
        // SAFETY: the resource erases table generics; key() parsed the id for
        // this table's primary key.
        const row = await settled(
          repository.findById(id.data as never, extra as never),
        );
        if (!row.ok) return row;
        const permitted = await permit(
          "get",
          db,
          resourceOf(id.data, row.data),
        );
        if (!permitted.ok) return permitted;
        const allowed = await authorize(ctx, "get", {
          id: id.data,
          row: row.data,
        });
        if (!allowed.ok) return allowed;
        return after("afterGet", ctx, row);
      }
      case "create": {
        const body = asObject(input.data);
        if (!body.ok) return body;
        const data = options.input?.create
          ? await validate(options.input.create, body.data, "data")
          : body;
        if (!data.ok) return data;
        const permitted = await permit(
          "create",
          db,
          resourceOf(undefined, data.data),
        );
        if (!permitted.ok) return permitted;
        const allowed = await authorize(ctx, "create", { data: data.data });
        if (!allowed.ok) return allowed;
        const values = hooks.beforeCreate
          ? await runHook("beforeCreate", () =>
              // SAFETY: the resource erases table generics; data was validated for this table.
              hooks.beforeCreate!(ctx, data.data as never),
            )
          : data;
        if (!values.ok) return values;
        // SAFETY: the resource erases table generics; the body was validated
        // against the table's insert schema.
        const created = await settled(
          repository.create(values.data as never, extra as never),
        );
        return after("afterCreate", ctx, created);
      }
      case "update": {
        const id = key(input.id);
        if (!id.ok) return id;
        const body = asObject(input.data);
        if (!body.ok) return body;
        const data = options.input?.update
          ? await validate(options.input.update, body.data, "data")
          : body;
        if (!data.ok) return data;
        const row = await rowFor("update", db, id.data);
        if (!row.ok) return row;
        const permitted = await permit(
          "update",
          db,
          resourceOf(id.data, row.data),
        );
        if (!permitted.ok) return permitted;
        const target = {
          id: id.data,
          data: data.data,
          ...(row.data === undefined ? {} : { row: row.data }),
        };
        const allowed = await authorize(ctx, "update", target);
        if (!allowed.ok) return allowed;
        const values = hooks.beforeUpdate
          ? await runHook("beforeUpdate", () =>
              // SAFETY: the resource erases table generics; data was validated for this table.
              hooks.beforeUpdate!(ctx, data.data as never, target as never),
            )
          : data;
        if (!values.ok) return values;
        // SAFETY: the resource erases table generics; the id and body were
        // parsed for this table.
        const updated = await settled(
          repository.update(
            id.data as never,
            values.data as never,
            extra as never,
          ),
        );
        return after("afterUpdate", ctx, updated);
      }
      case "delete": {
        const id = key(input.id);
        if (!id.ok) return id;
        const row = await rowFor("delete", db, id.data);
        if (!row.ok) return row;
        const permitted = await permit(
          "delete",
          db,
          resourceOf(id.data, row.data),
        );
        if (!permitted.ok) return permitted;
        const target = {
          id: id.data,
          ...(row.data === undefined ? {} : { row: row.data }),
        };
        const allowed = await authorize(ctx, "delete", target);
        if (!allowed.ok) return allowed;
        if (hooks.beforeDelete) {
          const before = await runHook("beforeDelete", () =>
            // SAFETY: the target holds this table's row, typed per table for callers.
            hooks.beforeDelete!(ctx, target as never),
          );
          if (!before.ok) return before;
        }
        // SAFETY: the resource erases table generics; key() parsed the id for
        // this table's primary key.
        return settled(repository.delete(id.data as never));
      }
      default: {
        const unknown: never = operation;
        throw new TypeError(`Unknown operation ${String(unknown)}`);
      }
    }
  };

  const action = async (
    db: object,
    name: string,
    input: ResourceInput = {},
  ): Promise<Result<unknown>> => {
    const planned = plan.actions.find((candidate) => candidate.name === name);
    const actions: ResourceRouteOptions<AnyModels, string, Ref>["actions"] =
      options.actions;
    const definition = actions?.[name];
    if (!planned || !definition) {
      return err(dbError("not_found", `${table} has no action ${name}`));
    }
    let id: unknown;
    if (planned.params.length > 0) {
      const parsed = key(input.id);
      if (!parsed.ok) return parsed;
      id = parsed.data;
    }
    let data: unknown = input.data;
    if (planned.input) {
      // SAFETY: action inputs are Standard Schemas; StandardLike only narrows the marker.
      const parsed = await validate(
        planned.input as StandardSchemaV1,
        data,
        "data",
      );
      if (!parsed.ok) return parsed;
      data = parsed.data;
    }
    let query: unknown = queryObject(input.query);
    if (planned.query) {
      // SAFETY: action queries are Standard Schemas; StandardLike only narrows the marker.
      const parsed = await validate(
        planned.query as StandardSchemaV1,
        query,
        "query",
      );
      if (!parsed.ok) return parsed;
      query = parsed.data;
    }
    const row = id === undefined ? ok(undefined) : await rowFor(name, db, id);
    if (!row.ok) return row;
    const permitted = await permit(name, db, resourceOf(id, row.data ?? data));
    if (!permitted.ok) return permitted;
    const ctx = ctxOf(db, input);
    const allowed = await authorize(ctx, name, {
      id,
      data,
      query,
      ...(row.data === undefined ? {} : { row: row.data }),
    });
    if (!allowed.ok) return allowed;
    return runHandler(name, () => definition.handler(ctx, { id, data, query }));
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

  type Routed = readonly [value: unknown, status?: number];

  const route = async (
    request: Request,
    db: object,
    segments: readonly string[],
    actions: boolean,
  ): Promise<Routed> => {
    if (crossSiteSimpleRequest(request)) {
      return [
        err(
          dbError(
            "forbidden",
            "Cross-site requests need Content-Type: application/json or a bearer token",
            { code: "CROSS_SITE_REQUEST" },
          ),
        ),
      ];
    }
    if (actions && segments.length > 0) {
      const method = request.method === "HEAD" ? "GET" : request.method;
      const found = matchAction(plan, method, segments);
      if (found === "method") {
        return [
          methodNotAllowed(
            plan.actions
              .filter((candidate) => actionFits(candidate, segments))
              .map((candidate) => candidate.method),
          ),
        ];
      }
      if (found) {
        const body = method === "GET" ? ok(undefined) : await readJson(request);
        if (!body.ok) return [body];
        const id = keyParam ? found.params[keyParam] : undefined;
        const value = await action(db, found.action.name, {
          id,
          data: body.data,
          query: new URL(request.url).searchParams,
          request,
        });
        return [value, found.action.status ?? 200];
      }
    }
    if (segments.length === 0) {
      if (request.method === "GET" && has("list")) {
        return [
          await execute(db, "list", {
            query: new URL(request.url).searchParams,
            request,
          }),
        ];
      }
      if (request.method === "POST" && has("create")) {
        const body = await readBody(request);
        return [
          body.ok
            ? await execute(db, "create", { data: body.data, request })
            : body,
          201,
        ];
      }
      return [methodNotAllowed(collectionMethods)];
    }
    if (segments.length > 1 || !keyParam)
      return [new Response(null, { status: 404 })];
    const id = segments[0];
    if (request.method === "GET" && has("get"))
      return [await execute(db, "get", { id, request })];
    if (request.method === "PATCH" && has("update")) {
      const body = await readBody(request);
      return [
        body.ok
          ? await execute(db, "update", { id, data: body.data, request })
          : body,
      ];
    }
    if (request.method === "DELETE" && has("delete")) {
      return [await execute(db, "delete", { id, request })];
    }
    return [methodNotAllowed(itemMethods)];
  };

  const reply = async (
    routed: () => Promise<Routed>,
    respondOptions: RespondOptions,
  ): Promise<Response> => {
    const [value, status] = await routed();
    return respond(
      () => value,
      status === undefined ? respondOptions : { ...respondOptions, status },
    );
  };

  return {
    table,
    meta,
    operations,
    keyParam,
    list,
    pagination,
    maxPageSize,
    plan,
    execute,
    action,
    handle(request, db, id, respondOptions = {}) {
      return reply(
        () => route(request, db, id === undefined ? [] : [id], false),
        respondOptions,
      );
    },
    serve(request, db, subpath, respondOptions = {}) {
      const segments = splitPath(subpath);
      return reply(
        async () =>
          segments.ok ? route(request, db, segments.data, true) : [segments],
        respondOptions,
      );
    },
  };
}
