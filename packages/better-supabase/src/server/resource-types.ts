import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { ValidationIssue } from "../core/errors.ts";
import type { RequestContext } from "../core/plugin.ts";
import type { Result } from "../core/result.ts";
import type { SelectArg } from "../ir/args.ts";
import type {
  AnyModels,
  Insert,
  Row,
  TableKey,
  TableMeta,
  Update,
} from "../schema/types.ts";
import type { ResourceOperation } from "../spec/model.ts";
import type {
  ResourceActionSpec,
  ResourceDescription,
  ResourcePagination,
  ResourcePlan,
} from "../spec/resource.ts";
import type { RespondOptions } from "./respond.ts";

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

export type Parsed<S> = S extends StandardSchemaV1
  ? StandardSchemaV1.InferOutput<S>
  : undefined;

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
   * to `cursor`, or `offset` for a table or view without a primary key.
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
