import type { Logger } from "../core/logger.ts";
import type { DbStats } from "../core/stats.ts";

import { EMPTY_STATS, StatsRecorder } from "../core/stats.ts";

/** Forwarded by the proxy so every scope of one render shares an id. */
export const REQUEST_ID_HEADER = "x-bsb-request-id";

/**
 * The id requests of one render share: the proxy's `x-bsb-request-id`, else the
 * W3C trace id, `x-vercel-id` or `x-request-id` the platform forwards. Without
 * any, every scope counts on its own.
 */
export function requestIdOf(headers: Headers): string | undefined {
  const forwarded = headers.get(REQUEST_ID_HEADER);

  if (forwarded) {
    return forwarded;
  }

  const trace = headers.get("traceparent")?.split("-")[1];

  if (trace && /^[0-9a-f]{32}$/.test(trace)) {
    return `trace:${trace}`;
  }

  const vercel = headers.get("x-vercel-id");

  if (vercel) {
    return `vercel:${vercel}`;
  }

  const plain = headers.get("x-request-id");

  return plain ? `request:${plain}` : undefined;
}

/** Sequential database round trips a development render may wait on. */
export const DEFAULT_ROUND_TRIPS = 4;

export interface DbBudget {
  readonly calls?: number;
  readonly waves?: number;
  /** Service-role calls a user request may make. */
  readonly adminCalls?: number;
  /** Token verifications one request may run across its scopes. */
  readonly verifications?: number;
}

export interface CollectorOptions {
  readonly budget?: DbBudget;
  /** Warn when a render exceeds `budget`. */
  readonly warn?: boolean;
  readonly logger: Logger;
  /** How long totals stay readable. Defaults to 60 seconds. */
  readonly ttlMs?: number;
  /** Defaults to 500 requests. */
  readonly maxEntries?: number;
  /**
   * Idle time after the last call before the budget is checked. Defaults to 250
   * ms.
   */
  readonly idleMs?: number;
}

interface Entry {
  readonly recorder: StatsRecorder;
  readonly created: number;
  readonly options: CollectorOptions;
  timer?: ReturnType<typeof setTimeout> | undefined;
}

class CollectedRecorder extends StatsRecorder {
  readonly #onIdle: () => void;

  constructor(onIdle: () => void) {
    super();
    this.#onIdle = onIdle;
  }

  override begin(table: string, admin?: boolean): () => void {
    const end = super.begin(table, admin);

    return () => {
      end();
      this.#onIdle();
    };
  }
}

/** Request totals keyed by request id, bounded by age and count. */
export class StatsCollector {
  readonly #entries = new Map<string, Entry>();
  readonly #options: CollectorOptions;

  constructor(options: CollectorOptions) {
    this.#options = options;
  }

  /**
   * The recorder for a request id, created on first use. `options` sets the
   * budget and logger of a new entry; the collector's own are the default.
   */
  recorderFor(id: string, options?: CollectorOptions): StatsRecorder {
    const existing = this.#entries.get(id);

    if (existing) {
      return existing.recorder;
    }

    this.#prune();

    const entry: Entry = {
      created: Date.now(),
      options: options ?? this.#options,
      recorder: new CollectedRecorder(() => {
        this.#schedule(id);
      }),
    };

    this.#entries.set(id, entry);

    return entry.recorder;
  }

  get(id: string): DbStats | undefined {
    return this.#entries.get(id)?.recorder.snapshot();
  }

  #schedule(id: string): void {
    const entry = this.#entries.get(id);

    if (!entry) {
      return;
    }

    const { budget, warn, logger, idleMs } = entry.options;

    if (!warn || !budget) {
      return;
    }

    if (entry.timer) {
      clearTimeout(entry.timer);
    }

    entry.timer = setTimeout(() => {
      entry.timer = undefined;
      const stats = entry.recorder.snapshot();

      if (!overBudget(stats, budget)) {
        return;
      }

      logger.warn(
        `request ${id} made ${stats.calls} database calls in ${stats.waves} waves, over the budget of ${describeBudget(budget)}${extraStats(stats)}; load the page's data in one read set (defineReadSet) to make it one call, run reads as the user instead of bsb.admin(), and pass cached({ session }) in nested scopes`,
        { requestId: id, ...stats },
      );
    }, idleMs ?? 250);
  }

  #prune(): void {
    const cutoff = Date.now() - (this.#options.ttlMs ?? 60_000);
    const max = this.#options.maxEntries ?? 500;

    for (const [id, entry] of this.#entries) {
      if (entry.created >= cutoff && this.#entries.size < max) {
        break;
      }

      if (entry.timer) {
        clearTimeout(entry.timer);
      }

      this.#entries.delete(id);
    }
  }
}

const SHARED = Symbol.for("better-supabase.next.stats-collector");

/** A view of the shared collector that applies one app's budget and logger. */
export interface CollectorView {
  recorderFor(id: string): StatsRecorder;
  get(id: string): DbStats | undefined;
}

/**
 * One store of request totals per process. Next.js can load the proxy, pages
 * and route handlers as separate module instances, and they must see the same
 * totals. Each caller's budget and logger apply to the requests it starts, so a
 * second app in the process keeps its own.
 */
