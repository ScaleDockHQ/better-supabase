import type { DbStats } from "../core/stats.ts";

import { DB_CALLS_HEADER, parseDbStats } from "../server/entries/timing.ts";

/** The part of a Playwright `Request` the budget check reads. */
export interface BudgetRequest {
  headers(): Record<string, string>;
}

/** The part of a Playwright `Response` the budget check reads. */
export interface BudgetResponse {
  url(): string;
  headers(): Record<string, string>;
  /** Never settles when the browser aborts the stream, so `requestfailed` ends the wait too. */
  finished(): Promise<unknown>;
  request(): BudgetRequest;
}

/** The part of a Playwright `Page` the budget check uses. */
export interface BudgetPage {
  on(event: "response", listener: (response: BudgetResponse) => void): unknown;
  on(
    event: "requestfailed",
    listener: (request: BudgetRequest) => void,
  ): unknown;
  off(event: "response", listener: (response: BudgetResponse) => void): unknown;
  off(
    event: "requestfailed",
    listener: (request: BudgetRequest) => void,
  ): unknown;
  reload(): Promise<unknown>;
  readonly request: {
    get(url: string): Promise<{
      ok(): boolean;
      status(): number;
      json(): Promise<unknown>;
    }>;
  };
}

export interface DbBudgetExpectation {
  readonly maxCalls?: number;
  readonly maxWaves?: number;
  /** The navigation to measure. Defaults to reloading the page. */
  readonly during?: () => Promise<unknown>;
  /** Also measure router prefetches. Defaults to false. */
  readonly prefetches?: boolean;
  /** How long to wait for a streamed response to finish. Defaults to 10 seconds. */
  readonly timeoutMs?: number;
  /**
   * How long to keep listening once `during` resolves and no new response
   * arrives, for renders it started that answer later (the dynamic render
   * after an `instant()` lock releases). Defaults to 500 ms.
   */
  readonly settleMs?: number;
  /**
   * When no document or RSC response carries `x-bs-request-id`, throw
   * (the default) or return `[]`. Cache-only navigations never hit the
   * proxy, so they have no request id.
   */
  readonly requireRequest?: boolean;
}

export interface MeasuredRender {
  readonly url: string;
  readonly requestId: string;
  readonly stats: DbStats;
}

function isPrefetch(response: BudgetResponse): boolean {
  const headers = response.request().headers();
  return (
    headers["next-router-prefetch"] !== undefined ||
    headers["purpose"] === "prefetch" ||
    (headers["sec-purpose"]?.includes("prefetch") ?? false)
  );
}

function sleep(ms: number): Promise<void> {
  return new Promise((done) => {
    setTimeout(done, ms);
  });
}

function settle(promise: Promise<unknown>, ms: number): Promise<unknown> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  return Promise.race([
    promise,
    new Promise((done) => {
      timer = setTimeout(done, ms);
    }),
  ]).finally(() => {
    clearTimeout(timer);
  });
}

/** What `expectDbBudget` measures on a plain fetch `Response`. */
export interface ResponseBudgetExpectation {
  readonly maxCalls?: number;
  readonly maxWaves?: number;
  /** The header `withDbStats` wrote. Defaults to `x-bs-db-calls`. */
  readonly header?: string;
}

/** The calls, waves and time one response's request made. */
export type ResponseDbStats = Pick<DbStats, "calls" | "waves" | "ms">;

function expectResponseBudget(
  response: Response,
  expectation: ResponseBudgetExpectation,
): ResponseDbStats {
  const header = expectation.header ?? DB_CALLS_HEADER;
  const stats = parseDbStats(response.headers.get(header));
  if (!stats) {
    throw new Error(
      `expectDbBudget: the response has no ${header} header. Add withDbStats() to the entries.`,
    );
  }
  if (
    (expectation.maxCalls !== undefined &&
      stats.calls > expectation.maxCalls) ||
    (expectation.maxWaves !== undefined && stats.waves > expectation.maxWaves)
  ) {
    throw new Error(
      `expectDbBudget: ${stats.calls} calls in ${stats.waves} waves, over the budget of ${expectation.maxCalls ?? "∞"} calls and ${expectation.maxWaves ?? "∞"} waves`,
    );
  }
  return stats;
}

/**
 * Reads the `withDbStats()` header of a fetch `Response` from any adapter
 * (Hono, SvelteKit, oRPC, an edge function) and fails when its request made
 * more database calls or waves than allowed.
 */
