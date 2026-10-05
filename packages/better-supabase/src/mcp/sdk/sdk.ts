import type {
  AuthInfo,
  CallToolResult,
  Icon,
  InputRequiredResult,
  OAuthTokenVerifier,
  RegisteredTool,
  ScopeChallengeHandler,
  ServerContext as McpContext,
  StandardSchemaWithJSON,
  ToolAnnotations,
} from "@modelcontextprotocol/server";

import {
  bearerAuthChallengeResponse,
  OAuthError,
  verifyBearerToken,
} from "@modelcontextprotocol/server";
import { fromSupabaseUrl } from "@supabase/server/oauth-protected-resource";

import type { AuthState } from "../../auth/resolve.ts";
import type { BetterSupabase } from "../../core/define.ts";
import type { AnyFunctions, AnyModels } from "../../schema/types.ts";
import type {
  BetterServer,
  ServerContext,
  ServerOptions,
} from "../../server/server.ts";

import { delegationOf } from "../../auth/actor.ts";
import { guard, type GuardOptions } from "../../server/respond.ts";
import { createServer, extendServer, withExtra } from "../../server/server.ts";

const WELL_KNOWN = "/.well-known/oauth-protected-resource";
const STATE_KEY = "betterSupabase";
/** Auth states this module verified; `AuthInfo.extra` from anywhere else is ignored. */
const verified = new WeakSet<object>();

type UserAuth<C, P> = Extract<AuthState<C, P>, { kind: "user" }>;

export interface McpAuthOptions
  extends ServerOptions, Omit<GuardOptions, "scopes"> {
  /**
   * The MCP endpoint's public URL, the RFC 9728 `resource`. Defaults to the
   * request URL without a trailing slash; pass it when a proxy rewrites the
   * host or path.
   */
  readonly resource?: string | ((request: Request) => string);
  /** Defaults to the project's Supabase Auth issuer. */
  readonly authorizationServers?: readonly string[];
  /** Scopes published as `scopes_supported`; `offline_access` is never listed. */
  readonly advertisedScopes?: readonly string[];
  /**
   * Scopes a delegated token (an OAuth client) needs; one without them gets a
   * 403 `insufficient_scope` challenge. The user's own session is not limited.
   */
  readonly requiredScopes?: readonly string[];
  /** Published as `resource_documentation`. */
  readonly resourceDocumentation?: string;
}

/** A fetch handler that takes verified auth, like the SDK's `createMcpHandler(...)`. */
export interface McpFetchHandler {
  fetch(
    request: Request,
    options?: { readonly authInfo?: AuthInfo },
  ): Promise<Response>;
}

export interface BetterMcpAuth<
  M extends AnyModels = AnyModels,
  F extends AnyFunctions = AnyFunctions,
  E = unknown,
  C = unknown,
  P = unknown,
> extends BetterServer<M, F, E, C, P> {
  /** An `OAuthTokenVerifier` for the SDK's bearer helpers; it verifies the token locally. */
  readonly verifier: OAuthTokenVerifier;
  /** The RFC 9728 Protected Resource Metadata document. */
  metadata(request: Request): Response;
  /** Where the metadata is served, for `WWW-Authenticate` challenges. */
  metadataUrl(request: Request): string;
  /**
   * A fetch handler that serves the metadata, refuses callers without a
   * valid bearer token (401 or 403 with an RFC 9728 challenge), then calls
   * `handler.fetch(request, { authInfo })`.
   */
  serve(handler: McpFetchHandler): (request: Request) => Promise<Response>;
  /** The caller's context for a tool call, from `ctx.http.authInfo`. */
  contextOf(ctx: McpContext): Promise<ServerContext<M, F, E, C, P>>;
}

/** What `withBetterSupabase` adds to the SDK's tool context. */
export interface BetterToolExtra<
  M extends AnyModels = AnyModels,
  F extends AnyFunctions = AnyFunctions,
  E = unknown,
  C = unknown,
  P = unknown,
> {
  /** Repositories bound to the verified caller, with RLS. */
  readonly db: ServerContext<M, F, E, C, P>["db"];
  readonly auth: AuthState<C, P>;
  /** The full server context: `db`, `auth`, `supabase` and the rest. */
  readonly bs: ServerContext<M, F, E, C, P>;
}

export type BetterToolContext<
  M extends AnyModels = AnyModels,
  F extends AnyFunctions = AnyFunctions,
  E = unknown,
  C = unknown,
  P = unknown,
> = McpContext & BetterToolExtra<M, F, E, C, P>;

export interface BetterToolConfig<
  InputArgs extends StandardSchemaWithJSON | undefined,
  OutputArgs extends StandardSchemaWithJSON | undefined,
