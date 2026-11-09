import { AsyncResult, ok } from "better-supabase";

/**
 * Microseconds per chain of `map`, `andThen` and `orThrow`, in this process.
 * Machine-dependent, so gated loosely, and the ratio to a bare promise chain is
 * gated on its own.
 */
export interface RuntimeTimes {
  readonly promise: number;
  readonly asyncResult: number;
  readonly ratio: number;
}

const RUNTIME_CHAINS = 20_000;
const RUNTIME_ROUNDS = 5;

/** One chain: a value through two `map` steps, an `andThen` and a read. */
async function promiseChain(value: number): Promise<number> {
  const one = await Promise.resolve(value + 1);
  const two = one * 2;
  const three = await Promise.resolve(two + 3);

  return three;
}

function asyncResultChain(value: number): Promise<number> {
  return AsyncResult.ok(value)
    .map((n) => n + 1)
    .map((n) => n * 2)
    .andThen((n) => Promise.resolve(ok(n + 3)))
    .orThrow();
}

async function perChain(
  run: (value: number) => Promise<number>,
): Promise<number> {
  let best = Number.POSITIVE_INFINITY;

  for (let round = 0; round < RUNTIME_ROUNDS; round += 1) {
    const started = performance.now();

    for (let i = 0; i < RUNTIME_CHAINS; i += 1) {
      await run(i);
    }

    best = Math.min(best, performance.now() - started);
  }

  return Number(((best * 1000) / RUNTIME_CHAINS).toFixed(3));
}

export async function benchRuntime(): Promise<RuntimeTimes> {
  // One unmeasured round so both paths are compiled before the first timing.
  await perChain(promiseChain);
  await perChain(asyncResultChain);

  const promise = await perChain(promiseChain);
  const asyncResult = await perChain(asyncResultChain);

  return {
    promise,
    asyncResult,
    ratio: Number((asyncResult / promise).toFixed(2)),
  };
}

/** The failures: the time may double, and the ratio may grow by half. */
export function checkRuntime(
  now: RuntimeTimes,
  before: RuntimeTimes | undefined,
  speed: number,
): readonly string[] {
  if (!before) {
    return [
      "runtime has no baseline. Run `pnpm --filter @better-supabase/types-perf update`.",
    ];
  }

  const expected = before.asyncResult * speed;
  const limit = Math.max(expected * 2, expected + 5);
  const failures: string[] = [];

  if (now.asyncResult > limit) {
    failures.push(
      `runtime: an AsyncResult chain grew from ${expected.toFixed(2)}us to ${now.asyncResult.toFixed(2)}us (limit ${limit.toFixed(2)}us).`,
    );
  }

  if (now.ratio > before.ratio * 1.5 + 0.5) {
    failures.push(
      `runtime: AsyncResult costs ${String(now.ratio)}x a promise chain, up from ${String(before.ratio)}x.`,
    );
  }

  return failures;
}
