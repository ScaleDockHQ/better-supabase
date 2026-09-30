import type { DbStats } from "../core/stats.ts";

/** The part of a Playwright `Response` the budget check reads. */
export interface BudgetResponse {
  url(): string;
  headers(): Record<string, string>;
  finished(): Promise<unknown>;
  request(): { headers(): Record<string, string> };
}

/** The part of a Playwright `Page` the budget check uses. */
export interface BudgetPage {
  on(event: "response", listener: (response: BudgetResponse) => void): unknown;
  off(event: "response", listener: (response: BudgetResponse) => void): unknown;
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

function settle(promise: Promise<unknown>, ms: number): Promise<unknown> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  return Promise.race([
    promise,
    new Promise((done) => {
      timer = setTimeout(done, ms);
    }),
  ]).finally(() => clearTimeout(timer));
}

/**
 * Measures every document and RSC navigation response during `during` and
 * fails when one render makes more database calls or waves than allowed.
 * Needs `createNext(sb, { debug })` and `next.debugRoute()` in the app.
 */
export async function expectDbBudget(
  page: BudgetPage,
  expectation: DbBudgetExpectation,
): Promise<readonly MeasuredRender[]> {
  const seen: { response: BudgetResponse; url: string; id: string }[] = [];
  const listener = (response: BudgetResponse): void => {
    const headers = response.headers();
    const id = headers["x-bs-request-id"];
    const stats = headers["x-bs-stats"];
    if (!id || !stats || (!expectation.prefetches && isPrefetch(response)))
      return;
    seen.push({ response, id, url: new URL(stats, response.url()).href });
  };
  page.on("response", listener);
  try {
    await (expectation.during ? expectation.during() : page.reload());
  } finally {
    page.off("response", listener);
  }
  if (seen.length === 0) {
    throw new Error(
      "expectDbBudget: no response carried x-bs-request-id. Enable createNext(sb, { debug: { enabled: true } }) and run the proxy.",
    );
  }
  await Promise.all(
    seen.map(({ response }) =>
      settle(response.finished(), expectation.timeoutMs ?? 10_000),
    ),
  );

  const renders: MeasuredRender[] = [];
  for (const { response, id, url } of seen) {
    const reply = await page.request.get(url);
    if (!reply.ok()) {
      throw new Error(
        `expectDbBudget: ${url} answered ${reply.status()}. Mount next.debugRoute() at that path.`,
      );
    }
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
