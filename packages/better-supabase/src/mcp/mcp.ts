import type {
  StandardJSONSchemaV1,
  StandardSchemaV1,
} from "@standard-schema/spec";

import {
  resourceMetadataResponse,
  unauthorizedResponse,
} from "@supabase/server/oauth-protected-resource";

import type { AnyAuthorizer, PermissionRef } from "../core/authorizer.ts";
import type { BetterSupabase } from "../core/define.ts";
import type { DbError } from "../core/errors.ts";
import type { OperationTable } from "../core/operations.ts";
import type { AnyFunctions, AnyModels, TableKey } from "../schema/types.ts";
import type {
  ResourceHandler,
  ResourceRouteOptions,
} from "../server/resource-types.ts";
import type { GuardOptions } from "../server/respond.ts";
import type {
  BetterServer,
  ServerContext,
  ServerOptions,
} from "../server/server-types.ts";
import type { ResourceOperation } from "../spec/model.ts";
import type { ToolSchemaTarget } from "./dialect.ts";
import type { Json, JsonRpcRequest } from "./json-rpc.ts";
import type { RequiredRoles } from "./permissions.ts";
import type {
  ServerDescription,
  ToolAnnotations,
  ToolInfo,
  ToolResult,
} from "./protocol.ts";

import { dbError } from "../core/errors.ts";
import { jsonResponse } from "../core/json.ts";
import {
  methodNotAllowed,
  problemResponse,
  toProblem,
} from "../core/problem.ts";
import { validate } from "../core/standard.ts";
import { boundedTtlCache } from "../core/ttl-cache.ts";
import { buildJsonSchema } from "../generators/json-schema.ts";
import { flushEvents } from "../server/adapter.ts";
import { withExtra } from "../server/extra.ts";
import { defineResource } from "../server/resource.ts";
import { defaultExpose, guard, settle } from "../server/respond.ts";
import { createServer, extendServer } from "../server/server.ts";
import { pageInputSchema, pageSchema } from "../spec/resource-schemas.ts";
import { schemaTargetFor, toolDialects } from "./dialect.ts";
import {
  discovery,
  endpointPreflight,
  isMetadataRequest,
  metadataPreflight,
  withCors,
} from "./http.ts";
import {
  HEADER_MISMATCH,
  INVALID_PARAMS,
  INVALID_REQUEST,
  META_CAPABILITIES,
  META_VERSION,
  METHOD_NOT_FOUND,
  PARSE_ERROR,
  UNSUPPORTED_PROTOCOL_VERSION,
  headerName,
  isObject,
  isRpcRequest,
  quoted,
  rpcError,
} from "./json-rpc.ts";
import {
  checkTool,
  contextOf,
  missingRole,
  permittedTools,
  toolPermission,
} from "./permissions.ts";
import {
  discoverResult,
  initializeResult,
  isModernMessage,
  LIST_TTL_MS,
  MCP_PROTOCOL_VERSION,
  modernResult,
  SUPPORTED_VERSIONS,
  textResult,
} from "./protocol.ts";

export { MCP_PROTOCOL_VERSION } from "./protocol.ts";

export type { ToolAnnotations, ToolInfo, ToolResult } from "./protocol.ts";

/** The host's hostname is in the list; a missing or malformed host is not. */
function hostAllowed(host: string | null, allowed: readonly string[]): boolean {
  if (!host) {
    return false;
  }

  try {
    return allowed.includes(new URL(`http://${host}`).hostname);
  } catch {
    return false;
  }
}

export interface ToolContext<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  B = unknown,
> extends ServerContext<M, F, E, C, P, B> {
  readonly request: Request;
  readonly signal: AbortSignal;
}

export interface McpTool<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  B = unknown,
> {
  readonly info: ToolInfo;
  /**
   * The input schema in another dialect, for clients on an older protocol
   * revision. Without it, `info.inputSchema` is rewritten.
   */
  readonly inputSchemaFor?: (target: ToolSchemaTarget) => Json | undefined;
  /** Validates arguments; its output is what `run` receives. */
  readonly input?: StandardSchemaV1;
  /** Opaque data for the `authorize` and `visible` hooks. Never sent to clients. */
  readonly meta?: unknown;
  /**
   * Checked by the authorizer on every call; callers it denies don't see the
   * tool.
   */
  readonly permission?: unknown;
  /** The provider operation the tool checks, in place of `mcp.tool.<name>`. */
  readonly operation?: string;
  run(args: never, ctx: ToolContext<M, F, E, C, P, B>): unknown;
}

/** What the `authorize` and `visible` hooks see of a tool. */
export interface ToolRef {
  readonly info: ToolInfo;
  /**
   * The tool's `meta`, e.g. a permission. For table tools, the resource's
   * `meta` for that operation.
   */
  readonly meta: unknown;
}