export function sharedCollector(options: CollectorOptions): CollectorView {
  // SAFETY: SHARED is a module symbol, so nothing else writes to that global slot.
  const scope = globalThis as { [SHARED]?: StatsCollector };
  const shared = scope[SHARED] ?? new StatsCollector(options);
  scope[SHARED] = shared;

  return {
    recorderFor: (id) => shared.recorderFor(id, options),
    get: (id) => shared.get(id),
  };
}

function overBudget(stats: DbStats, budget: DbBudget): boolean {
  return (
    (budget.calls !== undefined && stats.calls > budget.calls) ||
    (budget.waves !== undefined && stats.waves > budget.waves) ||
    (budget.adminCalls !== undefined && stats.adminCalls > budget.adminCalls) ||
    (budget.verifications !== undefined &&
      stats.verifications > budget.verifications)
  );
}

function extraStats(stats: DbStats): string {
  const parts = [
    stats.adminCalls > 0 ? `${stats.adminCalls} with the service role` : "",
    stats.verifications > 1 ? `${stats.verifications} token verifications` : "",
  ].filter(Boolean);

  return parts.length > 0 ? ` (${parts.join(", ")})` : "";
}

function describeBudget(budget: DbBudget): string {
  return [
    budget.calls === undefined ? undefined : `${budget.calls} calls`,
    budget.waves === undefined ? undefined : `${budget.waves} waves`,
    budget.adminCalls === undefined
      ? undefined
      : `${budget.adminCalls} admin calls`,
    budget.verifications === undefined
      ? undefined
      : `${budget.verifications} verifications`,
  ]
    .filter(Boolean)
    .join(" and ");
}

/**
 * `calls;waves;ms;verifications;adminCalls;tagCalls;hits;misses;fillMs`, the
 * value of the debug header. `hits` counts cached calls served from an entry (a
 * hit, a stale entry or a wait), `misses` the ones that filled, and `fillMs`
 * the time those fills took.
 */
export function formatStats(stats: DbStats): string {
  const entries = stats.entries ?? [];
  const misses = entries.filter((entry) => entry.outcome === "miss");

  const fillMs = misses.reduce((sum, entry) => sum + (entry.fillMs ?? 0), 0);

  return [
    stats.calls,
    stats.waves,
    stats.ms,
    stats.verifications,
    stats.adminCalls,
    stats.tagCalls ?? 0,
    entries.length - misses.length,
    misses.length,
    Math.round(fillMs * 100) / 100,
  ].join(";");
}

/** ` phases=write:2,render:3 decodes=1`, or an empty string with nothing to add. */
function describePhases(stats: DbStats): string {
  const phases = Object.entries(stats.phases ?? {})
    .map(([phase, calls]) => `${phase}:${calls}`)
    .join(",");

  const hits = Object.entries(stats.keptHits ?? {})
    .map(([phase, count]) => `${phase}:${count}`)
    .join(",");

  return [
    phases === "" ? "" : ` phases=${phases}`,
    hits === "" ? "" : ` keptHits=${hits}`,
    stats.decodes ? ` decodes=${stats.decodes}` : "",
  ].join("");
}

/**
 * A server action answers with a serializable result, never a `Response`, so it
 * can't carry the stats header. This logs the header's value instead; the
 * proxy's request id links the line to the page.
 */
export async function logActionStats(
  collector: Pick<CollectorView, "get"> | undefined,
  logger: Logger,
  request: () => Promise<Request>,
  header: string,
): Promise<void> {
  const id = collector && requestIdOf((await request()).headers);
  const stats = id === undefined ? undefined : collector?.get(id);

  if (stats) {
    logger.info(
      `bsb.action ${header}: ${formatStats(stats)}${describePhases(stats)}`,
    );
  }
}

/** The development budget: `waves` round trips and no service-role call. */
export function devBudget(waves: number | false): DbBudget | undefined {
  return waves === false ? undefined : { waves, adminCalls: 0 };
}

/** The 404 of `bsb.debugRoute()`, with the reason as JSON. */
export function debugRefusal(on: boolean): Response {
  return Response.json(
    on
      ? {
          error: "missing ?id=",
          reason:
            "Pass the request id from the bsb-request-id response header, or the URL in bsb-stats-url.",
        }
      : {
          error: "debug is off",
          reason:
            "Set createNext({ debug: { enabled: true } }); production needs it on explicitly, and the proxy must run for the page.",
        },
    { status: 404, headers: { "cache-control": "no-store" } },
  );
}

/**
 * The handler of `bsb.debugRoute()`: the request's database totals for `?id=`,
 * or the refusal.
 */
export function debugRoute(
  collector: Pick<StatsCollector, "get"> | undefined,
  statsHeader: string,
  statsValue: (stats: DbStats) => string,
): (request: Request) => Promise<Response> {
  return (request) => {
    const id = new URL(request.url).searchParams.get("id");

    if (!collector || !id) {
      return Promise.resolve(debugRefusal(collector !== undefined));
    }

    // A render served entirely from cache entries records nothing: it made no
    // calls. A fill records on the request that started it, remote fills
    // through bsb.remote() included, raw ctx.supabase calls too.
    const stats = collector.get(id) ?? EMPTY_STATS;

    return Promise.resolve(
      Response.json(stats, {
        headers: {
          [statsHeader]: statsValue(stats),
          "cache-control": "no-store",
        },
      }),
    );
  };
}
