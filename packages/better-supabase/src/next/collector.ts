import type { Logger } from "../core/logger.ts";

import { type DbStats, StatsRecorder } from "../core/stats.ts";

/** Forwarded by the proxy so every scope of one render shares an id. */
export const REQUEST_ID_HEADER = "x-bs-request-id";

export interface DbBudget {
  readonly calls?: number;
  readonly waves?: number;
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
  /** Idle time after the last call before the budget is checked. Defaults to 250 ms. */
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

  override begin(table: string): () => void {
    const end = super.begin(table);
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
    if (existing) return existing.recorder;
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
    if (!entry) return;
    const { budget, warn, logger, idleMs } = entry.options;
    if (!warn || !budget) return;
    if (entry.timer) clearTimeout(entry.timer);
    entry.timer = setTimeout(() => {
      entry.timer = undefined;
      const stats = entry.recorder.snapshot();
      if (!overBudget(stats, budget)) return;
      logger.warn(
        `request ${id} made ${stats.calls} database calls in ${stats.waves} waves, over the budget of ${describeBudget(budget)}`,
        { requestId: id, ...stats },
      );
    }, idleMs ?? 250);
  }

  #prune(): void {
    const cutoff = Date.now() - (this.#options.ttlMs ?? 60_000);
    const max = this.#options.maxEntries ?? 500;
    for (const [id, entry] of this.#entries) {
      if (entry.created >= cutoff && this.#entries.size < max) break;
      if (entry.timer) clearTimeout(entry.timer);
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
 * and route handlers as separate module instances, and they must see the
 * same totals. Each caller's budget and logger apply to the requests it
 * starts, so a second app in the process keeps its own.
 */
export function sharedCollector(options: CollectorOptions): CollectorView {
  // SAFETY: SHARED is a module symbol, so nothing else writes to that global slot.
  const scope = globalThis as { [SHARED]?: StatsCollector };
  const shared = (scope[SHARED] ??= new StatsCollector(options));
  return {
    recorderFor: (id) => shared.recorderFor(id, options),
    get: (id) => shared.get(id),
  };
}

function overBudget(stats: DbStats, budget: DbBudget): boolean {
  return (
    (budget.calls !== undefined && stats.calls > budget.calls) ||
    (budget.waves !== undefined && stats.waves > budget.waves)
  );
}

function describeBudget(budget: DbBudget): string {
  return [
    budget.calls === undefined ? undefined : `${budget.calls} calls`,
    budget.waves === undefined ? undefined : `${budget.waves} waves`,
  ]
    .filter(Boolean)
    .join(" and ");
}

/** `calls;waves;ms`, the value of the debug header. */
export function formatStats(stats: DbStats): string {
  return `${stats.calls};${stats.waves};${stats.ms}`;
}
