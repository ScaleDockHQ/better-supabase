/** Latency summary shared by the benchmark scripts in this folder. */
export interface Summary {
  readonly p50: number;
  readonly p95: number;
  readonly mean: number;
}

export function summarize(samples: readonly number[]): Summary {
  const sorted = samples.toSorted((a, b) => a - b);

  const at = (share: number): number =>
    sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * share))] ?? 0;

  return {
    p50: at(0.5),
    p95: at(0.95),
    mean: sorted.reduce((sum, value) => sum + value, 0) / sorted.length,
  };
}

export async function time(run: () => Promise<unknown>): Promise<number> {
  const start = performance.now();
  await run();

  return performance.now() - start;
}

export function format(label: string, summary: Summary): string {
  return `${label.padEnd(28)} p50 ${summary.p50.toFixed(1)} ms  p95 ${summary.p95.toFixed(1)} ms  mean ${summary.mean.toFixed(1)} ms`;
}