> {
  readonly title?: string;
  readonly description?: string;
  readonly inputSchema?: InputArgs;
  readonly outputSchema?: OutputArgs;
  readonly annotations?: ToolAnnotations;
  readonly icons?: Icon[];
  readonly scopeChallenge?: ScopeChallengeHandler;
  readonly _meta?: Record<string, unknown>;
  /** Extra keys for wrappers registered in between, like permdock's `permission`. */
  readonly [key: string]: unknown;
}

type ToolReturn =
  | CallToolResult
  | InputRequiredResult
  | Promise<CallToolResult | InputRequiredResult>;

export type BetterToolCallback<
  InputArgs extends StandardSchemaWithJSON | undefined,
  Ctx,
> = InputArgs extends StandardSchemaWithJSON
  ? (
      args: StandardSchemaWithJSON.InferOutput<InputArgs>,
      ctx: Ctx,
    ) => ToolReturn
  : (ctx: Ctx) => ToolReturn;

/** An SDK server whose tool callbacks also get `db`, `auth` and `bs`. */
export type BetterMcpServer<
  S,
  M extends AnyModels = AnyModels,
  F extends AnyFunctions = AnyFunctions,
  E = unknown,
  C = unknown,
  P = unknown,
> = Omit<S, "registerTool"> & {
  registerTool<
    OutputArgs extends StandardSchemaWithJSON | undefined = undefined,
    InputArgs extends StandardSchemaWithJSON | undefined = undefined,
  >(
    name: string,
    config: BetterToolConfig<InputArgs, OutputArgs>,
    cb: BetterToolCallback<InputArgs, BetterToolContext<M, F, E, C, P>>,
  ): RegisteredTool;
};

/** The structural part of `McpServer` (or a wrapper of it) that `withBetterSupabase` needs. */
export interface ToolRegistrar {
  registerTool(
    name: string,
    config: never,
    cb: (...params: never[]) => unknown,
  ): unknown;
}

function claimString(
  claims: Readonly<Record<string, unknown>>,
  key: string,
): string | undefined {
  const value = claims[key];
  return typeof value === "string" ? value : undefined;
}

function isUserState<C, P>(value: unknown): value is UserAuth<C, P> {
  return (
    typeof value === "object" &&
    value !== null &&
    verified.has(value) &&
    "kind" in value &&
    value.kind === "user"
  );
}

/**
 * Bearer auth for an MCP server built on the official SDK
 * (`@modelcontextprotocol/server` 2.3 or later). Verifies Supabase access
 * tokens locally, serves the RFC 9728 metadata, and binds repositories to
 * the caller. Pair it with `withBetterSupabase` and `createMcpHandler`.
 */
export function createMcpAuth<
  M extends AnyModels,
  D,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
