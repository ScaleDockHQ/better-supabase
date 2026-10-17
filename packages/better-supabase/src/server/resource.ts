import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { BetterSupabase } from "../core/define.ts";
import type { RepositoryOf } from "../core/repository-types.ts";
import type { AnyFunctions, AnyModels, TableKey } from "../schema/types.ts";
import type { ResourceOperation } from "../spec/model.ts";
import type {
  ResourceContext,
  ResourceHandler,
  ResourceHooks,
  ResourceInput,
  ResourceRouteOptions,
  ResourceTarget,
} from "./resource-types.ts";

import {
  checkEach,
  checkPermission,
  type AuthorizationResource,
  type Authorizer,
} from "../core/authorizer.ts";
import { dbError } from "../core/errors.ts";
import { isRecord } from "../core/guards.ts";
import { methodNotAllowed } from "../core/problem.ts";
import { err, ok, type Result } from "../core/result.ts";
import { validate } from "../core/standard.ts";
import { matchAction, planResource } from "../spec/resource.ts";
import { runHandler, runHook, settled } from "./resource-execute.ts";
import {
  actionFits,
  asObject,
  contextOf,
  crossSiteSimpleRequest,
  keyValue,
  pageArgs,
  queryObject,
  readBody,
  readJson,
  splitPath,
} from "./resource-http.ts";
import { respond, type RespondOptions } from "./respond.ts";

type AnyRepository = RepositoryOf<AnyModels, string, unknown>;

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
    if (permission === undefined) {
      return ok(undefined);
    }
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
    if (!run || !result.ok) {
      return result;
    }
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
    if (!repository) {
      throw new TypeError(`The db has no "${table}" repository`);
    }
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
    if (plan.permissions[name] === undefined) {
      return ok(undefined);
    }
    // SAFETY: the resource erases table generics; id was parsed for this key.
    return settled(repositoryOf(db).findById(id as never));
  };

  const filterRows = async (
    db: object,
    result: Result<unknown>,
  ): Promise<Result<unknown>> => {
    const permission = plan.permissions["list"];
    if (permission === undefined || !result.ok) {
      return result;
    }
    if (!authorizer) {
      const denied = await checkPermission({
        authorizer,
        permission,
        resource: { type: table },
        context: contextOf(db),
      });
      if (!denied.ok) {
        return denied;
      }
    }
    const page = result.data;
    if (!isRecord(page) || !Array.isArray(page["items"])) {
      return result;
    }
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
          if (!page.ok) {
            return page;
          }
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
        if (!allowed.ok) {
          return allowed;
        }
        return after("afterList", ctx, await filterRows(db, await run()));
      }
      case "get": {
        const id = key(input.id);
        if (!id.ok) {
          return id;
        }
        // SAFETY: the resource erases table generics; key() parsed the id for
        // this table's primary key.
        const row = await settled(
          repository.findById(id.data as never, extra as never),
        );
        if (!row.ok) {
          return row;
        }
        const permitted = await permit(
          "get",
          db,
          resourceOf(id.data, row.data),
        );
        if (!permitted.ok) {
          return permitted;
        }
        const allowed = await authorize(ctx, "get", {
          id: id.data,
          row: row.data,
        });
        if (!allowed.ok) {
          return allowed;
        }
        return after("afterGet", ctx, row);
      }
      case "create": {
        const body = asObject(input.data);
        if (!body.ok) {
          return body;
        }
        const data = options.input?.create
          ? await validate(options.input.create, body.data, "data")
          : body;
        if (!data.ok) {
          return data;
        }
        const permitted = await permit(
          "create",
          db,
          resourceOf(undefined, data.data),
        );
        if (!permitted.ok) {
          return permitted;
        }
        const allowed = await authorize(ctx, "create", { data: data.data });
        if (!allowed.ok) {
          return allowed;
        }
        const values = hooks.beforeCreate
          ? await runHook("beforeCreate", () =>
              // SAFETY: the resource erases table generics; data was validated for this table.
              hooks.beforeCreate!(ctx, data.data as never),
            )
          : data;
        if (!values.ok) {
          return values;
        }
        // SAFETY: the resource erases table generics; the body was validated
        // against the table's insert schema.
        const created = await settled(
          repository.create(values.data as never, extra as never),
        );
        return after("afterCreate", ctx, created);
      }
      case "update": {
        const id = key(input.id);
        if (!id.ok) {
          return id;
        }
        const body = asObject(input.data);
        if (!body.ok) {
          return body;
        }
        const data = options.input?.update
          ? await validate(options.input.update, body.data, "data")
          : body;
        if (!data.ok) {
          return data;
        }
        const row = await rowFor("update", db, id.data);
        if (!row.ok) {
          return row;
        }
        const permitted = await permit(
          "update",
          db,
          resourceOf(id.data, row.data),
        );
        if (!permitted.ok) {
          return permitted;
        }
        const target = {
          id: id.data,
          data: data.data,
          ...(row.data === undefined ? {} : { row: row.data }),
        };
        const allowed = await authorize(ctx, "update", target);
        if (!allowed.ok) {
          return allowed;
        }
        const values = hooks.beforeUpdate
          ? await runHook("beforeUpdate", () =>
              // SAFETY: the resource erases table generics; data was validated for this table.
              hooks.beforeUpdate!(ctx, data.data as never, target as never),
            )
          : data;
        if (!values.ok) {
          return values;
        }
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
        if (!id.ok) {
          return id;
        }
        const row = await rowFor("delete", db, id.data);
        if (!row.ok) {
          return row;
        }
        const permitted = await permit(
          "delete",
          db,
          resourceOf(id.data, row.data),
        );
        if (!permitted.ok) {
          return permitted;
        }
        const target = {
          id: id.data,
          ...(row.data === undefined ? {} : { row: row.data }),
        };
        const allowed = await authorize(ctx, "delete", target);
        if (!allowed.ok) {
          return allowed;
        }
        if (hooks.beforeDelete) {
          const before = await runHook("beforeDelete", () =>
            // SAFETY: the target holds this table's row, typed per table for callers.
            hooks.beforeDelete!(ctx, target as never),
          );
          if (!before.ok) {
            return before;
          }
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
      if (!parsed.ok) {
        return parsed;
      }
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
      if (!parsed.ok) {
        return parsed;
      }
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
      if (!parsed.ok) {
        return parsed;
      }
      query = parsed.data;
    }
    const row = id === undefined ? ok(undefined) : await rowFor(name, db, id);
    if (!row.ok) {
      return row;
    }
    const permitted = await permit(name, db, resourceOf(id, row.data ?? data));
    if (!permitted.ok) {
      return permitted;
    }
    const ctx = ctxOf(db, input);
    const allowed = await authorize(ctx, name, {
      id,
      data,
      query,
      ...(row.data === undefined ? {} : { row: row.data }),
    });
    if (!allowed.ok) {
      return allowed;
    }
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
        if (!body.ok) {
          return [body];
        }
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
    if (segments.length > 1 || !keyParam) {
      return [new Response(null, { status: 404 })];
    }
    const id = segments[0];
    if (request.method === "GET" && has("get")) {
      return [await execute(db, "get", { id, request })];
    }
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
