import type { AuthResolution, AuthState } from "../../auth/resolve.ts";
import type { SessionEncoding } from "../../auth/session.ts";
import type { EventHub } from "../../core/events.ts";
import type { AnyFunctions, AnyModels } from "../../schema/types.ts";
import type { ContextOptions, ServerContext } from "../server.ts";
import type { ActiveSupport } from "../support.ts";

/**
 * What the entries need from a `createServer` server: its resolver, its
 * request-scoped context builder and the settings behind them. The server
 * registers it once; entries read it with `serverCore(server)`.
 */
export interface ServerCore<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
> {
  readonly events: EventHub;
  /** How long reads stay on the primary after a write. */
  readonly pinMs: number;
  resolve(
    request: Request,
    options: {
      readonly refresh?: boolean;
      readonly cookies?: boolean;
      readonly encode?: SessionEncoding;
      readonly checkSession?: boolean;
    },
  ): Promise<AuthResolution<C, P>>;
  /** The session cookie's name (`auth.cookie.name`, else `sb-<ref>-auth-token`). */
  sessionCookie(): string;
  /** `ServerOptions.tenant`, or `undefined` without one. */
  tenant(
    request: Request,
    auth: AuthState<C, P>,
  ): string | undefined | PromiseLike<string | undefined>;
  support(
    request: Request,
    auth: AuthState<C, P>,
  ): Promise<ActiveSupport | undefined>;
  context(
    resolution: AuthResolution<C, P>,
    request: Request,
    options: ContextOptions,
    tenant: string | undefined,
  ): ServerContext<M, F, E, C, P>;
}

// oxlint-disable-next-line typescript/no-explicit-any -- the registry holds servers of every schema.
type AnyCore = ServerCore<any, any, any, any, any>;

const cores = new WeakMap<object, AnyCore>();

/** Records the core behind `server`, so `serverCore` finds it on copies too. */
export function registerCore(server: object, core: AnyCore): void {
  cores.set(server, core);
}

/** Copies the registration from `from` to `to` (`extendServer` builds a new object). */
export function shareCore(from: object, to: object): void {
  const core = cores.get(from);
  if (core) cores.set(to, core);
}

/** The core of a server built by `createServer` or one of the adapter factories. */
export function serverCore<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C,
  P,
>(server: {
  readonly events: EventHub;
  context(request: Request): Promise<ServerContext<M, F, E, C, P>>;
}): ServerCore<M, F, E, C, P> {
  const core = cores.get(server);
  if (!core) {
    throw new TypeError(
      "better-supabase: this server was not built by createServer(); pass the definition or a server from createServer",
    );
  }
  // SAFETY: the registry maps each server to the core createServer built for it, with the same generics.
  return core as ServerCore<M, F, E, C, P>;
}

/**
 * Per-call state `server.context()` seeds under a symbol, so one folded
 * pipeline serves every call: the options of this call, and the context the
 * terminal hands back.
 */
export interface CallState {
  readonly options: ContextOptions;
  context?: unknown;
}

export const CALL: unique symbol = Symbol("better-supabase.call");

const supportLookups = new WeakMap<
  object,
  Promise<ActiveSupport | undefined>
>();

/**
 * Starts the support lookup for a signed-in caller, so `withTenant` can run
 * the tenant resolver while the support store answers. Other callers never
 * have a support session, so they skip it.
 */
export function startSupportLookup<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C,
  P,
>(
  core: ServerCore<M, F, E, C, P>,
  request: Request,
  session: AuthResolution<C, P>,
): void {
  if (session.auth.kind !== "user" || supportLookups.has(session)) return;
  const lookup = core.support(request, session.auth);
  // withSupport awaits and reports a failure; a pipeline without it must not leave it unhandled.
  lookup.catch(() => undefined);
  supportLookups.set(session, lookup);
}

/** The support session of a resolved request: the started lookup, else a new one. */
export function supportLookup<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C,
  P,
>(
  core: ServerCore<M, F, E, C, P>,
  request: Request,
  session: AuthResolution<C, P>,
): Promise<ActiveSupport | undefined> {
  return supportLookups.get(session) ?? core.support(request, session.auth);
}

/** The call state on a context seeded by `server.context()`, if any. */
export function callOf(ctx: object): CallState | undefined {
  // SAFETY: only server.context() writes this symbol, and always a CallState.
  return (ctx as { readonly [CALL]?: CallState })[CALL];
}
