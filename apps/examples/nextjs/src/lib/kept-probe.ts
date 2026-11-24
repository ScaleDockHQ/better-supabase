import type { KeptStore } from "better-supabase/server";

import * as v from "valibot";

/**
 * The kept-store half of the Vercel probe. The route runs it on
 * `vercelRuntimeCacheAdapter(getCache)` and `scripts/probe-vercel-tags.ts
 * --local` on `memoryKeptStore()`.
 */
export type ProbeStore = Pick<KeptStore, "expireTags" | "get" | "set">;

/** One id per module instance, so two requests show whether they met. */
const INSTANCE: string = crypto.randomUUID().slice(0, 8);

const VERSION_KEY = "bsb-probe:version";

export interface KeptWrite {
  readonly key: string;
  readonly instance: string;
  readonly ms: number;
}

export interface KeptRead {
  readonly key: string;
  readonly found: boolean;
  readonly writtenBy: string | null;
  readonly instance: string;
  readonly ms: number;
}

export interface Percentiles {
  readonly p50: number;
  readonly p95: number;
}

export interface Latency {
  readonly samples: number;
  readonly set: Percentiles;
  readonly hit: Percentiles;
  readonly miss: Percentiles;
}

export interface Burst {
  readonly calls: number;
  readonly windowMs: number;
  readonly accepted: number;
  readonly errors: readonly string[];
  readonly totalMs: number;
}

export interface VersionRead {
  /** The deployment that wrote the entry this request found, if any. */
  readonly previous: string | null;
  readonly current: string;
}

const message = (cause: unknown): string =>
  cause instanceof Error ? cause.message : String(cause);

const round = (ms: number): number => Math.round(ms * 100) / 100;

const Written = v.object({ instance: v.string() });
const Deployed = v.object({ deployment: v.string() });

const percentiles = (samples: readonly number[]): Percentiles => {
  const sorted = samples.toSorted((a, b) => a - b);

  const at = (share: number): number =>
    round(
      sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * share))] ??
        0,
    );

  return { p50: at(0.5), p95: at(0.95) };
};

const timed = async <T>(work: () => Promise<T>): Promise<[T, number]> => {
  const start = performance.now();

  const value = await work();

  return [value, performance.now() - start];
};

const sleep = (ms: number): Promise<void> =>
  new Promise((resolve) => {
    setTimeout(resolve, ms);
  });

/** Stores an entry another request can read with `keptRead`. */
export async function keptWrite(store: ProbeStore): Promise<KeptWrite> {
  const key = `bsb-probe:kept:${crypto.randomUUID()}`;

  const [, ms] = await timed(() =>
    store.set(
      key,
      { instance: INSTANCE },
      { tags: ["bsb:probe-kept"], ttl: 300 },
    ),
  );

  return { key, instance: INSTANCE, ms: round(ms) };
}

/** Reads an entry `keptWrite` stored, maybe on another instance. */
export async function keptRead(
  store: ProbeStore,
  key: string,
): Promise<KeptRead> {
  const [value, ms] = await timed(() => store.get(key));

  const written = v.safeParse(Written, value);

  return {
    key,
    found: written.success,
    writtenBy: written.success ? written.output.instance : null,
    instance: INSTANCE,
    ms: round(ms),
  };
}

/**
 * Reads the entry the previous deployment wrote under a fixed key, then writes
 * this deployment's id, so a run after a redeploy shows whether entries survive
 * it.
 */
export async function versionRead(
  store: ProbeStore,
  deployment: string,
): Promise<VersionRead> {
  const found = v.safeParse(Deployed, await store.get(VERSION_KEY));

  const previous = found.success ? found.output.deployment : null;

  await store.set(VERSION_KEY, { deployment }, { tags: [], ttl: 86_400 });

  return { previous, current: deployment };
}

/** `samples` set, hit and miss round trips, as p50 and p95 in milliseconds. */
export async function latency(
  store: ProbeStore,
  samples = 40,
): Promise<Latency> {
  const sets: number[] = [];
  const hits: number[] = [];
  const misses: number[] = [];

  for (let index = 0; index < samples; index += 1) {
    const key = `bsb-probe:latency:${crypto.randomUUID()}`;

    sets.push(
      (await timed(() => store.set(key, { index }, { tags: [], ttl: 60 })))[1],
    );
    hits.push((await timed(() => store.get(key)))[1]);
    misses.push((await timed(() => store.get(`${key}:missing`)))[1]);
  }

  return {
    samples,
    set: percentiles(sets),
    hit: percentiles(hits),
    miss: percentiles(misses),
  };
}

/**
 * Starts `calls` `expireTags` calls spread over `windowMs`, as a write burst
 * would, and counts the ones the store rejects.
 */
export async function burst(
  store: ProbeStore,
  calls = 250,
  windowMs = 1000,
): Promise<Burst> {
  const start = performance.now();
  const pending: Promise<string | null>[] = [];

  for (let index = 0; index < calls; index += 1) {
    pending.push(
      store.expireTags([`bsb:probe-burst-${String(index)}`]).then(
        () => null,
        (cause: unknown) => message(cause),
      ),
    );
    await sleep(windowMs / calls);
  }

  const results = await Promise.all(pending);

  const errors = results.filter((result): result is string => result !== null);

  return {
    calls,
    windowMs,
    accepted: calls - errors.length,
    errors: [...new Set(errors)],
    totalMs: round(performance.now() - start),
  };
}
