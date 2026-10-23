import type { AnySchema, MetaPlugin } from "@orpc/server";

import type { Authorizer } from "../core/authorizer.ts";
import type { BetterSupabase } from "../core/define.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type {
  ResourceHandler,
  ResourceRouteOptions,
} from "../server/resource-types.ts";
import type { Api } from "../spec/api.ts";
import type { ModelOperation, TableVerb } from "../spec/model.ts";
import type { ResourceInput } from "../spec/options.ts";

import { callWithInput } from "../blocks/block-method.ts";
import { checkPermission } from "../core/authorizer.ts";
import { instanceProperty } from "../core/db-blocks.ts";
import { dbError } from "../core/errors.ts";
import { isRecord } from "../core/guards.ts";
import { err } from "../core/result.ts";
import { contextOf } from "../server/resource-http.ts";
import { defineResource } from "../server/resource.ts";
import { TABLE_VERBS } from "../spec/resource.ts";

/** The route `router()` gives one operation of the API model. */
export interface ApiRoute {
  readonly method: "GET" | "POST" | "PUT" | "PATCH" | "DELETE";
  readonly path: `/${string}`;
  readonly operationId: string;
  readonly tags: string[];
  readonly summary?: string;
  readonly successStatus: number;
  /**
   * `detailed` for table operations (`{ params, query, body }`), `compact` for
   * verbs (the body).
   */
  readonly inputStructure: "compact" | "detailed";
}

/** Options of `router()`. */
export interface ApiRouterOptions<G> {
  /** Guard and authorize options every procedure runs behind. */
  readonly guard?: G;
  /**
   * Route metadata per procedure: pass `openapi` from `@orpc/openapi`, so
   * `OpenAPIHandler` serves each operation at its documented path.
   */
  readonly meta?: (
    route: ApiRoute,
  ) => MetaPlugin<AnySchema, AnySchema, Record<never, never>>;
  /**
   * Handlers for tables whose hooks or actions `defineApi` can't run from a
   * description, such as `defineResource(betterSupabase, "customers", { hooks
   * })`. A handler passed as the resource in `defineApi` is used as is.
   */
  readonly resources?: Readonly<Record<string, ResourceHandler<unknown>>>;
}

/** What `router()` returns: one procedure per operation, and their routes. */
export interface ApiRouter<P> {
  /** One procedure per operation id, to mount in `os.router()`. */
  readonly procedures: Readonly<Record<string, P>>;
  readonly routes: readonly ApiRoute[];
}

interface Detailed {
  readonly params?: Readonly<Record<string, unknown>>;
  readonly query?: Readonly<Record<string, unknown>>;
  readonly body?: unknown;
}

export interface Call {
  readonly input: unknown;
  readonly db: object;
  readonly request: Request;
}

type Run = ApiProcedureSpec["run"];

const METHODS = {
  get: "GET",
  post: "POST",
  put: "PUT",
  patch: "PATCH",
  delete: "DELETE",
} as const;

function isHandler(input: unknown): input is ResourceHandler<unknown> {
  return (
    isRecord(input) &&
    typeof input["execute"] === "function" &&
    typeof input["verb"] === "function"
  );
}

function detailed(input: unknown): Detailed {
  return isRecord(input) ? input : {};
}

/**
 * Whether `defineResource` can serve a description as it is: a list query with
 * its runner, validators and action handlers. A plain description from a
 * spec-only setup is not.
 */
function servable(table: string, input: ResourceInput<unknown>): void {
  if (input === true || "plan" in input) {
    return;
  }

  if (input.list && !("parse" in input.list)) {
    throw new TypeError(
      `${table}: the list query has no runner; pass the defineListQuery() result, or a handler in router({ resources })`,
    );
  }

  for (const [name, action] of Object.entries(input.actions ?? {})) {
    if (!("handler" in action)) {
      throw new TypeError(
        `${table}.actions.${name} has no handler; pass a defineResource() handler in router({ resources })`,
      );
    }
  }
}

function handlerFor<M extends AnyModels, D, F extends AnyFunctions, E>(
  betterSupabase: BetterSupabase<M, D, F, E>,
  authorizer: Authorizer<unknown> | undefined,
  table: string,
  input: ResourceInput<unknown>,
): ResourceHandler<unknown> {
  if (isHandler(input)) {
    return input;
  }

  if (input !== true && "plan" in input) {
    throw new TypeError(
      `${table}: the resource carries a plan but no handler; pass the defineResource() handler`,
    );
  }

  servable(table, input);

  // SAFETY: servable() checked the description has what defineResource runs
  // (a list runner, Standard Schema validators, action handlers); the table
  // generics are erased here.
  const options = (input === true ? {} : input) as ResourceRouteOptions<
    AnyModels,
    string,
    unknown
  >;

  return defineResource(
    betterSupabase,
    // SAFETY: the API model only publishes tables of this schema.
    table as never,
    // SAFETY: the description was written for this table, so its generics fit.
    options as never,
    authorizer,
  );
}

