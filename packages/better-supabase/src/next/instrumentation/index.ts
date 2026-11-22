import type { Events } from "../../core/event-map.ts";
import type { EventHub } from "../../core/events.ts";

import { emitBlockEvent } from "../../core/block-events.ts";
import { defineEvents, event } from "../../core/event-map.ts";

/**
 * The `request` argument of Next.js's `onRequestError`, typed structurally so
 * `next` is not imported. `tests/optional-peers.test-d.ts` checks it against
 * the installed `InstrumentationOnRequestError`.
 */
export interface RequestErrorRequest {
  readonly path: string;
  readonly method: string;
  readonly headers: Readonly<Record<string, string | string[] | undefined>>;
}

/** The `context` argument of Next.js's `onRequestError`. */
export interface RequestErrorContext {
  readonly routerKind: "Pages Router" | "App Router";
  readonly routePath: string;
  readonly routeType: "render" | "route" | "action" | "proxy";
  readonly renderSource?:
    | "react-server-components"
    | "react-server-components-payload"
    | "server-rendering";
  readonly revalidateReason: "on-demand" | "stale" | undefined;
}

/** The data of a `request.failed` block event. */
export interface RequestFailedEventData {
  /** The error's `name`, or `Error` for a thrown value that is not one. */
  readonly name: string;
  /**
   * The error's message, cut to `maxMessageLength`. Left out when the bridge
   * runs with `message: false`.
   */
  readonly message?: string;
  /** Next.js's `digest`, the id that links the log line to the client error. */
  readonly digest?: string;
  /** The request path without its query string. */
  readonly path: string;
  readonly method: string;
  readonly routerKind: RequestErrorContext["routerKind"];
  /** The route pattern, such as `/customers/[id]`. */
  readonly routePath: string;
  readonly routeType: RequestErrorContext["routeType"];
  readonly renderSource?: NonNullable<RequestErrorContext["renderSource"]>;
  readonly revalidateReason?: "on-demand" | "stale";
}

/** The events the `onRequestError` bridge emits: type to data. */
export type RequestEvents = {
  readonly "request.failed": RequestFailedEventData;
};

/** The bridge's event types, for `onBlockEvent` and the webhook catalog. */
export const requestEvents: Events<RequestEvents> = defineEvents({
  "request.failed": event<RequestFailedEventData>(),
});

export interface OnRequestErrorOptions {
  /**
   * Set `false` to leave the error message out of the event. Defaults to
   * `true`.
   */
  readonly message?: boolean;
  /** The message is cut to this many characters. Defaults to 500. */
  readonly maxMessageLength?: number;
  /**
   * How long the returned promise waits for the sinks that already started, so
   * a serverless function does not freeze mid-send. Defaults to 2000 ms; `0`
   * returns at once.
   */
  readonly settleMs?: number;
}

/** What `createOnRequestError` returns: Next's `onRequestError` signature. */
export type OnRequestError = (
  error: unknown,
  request: RequestErrorRequest,
  context: RequestErrorContext,
) => Promise<void>;

const DEFAULT_MAX_MESSAGE = 500;
const DEFAULT_SETTLE_MS = 2000;

function pathOf(path: string): string {
  const cut = path.search(/[?#]/);

  return cut === -1 ? path : path.slice(0, cut);
}

function failureData(
  error: unknown,
  request: RequestErrorRequest,
  context: RequestErrorContext,
  options: OnRequestErrorOptions,
): RequestFailedEventData {
  const cause = typeof error === "object" && error !== null ? error : undefined;
  const name = error instanceof Error ? error.name : "Error";
  const digest = cause && "digest" in cause ? cause.digest : undefined;

  const text =
    error instanceof Error
      ? error.message
      : typeof error === "string"
        ? error
        : undefined;

  return {
    name,
    ...(options.message !== false && text !== undefined
      ? {
          message: text.slice(
            0,
            options.maxMessageLength ?? DEFAULT_MAX_MESSAGE,
          ),
        }
      : {}),
    ...(typeof digest === "string" ? { digest } : {}),
    path: pathOf(request.path),
    method: request.method,
    routerKind: context.routerKind,
    routePath: context.routePath,
    routeType: context.routeType,
    ...(context.renderSource ? { renderSource: context.renderSource } : {}),
    ...(context.revalidateReason
      ? { revalidateReason: context.revalidateReason }
      : {}),
  };
}

/**
 * Next.js's `onRequestError` as a bridge to the event sinks: every server error
 * (a render, route handler, Server Action or proxy failure) becomes a
 * `request.failed` block event. `forwardBlockEvents` sends it to a sink such as
 * the outbox, and `traceBlockEvents` records it on the active span. Headers,
 * cookies and the query string never enter the event. Nothing it does changes
 * what Next.js shows the user: a throwing handler is logged and ignored
 * (invariant 5).
 *
 * ```ts
 * import { createOnRequestError } from "better-supabase/next/instrumentation";
 *
 * import { betterSupabase } from "./lib/supabase/server";
 *
 * export const onRequestError = createOnRequestError(betterSupabase);
 * ```
 */
export function createOnRequestError(
  betterSupabase: { readonly events: EventHub },
  options: OnRequestErrorOptions = {},
): OnRequestError {
  const { events } = betterSupabase;
  const settleMs = options.settleMs ?? DEFAULT_SETTLE_MS;

  return async (error, request, context) => {
    try {
      emitBlockEvent<RequestEvents>(
        events,
        "request.failed",
        failureData(error, request, context, options),
      );
    } catch (cause) {
      events.logger.error("request.failed bridge threw", { cause });

      return;
    }

    if (settleMs <= 0 || !events.pending) {
      return;
    }

    let timer: ReturnType<typeof setTimeout> | undefined;

    await Promise.race([
      events.settled(),
      new Promise<void>((resolve) => {
        timer = setTimeout(resolve, settleMs);
      }),
    ]);

    clearTimeout(timer);
  };
}