/** The outcome of `authorize`. `scopes` turns a refusal into an OAuth challenge. */
export type ToolDecision =
  | { readonly allowed: true }
  | {
      readonly allowed: false;
      readonly reason?: string;
      /** OAuth scopes the call needs, sent in an `insufficient_scope` challenge. */
      readonly scopes?: readonly string[];
    };

export interface ToolDefinition<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  I,
  C = unknown,
  P = unknown,
  Ref = unknown,
  B = unknown,
> {
  readonly name: string;
  readonly title?: string;
  readonly description: string;
  /**
   * Validator for the arguments. Its JSON Schema comes from Standard JSON
   * Schema (zod 4, arktype, valibot) unless `inputSchema` is given.
   */
  readonly input?: StandardSchemaV1<unknown, I>;
  readonly inputSchema?: Json;
  readonly outputSchema?: Json;
  /**
   * The dialect `input` converts to for `ToolInfo` and the `tools` list.
   * Defaults to `draft-2020-12`. `tools/list` converts again for clients on
   * 2025-06-18 and earlier, which get draft-07.
   */
  readonly jsonSchemaTarget?: ToolSchemaTarget;
  readonly annotations?: ToolAnnotations;
  /** Opaque data for the `authorize` and `visible` hooks. Never sent to clients. */
  readonly meta?: unknown;
  /**
   * Checked by the authorizer after the arguments are validated, with the tool
   * as the resource (`mcp_tool`). `tools/list` hides the tool from callers it
   * denies.
   */
  readonly permission?: Ref;
  /**
   * The provider operation whose permission the tool checks, in place of
   * `mcp.tool.<name>` (`invoices.void`).
   */
  readonly operation?: string;
  run(args: I, ctx: ToolContext<M, F, E, C, P, B>): unknown;
}

/**
 * A table's tools: the REST resource options, plus `meta` per operation for
 * `authorize` and `visible`.
 */
export type ToolResourceOptions<
  M extends AnyModels,
  T extends TableKey<M>,
  Ref = string,
> = ResourceRouteOptions<M, T, Ref> & {
  /**
   * Opaque data per operation, e.g. a permission, passed to `authorize` and
   * `visible` as the table tool's `meta`. Never sent to clients. An operation
   * without an entry gets `undefined`.
   */
  readonly meta?: { readonly [K in ResourceOperation]?: unknown };
};

export type ToolResources<M extends AnyModels, Ref = string> = {
  readonly [T in TableKey<M>]?: ToolResourceOptions<M, T, Ref> | true;
};

export interface McpOptions<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  Ref = string,
  B = unknown,