>(
  betterSupabase: BetterSupabase<M, D, F, E, C, P>,
  options: McpAuthOptions = {},
): BetterMcpAuth<M, F, E, C, P> {
  const server = createServer(betterSupabase, options);
  const allow = options.allow ?? ["user"];
  const scopes = options.requiredScopes ?? [];
  const advertised = (options.advertisedScopes ?? []).filter(
    (scope) => scope !== "offline_access",
  );

  const resourceOf = (request: Request): string => {
    if (typeof options.resource === "function")
      return options.resource(request);
    if (options.resource) return options.resource;
    const url = new URL(request.url);
    return url.pathname.startsWith(WELL_KNOWN)
      ? `${url.origin}${url.pathname.slice(WELL_KNOWN.length)}`
      : `${url.origin}${url.pathname}`.replace(/\/$/, "");
  };
  const metadataUrl = (request: Request): string => {
    const resource = new URL(resourceOf(request));
    return `${resource.origin}${WELL_KNOWN}${resource.pathname.replace(/\/$/, "")}`;
  };
  const metadata = (request: Request): Response =>
    Response.json(
      {
        resource: resourceOf(request),
        authorization_servers: [
          ...(options.authorizationServers ?? [
            fromSupabaseUrl(server.env.url),
          ]),
        ],
        bearer_methods_supported: ["header"],
        ...(advertised.length > 0 ? { scopes_supported: advertised } : {}),
        ...(options.resourceDocumentation === undefined
          ? {}
          : { resource_documentation: options.resourceDocumentation }),
      },
      { headers: { "access-control-allow-origin": "*" } },
    );

  const verifier: OAuthTokenVerifier = {
    async verifyAccessToken(token) {
      const { auth } = await server.resolve(
        new Request("https://mcp.invalid/", {
          headers: { authorization: `Bearer ${token}` },
        }),
        { cookies: false },
      );
      if (auth.kind !== "user") {
        throw new OAuthError("invalid_token", "The access token is not valid");
      }
      const denied = guard(auth, allow, options.aal, scopes);
      if (denied) {
        throw new OAuthError(
          denied.kind === "unauthorized"
            ? "invalid_token"
            : "insufficient_scope",
          denied.message,
        );
      }
      verified.add(auth);
      const exp = auth.claims.exp;
      return {
        token,
        clientId:
          claimString(auth.claims, "client_id") ??
          claimString(auth.claims, "azp") ??
          "",
        scopes: [...(delegationOf(auth.claims)?.scopes ?? [])],
        ...(auth.expiresAt === null
          ? typeof exp === "number"
            ? { expiresAt: exp }
            : {}
          : { expiresAt: auth.expiresAt }),
        extra: { [STATE_KEY]: auth },
      };
    },
  };

  const anon: AuthState<C, P> = { kind: "anon", reason: "none" };

  const contextOf = async (
    ctx: McpContext,
  ): Promise<ServerContext<M, F, E, C, P>> => {
    const info = ctx.http?.authInfo;
    const state = info?.extra?.[STATE_KEY];
    if (isUserState<C, P>(state)) return server.contextFor(state);
    if (info?.token) {
      const { auth } = await server.resolve(
        new Request("https://mcp.invalid/", {
          headers: { authorization: `Bearer ${info.token}` },
        }),
        { cookies: false },
      );
      return server.contextFor(auth.kind === "user" ? auth : anon);
    }
    return server.contextFor(anon);
  };

  const serve =
    (handler: McpFetchHandler) =>
    async (request: Request): Promise<Response> => {
      const path = new URL(request.url).pathname;
      if (path === WELL_KNOWN || path.startsWith(`${WELL_KNOWN}/`)) {
        if (request.method === "OPTIONS") {
          return new Response(null, {
            status: 204,
            headers: {
              "access-control-allow-origin": "*",
              "access-control-allow-methods": "GET, OPTIONS",
            },
          });
        }
        return metadata(request);
      }
      const header = request.headers.get("authorization");
      if (!header && allow.includes("anon")) return handler.fetch(request);
      const resourceMetadataUrl = metadataUrl(request);
      try {
        const authInfo = await verifyBearerToken(header, {
          verifier,
          resourceMetadataUrl,
        });
        return await handler.fetch(request, { authInfo });
      } catch (error) {
        if (!(error instanceof OAuthError)) throw error;
        return bearerAuthChallengeResponse(error, {
          resourceMetadataUrl,
          ...(scopes.length > 0 || advertised.length > 0
            ? { requiredScopes: [...new Set([...advertised, ...scopes])] }
            : {}),
        });
      }
    };

  return extendServer<BetterMcpAuth<M, F, E, C, P>>(server, {
    verifier,
    metadata,
    metadataUrl,
    serve,
    contextOf,
  });
}

/**
 * Wraps `server.registerTool` so every tool callback gets `db`, `auth` and
 * `bs` for the caller on its context. Wrap after permdock's `protectServer`
 * so permissions are checked before the context is built.
 */
export function withBetterSupabase<
  S extends ToolRegistrar,
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C,
  P,
>(
  server: S,
  auth: Pick<BetterMcpAuth<M, F, E, C, P>, "contextOf">,
): BetterMcpServer<S, M, F, E, C, P> {
  const register = server.registerTool.bind(server);
  const registerTool = (
    name: string,
    config: BetterToolConfig<StandardSchemaWithJSON | undefined, undefined>,
    cb: (...params: unknown[]) => ToolReturn,
  ): unknown =>
    // SAFETY: the SDK calls tool callbacks as (args, ctx) or (ctx); the context is always last.
    (register as (name: string, config: unknown, cb: unknown) => unknown)(
      name,
      config,
      async (...params: unknown[]) => {
        // SAFETY: the SDK passes its ServerContext as the last argument.
        const ctx = params.at(-1) as McpContext;
        const bs = await auth.contextOf(ctx);
        const extended = withExtra(ctx, { db: bs.db, auth: bs.auth, bs });
        return cb(...params.slice(0, -1), extended);
      },
    );
  Object.defineProperty(server, "registerTool", {
    value: registerTool,
    configurable: true,
    writable: true,
  });
  // SAFETY: registerTool is replaced above with the wrapper BetterMcpServer describes.
  // oxlint-disable-next-line anti-slop/no-chained-type-assertions -- S's own registerTool type does not overlap the wrapper's; the property was replaced above.
  return server as unknown as BetterMcpServer<S, M, F, E, C, P>;
}
