import type { AuthSession } from "../auth/view.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type {
  BetterSupabaseContributions,
  BetterSupabaseEntry,
} from "./composite.ts";
import type { SessionEntryConfig } from "./entries/session.ts";
import type { RefusalRedirects } from "./refusal.ts";
import type { AllowedCaller } from "./respond.ts";
import type { BetterServer, ServerOptions } from "./server.ts";

import { toSession } from "../auth/view.ts";
import { withBetterSupabase } from "./composite.ts";

/** Every caller: the framework factories guard per loader, action or route instead. */
export const EVERY_CALLER: readonly AllowedCaller[] = [
  "user",
  "anonymous",
  "anon",
  "service",
  "apiKey",
];

/** What the framework factories (`createSvelteKit`, `createReactRouter`, `createTanStackStart`) take. */
export interface FrameworkOptions
  extends
    ServerOptions,
    RefusalRedirects,
    Pick<SessionEntryConfig, "checkSession" | "cookieScopes" | "encode"> {
  /**
   * When the middleware refreshes an expired session cookie. Defaults to
   * `'navigation'`: page loads, client navigations and form posts.
   */
  readonly refresh?: SessionEntryConfig["refresh"];
  /** Include internal error messages in Problem Details. Defaults to development only. */
  readonly exposeErrors?: boolean;
  /** Keeps the invocation alive for event sink sends, e.g. the Workers `ctx.waitUntil`. */
  readonly waitUntil?: (promise: Promise<unknown>) => void;
}

/** The keys the framework factories put on `locals` or `context`. */
export type FrameworkLocals<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C = unknown,
  P = unknown,
> = BetterSupabaseContributions<M, F, E, C, P> & {
  /** The caller as plain data, safe to return from a loader to the browser. */
  readonly session: AuthSession<C, P>;
};

/** The `withBetterSupabase` entry the framework factories run, admitting every caller. */
export function frameworkEntry<
  M extends AnyModels,
  F extends AnyFunctions,
  E,
  C,
  P,
>(
  server: BetterServer<M, F, E, C, P>,
  options: FrameworkOptions,
  expose: boolean,
): BetterSupabaseEntry<M, F, E, C, P> {
  return withBetterSupabase(server, {
    refresh: options.refresh ?? "navigation",
    allow: EVERY_CALLER,
    expose,
    ...(options.checkSession === undefined
      ? {}
      : { checkSession: options.checkSession }),
    ...(options.cookieScopes === undefined
      ? {}
      : { cookieScopes: options.cookieScopes }),
    ...(options.encode === undefined ? {} : { encode: options.encode }),
    ...(options.waitUntil === undefined
      ? {}
      : { waitUntil: options.waitUntil }),
  });
}

/** The contributions plus the serializable `session`. */
export function localsOf<M extends AnyModels, F extends AnyFunctions, E, C, P>(
  contributions: object,
): FrameworkLocals<M, F, E, C, P> {
  // SAFETY: frameworkEntry contributes exactly BetterSupabaseContributions for this server.
  const base = contributions as BetterSupabaseContributions<M, F, E, C, P>;
  return { ...base, session: toSession(base.bs.auth) };
}

interface WaitUntilHost {
  waitUntil(promise: Promise<unknown>): void;
}

function isWaitUntilHost(value: unknown): value is WaitUntilHost {
  return (
    typeof value === "object" &&
    value !== null &&
    "waitUntil" in value &&
    typeof value.waitUntil === "function"
  );
}

/** `platform.context.waitUntil` on Cloudflare, `platform.waitUntil` elsewhere. */
export function platformWaitUntil(
  platform: unknown,
): ((promise: Promise<unknown>) => void) | undefined {
  if (typeof platform !== "object" || platform === null) return undefined;
  const context: unknown = "context" in platform ? platform.context : platform;
  if (!isWaitUntilHost(context)) return undefined;
  return (promise) => {
    context.waitUntil(promise);
  };
}

/** The form body as `FormData`, JSON as a value, nothing as `undefined`. */
export async function actionInput(request: Request): Promise<unknown> {
  const type = request.headers.get("content-type") ?? "";
  if (type.includes("application/json")) return request.json();
  if (
    type.includes("form-data") ||
    type.includes("application/x-www-form-urlencoded")
  )
    return request.formData();
  return undefined;
}