>
  extends ServerOptions, Omit<GuardOptions, "scopes"> {
  readonly name: string;
  readonly version: string;
  readonly title?: string;
  /** Sent to clients on `initialize`, e.g. how the tools fit together. */
  readonly instructions?: string;
  /**
   * Tables exposed as tools: `<table>_list`, `_get`, `_create`, `_update`,
   * `_delete`.
   */
  readonly resources?: ToolResources<M, Ref>;
  readonly tools?: readonly McpTool<M, F, E, C, P, B>[];
  /**
   * The authorization provider's operations (`authorization.operations` in the
   * config). A tool's `mcp.tool.<name>` entry replaces its `permission`, so the
   * provider decides what each tool needs.
   */
  readonly operations?: OperationTable;
  /**
   * Canonical URL of this MCP server (RFC 9728 `resource`). Defaults to the
   * request URL without query; on Supabase Edge Functions, to the public
   * `<origin>/functions/v1/<slug>` the gateway forwards.
   */
  readonly resource?: string | ((request: Request) => string);
  /**
   * Defaults to Supabase Auth of `env.url` (`<url>/auth/v1`); on Supabase Edge
   * Functions, to Auth on the public origin.
   */
  readonly authorizationServers?: readonly string[];
  /**
   * Scopes the tools need, published as RFC 9728 `scopes_supported` and in
   * `insufficient_scope` challenges. `offline_access` is left out: refresh
   * tokens are between the client and the authorization server.
   */
  readonly advertisedScopes?: readonly string[];
  /**
   * Scopes a delegated token (an OAuth client or an `act` chain) needs to call
   * the server at all. A missing one answers 403 `insufficient_scope`.
   */
  readonly requiredScopes?: readonly string[];
  /**
   * Roles a signed-in user needs to call the server at all, read from a claim
   * (`app_metadata.role` by default; a string or an array of strings). Users
   * without one get 403; service-role callers pass.
   *
   * ```ts
   * requiredRoles: { roles: ['admin', 'support'], claim: 'app_metadata.roles' }
   * ```
   */
  readonly requiredRoles?: RequiredRoles;
  /**
   * Read the session cookie. Defaults to false: MCP clients send bearer tokens,
   * and a cookie would let any page the user visits call the tools. Turn it on
   * only together with `allowedOrigins`.
   */
  readonly cookies?: boolean;
  /**
   * Origins allowed to call the server (DNS rebinding protection). Defaults to
   * any.
   */
  readonly allowedOrigins?: readonly string[];
  /**
   * Answers CORS preflights and adds `Access-Control-*` headers, so browser MCP
   * clients can call the server. The allowed origin is `allowedOrigins` when
   * set, any origin otherwise. Defaults to true.
   */
  readonly cors?: boolean;
  /**
   * Hostnames the `Host` header may name, without the port (DNS rebinding
   * protection). List the production, preview and local hosts. Defaults to
   * any.
   */
  readonly allowedHosts?: readonly string[];
  /**
   * A page that explains how to connect, published as RFC 9728
   * `resource_documentation`.
   */
  readonly resourceDocumentation?: string;
  /** Custom jsonb types, as in `createOpenApi`. */
  readonly json?: Readonly<Record<string, unknown>>;
  /**
   * Include internal error messages in tool results. Defaults to `NODE_ENV ===
   * 'development'`.
   */
  readonly exposeErrors?: boolean;
  /**
   * Keeps the invocation alive for event sink sends a tool started, e.g.
   * `EdgeRuntime.waitUntil` or Next's `after`.
   */
  readonly waitUntil?: (promise: Promise<unknown>) => void;
  /**
   * Decides each `tools/call` after the arguments are validated and before
   * `run`. `args` are the validated arguments (raw for table tools, which
   * validate in the repository). A refusal is a tool error; a refusal with
   * `scopes` is a 403 `insufficient_scope` challenge naming them.
   */
  readonly authorize?: (
    ctx: ToolContext<M, F, E, C, P, B>,
    tool: ToolRef,
    args: unknown,
  ) => ToolDecision | Promise<ToolDecision>;
  /**
   * Whether the caller sees a tool in `tools/list`. A hidden tool is called
   * like an unknown one. Lists are cached per token (`cacheScope: 'private'`).
   */
  readonly visible?: (
    ctx: ToolContext<M, F, E, C, P, B>,
    tool: ToolRef,
  ) => boolean | Promise<boolean>;
}

export interface BetterMcp<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  Ref = string,
  B = unknown,
> extends BetterServer<M, F, E, C, P, B> {
  /**
   * Everything in one handler: the MCP endpoint and
   * `/.well-known/oauth-protected-resource`.
   */
  readonly fetch: (request: Request) => Promise<Response>;
  /** The Streamable HTTP endpoint (POST JSON-RPC). */
  readonly endpoint: (request: Request) => Promise<Response>;
  /** RFC 9728 protected resource metadata. */
  metadata(request: Request): Response;
  readonly tools: readonly ToolInfo[];
  /** Adds a tool typed against this app's repositories. */
  tool<I = Record<string, unknown>>(
    definition: ToolDefinition<M, F, E, I, C, P, Ref, B>,
  ): this;
  /** Calls a tool directly, e.g. from tests or another transport. */
  call(
    name: string,
    args: unknown,
    ctx: ToolContext<M, F, E, C, P, B>,
  ): Promise<ToolResult>;
}

/** A custom tool. Pass it in `createMcp({ tools: [...] })`. */
export function defineTool<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  I = Record<string, unknown>,
  C = unknown,
  P = unknown,
  Ref = unknown,
  B = unknown,
>(
  definition: ToolDefinition<M, F, E, I, C, P, Ref, B>,
): McpTool<M, F, E, C, P, B> {
  if (!/^[A-Za-z0-9_.-]{1,64}$/.test(definition.name)) {
    throw new TypeError(
      `Invalid tool name "${definition.name}": use 1-64 letters, digits, "_", "-" or "."`,
    );
  }

  // SAFETY: a Standard Schema input carries ~standard, and every JSON Schema
  // field on it is optional.
  const standard = definition.input?.["~standard"] as
    | Partial<StandardJSONSchemaV1.Props>
    | undefined;

  const convert =
    definition.inputSchema === undefined ? standard?.jsonSchema : undefined;

  const inputSchema =
    definition.inputSchema ??
    convert?.input({
      target: definition.jsonSchemaTarget ?? "draft-2020-12",
    }) ??
    (definition.input ? undefined : { type: "object", properties: {} });

  if (!inputSchema) {
    throw new TypeError(
      `Tool "${definition.name}": the input schema has no JSON Schema; pass inputSchema`,
    );
  }

  const { $schema: _, ...schema } = inputSchema;

  return {
    ...(convert
      ? {
          inputSchemaFor: (target: ToolSchemaTarget) => {
            try {
              const { $schema: _dialect, ...converted } = convert.input({
                target,
              });

              return converted;
            } catch {
              // A library may not convert to every target; the caller then
              // rewrites the default schema instead.
              return;
            }
          },
        }
      : {}),
    info: {
      name: definition.name,
      ...(definition.title ? { title: definition.title } : {}),
      description: definition.description,
      inputSchema: schema,
      ...(definition.outputSchema
        ? { outputSchema: definition.outputSchema }
        : {}),
      ...(definition.annotations
        ? { annotations: definition.annotations }
        : {}),
    },
    ...(definition.input ? { input: definition.input } : {}),
    ...(definition.meta === undefined ? {} : { meta: definition.meta }),
    ...(definition.permission === undefined
      ? {}
      : { permission: definition.permission }),
    ...(definition.operation === undefined
      ? {}
      : { operation: definition.operation }),
    run: (args: never, ctx) => definition.run(args, ctx),
  };
}

