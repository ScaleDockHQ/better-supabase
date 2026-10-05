import type { BetterSupabase } from "../core/define.ts";
import type { AnyFunctions, AnyModels } from "../schema/types.ts";
import type { GuardOptions } from "../server/respond.ts";
import type { ServerContext, ServerOptions } from "../server/server.ts";

import { dbError, DbException } from "../core/errors.ts";
import { PRIMARY_COOKIE } from "../server/replicas.ts";
import { type ConformanceReport, conform, expect } from "./conformance.ts";

// oxlint-disable-next-line typescript/no-explicit-any -- the kit accepts a definition of any schema.
type AnySupabase = BetterSupabase<any, any, any, any>;

/** What the adapter kit asks a handler to do with the caller's context. */
export type AdapterRun = (
  ctx: Pick<
    ServerContext<AnyModels, AnyFunctions, unknown>,
    "auth" | "replica"
  >,
) => unknown;

export interface TestAdapterOptions {
  /** The definition the adapter is built from: the kit tracks event sends on its `events`. */
  readonly betterSupabase: AnySupabase;
  /**
   * Builds the adapter with `server` (pass it to `createX(betterSupabase,
   * server)`) and returns a fetch function that answers a request with
   * `run` as the caller, behind a guard that allows `allow`. Translate the
   * kit's bare GET into what the adapter expects (a JSON-RPC `tools/call`,
   * an oRPC call) inside the function.
   */
  readonly serve: (
    server: ServerOptions & { readonly exposeErrors: false },
    run: AdapterRun,
    options: {
      readonly allow: NonNullable<GuardOptions["allow"]>;
      readonly waitUntil: (promise: Promise<unknown>) => void;
    },
  ) => (request: Request) => Promise<Response>;
  /** The adapter answers handler errors in a 200 body (MCP tool results), not with HTTP statuses. */
  readonly errorsInBody?: boolean;
  /** The adapter sends no cookies (bearer-only transports such as MCP). */
  readonly cookies?: false;
}

const KIT_SERVER = {
  env: {
    url: "http://127.0.0.1:54321",
    publishableKey: "sb_publishable_kit",
    jwksUrl: new URL("http://127.0.0.1:54321/auth/v1/.well-known/jwks.json"),
  },
  readUrl: "http://127.0.0.1:54329",
  prefetchJwks: false,
  exposeErrors: false,
} as const;

/**
 * Proves a framework adapter refuses callers its guard rejects, answers
 * `DbError`s with their status, hides unexpected errors, applies the
 * context's cookies and hands pending event sends to `waitUntil`, the way
 * `handle()` from `better-supabase/server` does.
 */
export function testAdapter(
  name: string,
  options: TestAdapterOptions,
): Promise<ConformanceReport> {
  const { events } = options.betterSupabase;
  const call = async (
    run: AdapterRun,
    allow: NonNullable<GuardOptions["allow"]> = ["anon"],
    waitUntil: (promise: Promise<unknown>) => void = () => undefined,
  ): Promise<Response> =>
    options.serve(KIT_SERVER, run, { allow, waitUntil })(
      new Request("http://127.0.0.1/kit"),
    );
  const errorStatus = (expected: number): number =>
    options.errorsInBody ? 200 : expected;
  return conform(`Adapter "${name}"`, [
    [
      "refuses a caller the guard rejects",
      async () => {
        let ran = false;
        const response = await call(() => {
          ran = true;
        }, ["user"]);
        expect(
          response.status === 401,
          `expected 401 for an anonymous caller, got ${response.status}`,
        );
        expect(!ran, "the handler ran for a refused caller");
      },
    ],
    [
      "runs the handler for an allowed caller",
      async () => {
        const response = await call(() => ({ kit: "ran" }));
        expect(response.status === 200, `expected 200, got ${response.status}`);
        const body = await response.text();
        expect(body.includes("ran"), `the handler's data is missing: ${body}`);
      },
    ],
    [
      "answers a DbError with its status",
      async () => {
        const response = await call(() => {
          throw new DbException(dbError("not_found", "kit: no such row"));
        });
        expect(
          response.status === errorStatus(404),
          `expected ${errorStatus(404)}, got ${response.status}`,
        );
        const body = await response.text();
        expect(
          body.includes("kit: no such row"),
          `the error message is missing: ${body}`,
        );
      },
    ],
    [
      "hides the message of an unexpected error",
      async () => {
        const response = await call(() => {
          throw new Error("kit-internal-detail");
        });
        expect(
          response.status === errorStatus(500),
          `expected ${errorStatus(500)}, got ${response.status}`,
        );
        const body = await response.text();
        expect(
          !body.includes("kit-internal-detail"),
          "the response leaks the error message",
        );
      },
    ],
    options.cookies !== false && [
      "applies the context's cookies",
      async () => {
        let replica = false;
        const response = await call((ctx) => {
          replica = ctx.replica !== undefined;
          ctx.replica?.pin();
          return { pinned: true };
        });
        expect(replica, "ctx.replica is unset: pass `server` to the adapter");
        expect(
          response.headers
            .getSetCookie()
            .some((cookie) => cookie.startsWith(`${PRIMARY_COOKIE}=`)),
          `a write must send ${PRIMARY_COOKIE}; apply ctx.apply() or ctx.cookies()`,
        );
      },
    ],
    [
      "hands pending event sends to waitUntil",
      async () => {
        const { promise: send, resolve } = Promise.withResolvers<void>();
        const waited: Promise<unknown>[] = [];
        await call(
          () => {
            events.track(send);
            return { sent: true };
          },
          ["anon"],
          (promise) => {
            waited.push(promise);
          },
        );
        resolve();
        expect(
          waited.length > 0,
          "waitUntil was not called while an event send was pending",
        );
        await Promise.all(waited);
      },
    ],
  ]);
}