export function expectDbBudget(
  response: Response,
  expectation: ResponseBudgetExpectation,
): ResponseDbStats;
/**
 * Measures every document and RSC navigation response during `during` and
 * fails when one render makes more database calls or waves than allowed.
 * Needs `createNext(betterSupabase, { debug })` and `bs.debugRoute()` in the app.
 */
export function expectDbBudget(
  page: BudgetPage,
  expectation: DbBudgetExpectation,
): Promise<readonly MeasuredRender[]>;
export function expectDbBudget(
  target: Response | BudgetPage,
  expectation: DbBudgetExpectation | ResponseBudgetExpectation,
): ResponseDbStats | Promise<readonly MeasuredRender[]> {
  if (target instanceof Response)
    return expectResponseBudget(target, expectation);
  return expectPageBudget(target, expectation);
}

async function expectPageBudget(
  page: BudgetPage,
  expectation: DbBudgetExpectation,
): Promise<readonly MeasuredRender[]> {
  const seen: { response: BudgetResponse; url: string; id: string }[] = [];
  let lastSeen = 0;
  const listener = (response: BudgetResponse): void => {
    const headers = response.headers();
    const id = headers["x-bs-request-id"];
    const stats = headers["x-bs-stats"];
    if (!id || !stats || (!expectation.prefetches && isPrefetch(response)))
      return;
    lastSeen = Date.now();
    seen.push({ response, id, url: new URL(stats, response.url()).href });
  };
  const settleMs = expectation.settleMs ?? 500;
  const timeoutMs = expectation.timeoutMs ?? 10_000;
  /** Waits until no response has arrived for `settleMs`, at most `timeoutMs`. */
  const quiet = async (): Promise<void> => {
    const start = Date.now();
    lastSeen = Math.max(lastSeen, start);
    for (;;) {
      const left = lastSeen + settleMs - Date.now();
      if (left <= 0 || Date.now() - start >= timeoutMs) return;
      await sleep(left);
    }
  };
  const failed = new WeakSet<BudgetRequest>();
  const aborts = new Map<BudgetRequest, () => void>();
  const onFailed = (request: BudgetRequest): void => {
    failed.add(request);
    aborts.get(request)?.();
  };
  const ended = (response: BudgetResponse): Promise<unknown> => {
    const request = response.request();
    if (failed.has(request)) return Promise.resolve();
    return Promise.race([
      response.finished(),
      new Promise<void>((done) => {
        aborts.set(request, done);
      }),
    ]);
  };
  page.on("response", listener);
  page.on("requestfailed", onFailed);
  try {
    try {
      await (expectation.during ? expectation.during() : page.reload());
      await quiet();
    } finally {
      page.off("response", listener);
    }
    if (seen.length === 0) {
      if (expectation.requireRequest === false) return [];
      throw new Error(
        "expectDbBudget: no response carried x-bs-request-id. Enable createNext(betterSupabase, { debug: { enabled: true } }) and run the proxy.",
      );
    }
    await Promise.all(
      seen.map(({ response }) => settle(ended(response), timeoutMs)),
    );
  } finally {
    page.off("requestfailed", onFailed);
  }

  const renders: MeasuredRender[] = [];
  for (const { response, id, url } of seen) {
    const reply = await page.request.get(url);
    if (!reply.ok()) {
      throw new Error(
        `expectDbBudget: ${url} answered ${reply.status()}. Mount bs.debugRoute() at that path.`,
      );
    }
    // SAFETY: the stats endpoint always responds with a DbStats object.
    renders.push({
      url: response.url(),
      requestId: id,
      stats: (await reply.json()) as DbStats,
    });
  }

  const over = renders.filter(
    ({ stats }) =>
      (expectation.maxCalls !== undefined &&
        stats.calls > expectation.maxCalls) ||
      (expectation.maxWaves !== undefined &&
        stats.waves > expectation.maxWaves),
  );
  if (over.length > 0) {
    const lines = over.map(
      ({ url, stats }) =>
        `  ${url}: ${stats.calls} calls in ${stats.waves} waves (${stats.tables.join(", ")})`,
    );
    throw new Error(
      `expectDbBudget: over the budget of ${expectation.maxCalls ?? "∞"} calls and ${expectation.maxWaves ?? "∞"} waves:\n${lines.join("\n")}`,
    );
  }
  return renders;
}