const ANNOTATIONS: { readonly [K in ResourceOperation]: ToolAnnotations } = {
  list: { readOnlyHint: true, openWorldHint: false },
  get: { readOnlyHint: true, openWorldHint: false },
  create: { readOnlyHint: false, destructiveHint: false, openWorldHint: false },
  update: {
    readOnlyHint: false,
    destructiveHint: true,
    idempotentHint: true,
    openWorldHint: false,
  },
  delete: {
    readOnlyHint: false,
    destructiveHint: true,
    idempotentHint: true,
    openWorldHint: false,
  },
};

function tableTools(
  resource: ResourceHandler<unknown>,
  defs: Readonly<Record<string, Json>>,
): { info: ToolInfo; operation: ResourceOperation }[] {
  const { table, keyParam } = resource;
  const row = defs[`${table}Row`] ?? { type: "object" };

  // SAFETY: buildJsonSchema writes row schemas with a properties object of JSON Schemas.
  const key: Json | undefined = keyParam
    ? ((row["properties"] as Record<string, Json> | undefined)?.[keyParam] ?? {
        type: "string",
      })
    : undefined;

  const keyInput = (more: Json = {}): Json => ({
    type: "object",
    properties: { [keyParam!]: key, ...more },
    required: [keyParam!, ...Object.keys(more)],
    additionalProperties: false,
  });

  const cursor = resource.pagination === "cursor";
  const page: Json = pageSchema(row, cursor);
  const tools: { info: ToolInfo; operation: ResourceOperation }[] = [];

  const add = (
    operation: ResourceOperation,
    description: string,
    inputSchema: Json,
    outputSchema?: Json,
  ): void => {
    tools.push({
      operation,
      info: {
        name: `${table}_${operation}`,
        title: `${operation[0]!.toUpperCase()}${operation.slice(1)} ${table}`,
        description,
        inputSchema,
        ...(outputSchema ? { outputSchema } : {}),
        annotations: ANNOTATIONS[operation],
      },
    });
  };

  for (const operation of resource.operations) {
    switch (operation) {
      case "list": {
        // SAFETY: list schemas are JSON Schema objects.
        const { $schema: _, ...listSchema } = (resource.list?.jsonSchema ??
          pageInputSchema(cursor, resource.maxPageSize)) as Record<
          string,
          unknown
        >;

        add(
          "list",
          `List ${table} rows visible to the caller, one page at a time.`,
          listSchema,
          page,
        );
        break;
      }

      case "get": {
        if (keyParam) {
          add("get", `Get one ${table} row by ${keyParam}.`, keyInput(), row);
        }

        break;
      }

      case "create": {
        add(
          "create",
          `Create a ${table} row. Returns the created row.`,
          defs[`${table}Insert`] ?? { type: "object" },
          row,
        );
        break;
      }

      case "update": {
        if (keyParam) {
          add(
            "update",
            `Update the columns in "patch" on one ${table} row.`,
            keyInput({ patch: defs[`${table}Update`] ?? { type: "object" } }),
            row,
          );
        }

        break;
      }

      case "delete": {
        if (keyParam) {
          add("delete", `Delete one ${table} row by ${keyParam}.`, keyInput());
        }

        break;
      }

      default: {
        const unknown: never = operation;
        throw new TypeError(`Unknown operation ${String(unknown)}`);
      }
    }
  }

  return tools;
}

/** Callers whose visible tool lists are kept; the oldest goes first. */
const VISIBLE_LISTS_MAX = 1000;

