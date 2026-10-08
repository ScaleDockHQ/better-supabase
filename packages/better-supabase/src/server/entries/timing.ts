import { defineMiddleware, type SingleKeyEntry } from "@supabase/middleware";

import type { DbStats } from "../../core/stats.ts";

/** The header `withDbStats` sets: `calls;waves;ms`, what `expectDbBudget` reads. */
export const DB_CALLS_HEADER = "x-bs-db-calls";

/** `calls;waves;ms`, the value of the stats header. */
export function formatDbStats(stats: DbStats): string {
  return `${stats.calls};${stats.waves};${stats.ms}`;
}

/** Parses the stats header back into numbers, or `undefined` when it is malformed. */
export function parseDbStats(
  value: string | null | undefined,
): Pick<DbStats, "calls" | "waves" | "ms"> | undefined {
  if (!value) return undefined;
  const [calls, waves, ms] = value.split(";").map(Number);
  if (
    calls === undefined ||
    waves === undefined ||
    ms === undefined ||
    [calls, waves, ms].some(Number.isNaN)
  )
    return undefined;
  return { calls, waves, ms };
}

/** Collects `Server-Timing` metrics for one request. */
export interface ServerTiming {
  /** Adds a metric; `dur` in milliseconds. */
  add(name: string, dur: number, description?: string): void;
  /** Runs `fn` and records how long it took under `name`. */
  measure<T>(name: string, fn: () => T | Promise<T>): Promise<T>;
}

function withHeaders(
  response: Response,
  edit: (headers: Headers) => void,
): Response {
  const headers = new Headers(response.headers);
  edit(headers);
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

const TOKEN = /[^!#$%&'*+\-.^_`|~0-9A-Za-z]/g;

function metric(name: string, dur: number, description?: string): string {
  const desc =
    description === undefined
      ? ""
      : `;desc="${description.replaceAll(/["\\]/g, "")}"`;
  return `${name.replaceAll(TOKEN, "_")};dur=${dur.toFixed(1)}${desc}`;
}

/**
 * Entry contributing `ctx.timing`, and adding `Server-Timing` to the
 * response: `bs;dur=<ms>` for everything after it, plus the metrics handlers
 * add with `ctx.timing.add()` or `measure()`. Put it first, so it times the
 * whole request. Browsers show it in the network panel.
 */
export function withServerTiming(
  now: () => number = () => performance.now(),
): SingleKeyEntry<"timing", Record<never, never>, ServerTiming> {
  return defineMiddleware<
    "timing",
    undefined,
    Record<never, never>,
    ServerTiming
  >({
    key: "timing",
    run: () =>
      // oxlint-disable-next-line typescript/require-await -- an async generator is the response-seam shape `defineMiddleware` takes.
      async function* () {
        const started = now();
        const metrics: string[] = [];
        const timing: ServerTiming = {
          add: (name, dur, description) => {
            metrics.push(metric(name, dur, description));
          },
          async measure(name, fn) {
            const start = now();
            try {
              return await fn();
            } finally {
              metrics.push(metric(name, now() - start));
            }
          },
        };
        const response = yield { timing };
        const total = metric("bs", now() - started);
        return withHeaders(response, (headers) => {
          headers.append("server-timing", [total, ...metrics].join(", "));
        });
      },
  })();
}

/**
 * Entry adding the request's database totals to the response, after the
 * handler ran: `x-bs-db-calls: calls;waves;ms`, which `expectDbBudget(response)`
 * reads, and a `bs-db` `Server-Timing` metric. Put it
 * after `withBetterSupabase`, which contributes `ctx.bs`.
 */
export function withDbStats(
  options: { readonly header?: string } = {},
): SingleKeyEntry<
  "dbStats",
  { readonly bs: { stats(): DbStats } },
  () => DbStats
> {
  const header = options.header ?? DB_CALLS_HEADER;
  return defineMiddleware<
    "dbStats",
    undefined,
    { readonly bs: { stats(): DbStats } },
    () => DbStats
  >({
    key: "dbStats",
    run: () =>
      // oxlint-disable-next-line typescript/require-await -- an async generator is the response-seam shape `defineMiddleware` takes.
      async function* (_request, ctx) {
        const dbStats = (): DbStats => ctx.bs.stats();
        const response = yield { dbStats };
        const stats = dbStats();
        return withHeaders(response, (headers) => {
          headers.set(header, formatDbStats(stats));
          headers.append(
            "server-timing",
            metric(
              "bs-db",
              stats.ms,
              `${stats.calls} calls, ${stats.waves} waves`,
            ),
          );
        });
      },
  })();
}