function successOf(operation: ModelOperation): number {
  const status = Object.keys(operation.responses).find((key) =>
    /^2\d\d$/u.test(key),
  );

  return status === undefined ? 200 : Number(status);
}

function idOf(handler: ResourceHandler<unknown>, input: Detailed): unknown {
  return handler.keyParam === undefined
    ? undefined
    : input.params?.[handler.keyParam];
}

function tableRun(
  handler: ResourceHandler<unknown>,
  operation: ModelOperation,
): Run {
  const { source } = operation;

  switch (source.kind) {
    case "resource": {
      const name = source.operation;

      return ({ input, db, request }) => {
        const parts = detailed(input);

        return handler.execute(db, name, {
          id: idOf(handler, parts),
          data: parts.body,
          ...(parts.query ? { query: parts.query } : {}),
          request,
        });
      };
    }

    case "action": {
      const name = source.action;

      return ({ input, db, request }) => {
        const parts = detailed(input);

        return handler.action(db, name, {
          id: idOf(handler, parts),
          data: parts.body,
          ...(parts.query ? { query: parts.query } : {}),
          request,
        });
      };
    }

    case "verb": {
      const verb = TABLE_VERBS.find((each) => each === source.verb);

      if (verb === undefined) {
        throw new TypeError(`${handler.table}: unknown verb ${source.verb}`);
      }

      return ({ input, db, request }) =>
        handler.verb(db, verb satisfies TableVerb, { data: input, request });
    }

    case "data-api":
    case "route":
    case "fragment": {
      throw new TypeError(
        `${operation.id} is not a table operation of ${handler.table}`,
      );
    }

    default: {
      const unknown: never = source;
      throw new TypeError(`Unknown operation source ${String(unknown)}`);
    }
  }
}

function blockRun(
  api: Api,
  authorizer: Authorizer<unknown> | undefined,
  operation: ModelOperation,
): Run {
  const { source } = operation;

  if (source.kind !== "verb" || source.owner !== "block") {
    throw new TypeError(`${operation.id} is not a block verb`);
  }

  const property = instanceProperty(source.name);

  const name =
    source.member === undefined
      ? source.verb
      : `${source.member}.${source.verb}`;

  const permission = api.blocks[source.name]?.permissions?.[name];

  return async ({ input, db }) => {
    if (permission !== undefined) {
      const permitted = await checkPermission({
        authorizer,
        permission,
        resource: { type: source.name },
        context: contextOf(db),
      });

      if (!permitted.ok) {
        return permitted;
      }
    }

    const blocks = "$blocks" in db ? db.$blocks : undefined;
    const instance = isRecord(blocks) ? blocks[property] : undefined;

    const client =
      source.member === undefined || !isRecord(instance)
        ? instance
        : instance[source.member];

    if (!isRecord(client)) {
      return err(
        dbError("not_found", `The db has no ${source.name} block instance`),
      );
    }

    return callWithInput(client, source.verb, input);
  };
}

/** One served operation: its route and what runs it. */
export interface ApiProcedureSpec {
  readonly route: ApiRoute;
  readonly run: (call: Call) => unknown;
}

/**
 * The route and runner of every operation of the API model that has a server
 * here: table operations run through `defineResource`, verbs through the
 * repository or the block instance's client on the caller's Db. Custom routes
 * and the Data API stay with whoever serves them.
 */
export function apiProcedures<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
>(
  betterSupabase: BetterSupabase<M, D, F, E>,
  authorizer: Authorizer<unknown> | undefined,
  api: Api,
  resources: ApiRouterOptions<unknown>["resources"] = {},
): ApiProcedureSpec[] {
  const handlers = new Map<string, ResourceHandler<unknown>>();

  for (const [table, input] of Object.entries(api.resources)) {
    handlers.set(
      table,
      resources[table] ?? handlerFor(betterSupabase, authorizer, table, input),
    );
  }

  return api.model.operations.flatMap((operation): ApiProcedureSpec[] => {
    const { source } = operation;
    let run: Run;

    if (source.kind === "verb" && source.owner === "block") {
      run = blockRun(api, authorizer, operation);
    } else if (
      source.kind === "resource" ||
      source.kind === "action" ||
      source.kind === "verb"
    ) {
      const handler = handlers.get(
        source.kind === "verb" ? source.name : source.table,
      );

      if (!handler) {
        return [];
      }

      run = tableRun(handler, operation);
    } else {
      return [];
    }

    const method = Object.entries(METHODS).find(
      ([name]) => name === operation.method,
    )?.[1];

    if (method === undefined || !operation.path.startsWith("/")) {
      return [];
    }

    const route: ApiRoute = {
      method,
      path: `/${operation.path.slice(1)}`,
      operationId: operation.id,
      tags: [...operation.tags],
      ...(operation.summary === undefined
        ? {}
        : { summary: operation.summary }),
      successStatus: successOf(operation),
      inputStructure: source.kind === "verb" ? "compact" : "detailed",
    };

    return [{ route, run }];
  });
}