/**
 * An MCP server (Streamable HTTP, stateless) whose tools run as the caller: the
 * Bearer token from the MCP client is verified and every query goes through
 * RLS. Answers 401 with RFC 9728 metadata so clients can sign in with Supabase
 * Auth's OAuth server.
 */
export function createMcp<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
  A extends AnyAuthorizer | undefined = undefined,
  B = unknown,
>(
  betterSupabase: BetterSupabase<M, D, F, E, C, P, B>,
  options: McpOptions<M, F, E, C, P, PermissionRef<A>, B> & {
    readonly authorizer?: A;
  },
): BetterMcp<M, F, E, C, P, PermissionRef<A>, B> {
  const server = createServer(betterSupabase, options);
  const expose = options.exposeErrors ?? defaultExpose();

  // SAFETY: buildJsonSchema always writes a $defs map of JSON Schemas.
  const defs = buildJsonSchema({
    meta: betterSupabase.meta,
    config: { json: options.json ?? {} },
  })["$defs"] as Record<string, Json>;

  /** A call `authorize` refused; `scopes` is empty for a plain tool error. */
  interface Refusal {
    readonly refusal: string;
    readonly scopes: readonly string[];
  }

  type Invocation = ToolResult | Refusal;

  interface Entry extends ToolRef {
    readonly permission?: unknown;
    /**
     * The listed tool with its schemas in `target`'s dialect, built once per
     * target.
     */
    infoFor(target: ToolSchemaTarget): ToolInfo;
    call(
      args: unknown,
      ctx: ToolContext<M, F, E, C, P, B>,
    ): Promise<Invocation>;
  }

  const registry = new Map<string, Entry>();
  let allTools: ToolInfo[] | undefined;
  const listed = new Map<ToolSchemaTarget, ToolInfo[]>();
  /** Bumped on every registration, so cached visible lists built before it miss. */
  let generation = 0;

  const register = (entry: Entry): void => {
    if (registry.has(entry.info.name)) {
      throw new TypeError(`Duplicate MCP tool "${entry.info.name}"`);
    }

    registry.set(entry.info.name, entry);
    allTools = undefined;
    listed.clear();
    generation += 1;
  };

  const failure = (error: DbError): ToolResult =>
    textResult(toProblem(error, { expose }), true);

  const refused = async (
    tool: ToolRef,
    args: unknown,
    ctx: ToolContext<M, F, E, C, P, B>,
  ): Promise<Refusal | undefined> => {
    if (!options.authorize) {
      return undefined;
    }

    const decision = await options.authorize(ctx, tool, args);

    if (decision.allowed) {
      return undefined;
    }

    return {
      refusal: decision.reason ?? `Not allowed to call ${tool.info.name}`,
      scopes: decision.scopes ?? [],
    };
  };

  const isVisible = async (
    tool: ToolRef,
    ctx: ToolContext<M, F, E, C, P, B>,
  ): Promise<boolean> => !options.visible || options.visible(ctx, tool);

  for (const [table, raw] of Object.entries(options.resources ?? {})) {
    if (!raw) {
      continue;
    }

    // SAFETY: options.resources is keyed by table names of M, and
    // Object.entries widens the keys and values.
    const key = table as TableKey<M>;
    // SAFETY: as above, `raw` is the options entry for `key`.
    const entry = raw as ToolResourceOptions<M, TableKey<M>> | true;
    const { meta, ...route } = entry === true ? {} : entry;

    const resource = defineResource(
      betterSupabase,
      key,
      route,
      options.authorizer,
    );

    for (const { info, operation } of tableTools(resource, defs)) {
      const ref: ToolRef = { info, meta: meta?.[operation] };
      register({
        ...ref,
        infoFor: toolDialects(info),
        async call(args, ctx) {
          // SAFETY: resource tools declare an object input schema, and the
          // arguments default to an empty object.
          const input = (args ?? {}) as Record<string, unknown>;
          const refusal = await refused(ref, input, ctx);

          if (refusal) {
            return refusal;
          }

          const id = resource.keyParam ? input[resource.keyParam] : undefined;

          const result = await resource.execute(ctx.db, operation, {
            id,
            query: input,
            data: operation === "update" ? input["patch"] : input,
          });

          if (!result.ok) {
            return failure(result.error);
          }

          return textResult(
            operation === "delete" ? { deleted: true } : result.data,
          );
        },
      });
    }
  }

  const addTool = (declared: McpTool<M, F, E, C, P, B>): void => {
    const permission = toolPermission(
      options.operations,
      declared.info.name,
      declared.permission,
      declared.operation,
    );

    const tool = { ...declared, permission };
    const ref: ToolRef = { info: tool.info, meta: tool.meta };
    register({
      ...ref,
      ...(permission === undefined ? {} : { permission }),
      infoFor: toolDialects(tool.info, tool.inputSchemaFor),
      async call(args, ctx) {
        let value: unknown = args ?? {};

        if (tool.input) {
          const parsed = await validate(tool.input, value, "arguments");

          if (!parsed.ok) {
            return failure(parsed.error);
          }

          value = parsed.data;
        }

        const checked = await checkTool(
          options.authorizer,
          tool,
          value,
          ctx.db,
        );

        if (!checked.ok) {
          return failure(checked.error);
        }

        const refusal = await refused(ref, value, ctx);

        if (refusal) {
          return refusal;
        }

        // SAFETY: value passed the tool's input schema above, so it has the
        // tool's input type.
        const outcome = await settle(() => tool.run(value as never, ctx));

        return outcome.ok ? textResult(outcome.data) : failure(outcome.error);
      },
    });
  };

  for (const tool of options.tools ?? []) {
    addTool(tool);
  }

  const listTools = (): ToolInfo[] =>
    (allTools ??= [...registry.values()].map((entry) => entry.info));

  const listFor = (target: ToolSchemaTarget): ToolInfo[] => {
    let tools = listed.get(target);

    if (!tools) {
      tools = [...registry.values()].map((entry) => entry.infoFor(target));
      listed.set(target, tools);
    }

    return tools;
  };

  /**
   * A user's visible list per token, for as long as clients may cache it
   * (`ttlMs`). `tools/call` still checks `visible` on every call.
   */
  const visibleLists = boundedTtlCache<
    string,
    { readonly entries: Entry[]; readonly generation: number }
  >({ max: VISIBLE_LISTS_MAX });

  let warned = false;

  /**
   * A tool with a permission and no authorizer to check it is never listed,
   * which is easy to miss.
   */
  const warnHidden = (all: readonly Entry[]): void => {
    if (warned || options.authorizer) {
      return;
    }

    const hidden = all
      .filter((entry) => entry.permission !== undefined)
      .map((entry) => entry.info.name);

    if (hidden.length > 0) {
      warned = true;
      console.warn(
        `createMcp: ${hidden.join(", ")} ${hidden.length === 1 ? "has" : "have"} a permission but no authorizer is set, so tools/list hides ${hidden.length === 1 ? "it" : "them"}. Pass authorizer to createMcp, or drop the permission.`,
      );
    }
  };

  /**
   * Without a `visible` hook or permissions every caller sees the same list,
   * built once.
   */
  const visibleTools = async (
    context: () => ToolContext<M, F, E, C, P, B>,
    target: ToolSchemaTarget,
  ): Promise<ToolInfo[]> => {
    const all = [...registry.values()];
    const gated = all.some((entry) => entry.permission !== undefined);

    if (!options.visible && !gated) {
      return listFor(target);
    }

    warnHidden(all);

    const ctx = context();
    const token = ctx.auth.kind === "user" ? ctx.auth.token : undefined;
    const cached = token === undefined ? undefined : visibleLists.get(token);

    if (cached?.generation === generation) {
      return cached.entries.map((entry) => entry.infoFor(target));
    }

    const [shown, permitted] = await Promise.all([
      Promise.all(all.map((entry) => isVisible(entry, ctx))),
      permittedTools(
        options.authorizer,
        all.map((entry) => ({ name: entry.info.name, ...entry })),
        contextOf(ctx.db),
      ),
    ]);

    const entries = all.filter((_, index) => shown[index] && permitted[index]);

    if (token !== undefined) {
      visibleLists.set(
        token,
        { entries, generation },
        Date.now() + LIST_TTL_MS,
      );
    }

    return entries.map((entry) => entry.infoFor(target));
  };

  const urls = discovery(options, () => server.env.url);
  const { metadataUrl } = urls;

  const invoke = async (
    name: string,
    args: unknown,
    ctx: ToolContext<M, F, E, C, P, B>,
    checkVisible = true,
  ): Promise<Invocation> => {
    const entry = registry.get(name);

    try {
      if (!entry || (checkVisible && !(await isVisible(entry, ctx)))) {
        return failure(dbError("not_found", `Unknown tool "${name}"`));
      }

      return await entry.call(args, ctx);
    } catch (cause) {
      return failure(
        dbError(
          "unexpected",
          expose && cause instanceof Error ? cause.message : "The tool failed",
        ),
      );
    }
  };

  const isRefusal = (value: Invocation): value is Refusal => "refusal" in value;

  const call: BetterMcp<M, F, E, C, P, PermissionRef<A>, B>["call"] = async (
    name,
    args,
    ctx,
  ) => {
    const outcome = await invoke(name, args, ctx);

    return isRefusal(outcome)
      ? failure(dbError("forbidden", outcome.refusal))
      : outcome;
  };

  const scopes = (options.advertisedScopes ?? []).filter(
    (scope) => scope !== "offline_access",
  );

  const description: ServerDescription = {
    info: {
      name: options.name,
      version: options.version,
      ...(options.title ? { title: options.title } : {}),
    },
    ...(options.instructions ? { instructions: options.instructions } : {}),
  };

  const unauthorized = (request: Request): Response => {
    const response = unauthorizedResponse(request, {
      resourceMetadataUrl: metadataUrl(request),
    });

    if (scopes.length > 0) {
      response.headers.set(
        "www-authenticate",
        `${response.headers.get("www-authenticate") ?? "Bearer"}, scope=${quoted(scopes.join(" "))}`,
      );
    }

    return response;
  };

  const forbidden = (
    request: Request,
    message: string,
    needed: readonly string[] = [],
    id: JsonRpcRequest["id"] = null,
  ): Response => {
    const all = [...new Set([...scopes, ...needed])];

    const challenge = [
      'Bearer error="insufficient_scope"',
      `error_description=${quoted(message)}`,
      ...(all.length > 0 ? [`scope=${quoted(all.join(" "))}`] : []),
      `resource_metadata=${quoted(metadataUrl(request))}`,
    ].join(", ");

    const response = rpcError(id, INVALID_REQUEST, message, 403);
    response.headers.set("www-authenticate", challenge);

    return response;
  };

  /**
   * A missing second factor is no scope problem, and an outage is not the
   * caller's fault.
   */
  const refuse = (request: Request, denied: DbError): Response => {
    if (denied.kind === "unauthorized") {
      return unauthorized(request);
    }

    if (denied.kind !== "forbidden") {
      return problemResponse(denied, { expose });
    }

    return denied.code === "INSUFFICIENT_AAL"
      ? rpcError(null, INVALID_REQUEST, denied.message, 403)
      : forbidden(request, denied.message, denied.scopes);
  };

  const unsupportedVersion = (
    id: JsonRpcRequest["id"],
    requested: unknown,
  ): Response =>
    rpcError(
      id,
      UNSUPPORTED_PROTOCOL_VERSION,
      "Unsupported protocol version",
      400,
      { supported: [...SUPPORTED_VERSIONS], requested },
    );

  /**
   * 2026-07-28 requests carry their version and capabilities, mirrored in
   * headers.
   */
  const checkModern = (
    message: JsonRpcRequest,
    header: string | null,
    headers: Headers,
  ): Response | undefined => {
    const meta = message.params?.["_meta"];
    const version = isObject(meta) ? meta[META_VERSION] : undefined;

    if (
      !isObject(meta) ||
      typeof version !== "string" ||
      !isObject(meta[META_CAPABILITIES])
    ) {
      return rpcError(
        message.id,
        INVALID_PARAMS,
        `Requests need _meta["${META_VERSION}"] and _meta["${META_CAPABILITIES}"]`,
        400,
      );
    }

    if (version !== MCP_PROTOCOL_VERSION) {
      return unsupportedVersion(message.id, version);
    }

    const mismatch = (detail: string): Response =>
      rpcError(message.id, HEADER_MISMATCH, `Header mismatch: ${detail}`, 400);

    if (header !== version) {
      return mismatch(`MCP-Protocol-Version must be ${version}`);
    }

    if (headers.get("mcp-method") !== message.method) {
      return mismatch(`Mcp-Method must be ${message.method}`);
    }

    const name = message.params?.["name"];

    if (message.method === "tools/call" && typeof name === "string") {
      const sent = headers.get("mcp-name");

      if (sent === null || headerName(sent) !== name) {
        return mismatch(`Mcp-Name must be ${name}`);
      }
    }

    return undefined;
  };

  const cors = options.cors ?? true;

  const endpoint = async (request: Request): Promise<Response> => {
    const response = await answer(request);
    flushEvents(server, options.waitUntil);

    return cors
      ? withCors(response, request, options.allowedOrigins)
      : response;
  };

  const answer = async (request: Request): Promise<Response> => {
    const origin = request.headers.get("origin");

    if (
      origin &&
      options.allowedOrigins &&
      !options.allowedOrigins.includes(origin)
    ) {
      return rpcError(null, INVALID_REQUEST, "Origin not allowed", 403);
    }

    if (
      options.allowedHosts &&
      !hostAllowed(urls.host(request), options.allowedHosts)
    ) {
      return rpcError(null, INVALID_REQUEST, "Host not allowed", 403);
    }

    if (request.method === "OPTIONS" && cors) {
      return endpointPreflight(request, options.allowedOrigins);
    }

    if (request.method !== "POST") {
      return methodNotAllowed(cors ? ["POST", "OPTIONS"] : ["POST"]);
    }

    const header = request.headers.get("mcp-protocol-version");

    if (header && !SUPPORTED_VERSIONS.includes(header)) {
      return unsupportedVersion(null, header);
    }

    const ctx = await server.context(request, {
      cookies: options.cookies ?? false,
    });

    const denied = guard(
      ctx.auth,
      options.allow,
      options.aal,
      options.requiredScopes,
    );

    if (denied) {
      return refuse(request, denied);
    }

    const roleDenied = missingRole(ctx.auth, options.requiredRoles);

    if (roleDenied) {
      return refuse(request, roleDenied);
    }

    let message: unknown;

    try {
      message = await request.json();
    } catch {
      return rpcError(null, PARSE_ERROR, "Parse error", 400);
    }

    if (!isRpcRequest(message)) {
      return rpcError(
        null,
        INVALID_REQUEST,
        "Expected one JSON-RPC 2.0 message",
        400,
      );
    }

    const modern = isModernMessage(message) || header === MCP_PROTOCOL_VERSION;

    if (modern) {
      const invalid = checkModern(message, header, request.headers);

      if (invalid) {
        return invalid;
      }
    }

    if (message.id === undefined) {
      return new Response(null, { status: 202 });
    }

    const toolContext = (): ToolContext<M, F, E, C, P, B> =>
      withExtra(ctx, { request, signal: request.signal });

    const reply = (result: object): Response =>
      jsonResponse({
        jsonrpc: "2.0",
        id: message.id,
        result: modern ? modernResult(result, description) : result,
      });

    const notFound = (): Response =>
      rpcError(
        message.id,
        METHOD_NOT_FOUND,
        `Method not found: ${message.method}`,
        modern ? 404 : 200,
      );

    switch (message.method) {
      case "server/discover": {
        return reply(discoverResult(description));
      }

      case "initialize": {
        return modern
          ? notFound()
          : reply(
              initializeResult(
                message.params?.["protocolVersion"],
                description,
              ),
            );
      }

      case "ping": {
        return modern ? notFound() : reply({});
      }

      case "tools/list": {
        return reply({
          // A request without the header is on 2025-03-26, the revision
          // before the header existed.
          tools: await visibleTools(
            toolContext,
            schemaTargetFor(
              modern ? MCP_PROTOCOL_VERSION : (header ?? "2025-03-26"),
            ),
          ),
          ...(modern ? { ttlMs: LIST_TTL_MS, cacheScope: "private" } : {}),
        });
      }

      case "tools/call": {
        const name = message.params?.["name"];
        const entry = typeof name === "string" ? registry.get(name) : undefined;
        const context = toolContext();

        if (!entry || !(await isVisible(entry, context))) {
          return rpcError(
            message.id,
            INVALID_PARAMS,
            `Unknown tool ${JSON.stringify(name)}`,
          );
        }

        const outcome = await invoke(
          entry.info.name,
          message.params?.["arguments"],
          context,
          false,
        );

        if (!isRefusal(outcome)) {
          return reply(outcome);
        }

        if (outcome.scopes.length > 0) {
          return forbidden(
            request,
            outcome.refusal,
            outcome.scopes,
            message.id,
          );
        }

        return reply(failure(dbError("forbidden", outcome.refusal)));
      }

      default: {
        return notFound();
      }
    }
  };

  const metadata = (request: Request): Response => {
    const resource = urls.resource(request);
    const authorizationServers = [...urls.authorizationServers(request)];

    if (scopes.length === 0 && options.resourceDocumentation === undefined) {
      return resourceMetadataResponse(request, {
        resource,
        authorizationServers,
      });
    }

    // The upstream document has no `scopes_supported` or
    // `resource_documentation`, and merging into its body would make this
    // synchronous method async.
    return Response.json(
      {
        resource,
        authorization_servers: authorizationServers,
        bearer_methods_supported: ["header"],
        ...(scopes.length > 0 ? { scopes_supported: scopes } : {}),
        ...(options.resourceDocumentation === undefined
          ? {}
          : { resource_documentation: options.resourceDocumentation }),
      },
      { headers: { "access-control-allow-origin": "*" } },
    );
  };

  type Mcp = BetterMcp<M, F, E, C, P, PermissionRef<A>, B>;

  const mcp: Mcp = extendServer<Mcp>(server, {
    get tools() {
      return [...listTools()];
    },
    tool(definition) {
      addTool(defineTool(definition));

      return mcp;
    },
    call,
    endpoint,
    metadata,
    fetch(request) {
      if (isMetadataRequest(request)) {
        return Promise.resolve(
          request.method === "OPTIONS"
            ? metadataPreflight()
            : metadata(request),
        );
      }

      return endpoint(request);
    },
  });

  return mcp;
}
