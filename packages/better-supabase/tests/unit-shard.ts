import { readFileSync } from "node:fs";
import * as v from "valibot";

const durationsSchema = v.record(v.string(), v.number());

/**
 * Splits files across CI shards by measured duration. Vitest's own shard hashes
 * the path and slices, so one shard can hold every slow file.
 */
export function assignShard<T>(
  files: readonly T[],
  idOf: (file: T) => string,
  durationsMs: ReadonlyMap<string, number>,
  index: number,
  count: number,
): T[] {
  if (count <= 1 || index < 1 || index > count) {
    return index === 1 ? [...files] : [];
  }

  const fallbackMs = median(durationsMs);

  const weighted = files
    .map((file) => {
      const id = idOf(file);

      return { file, id, durationMs: durationsMs.get(id) ?? fallbackMs };
    })
    .toSorted(
      (a, b) => b.durationMs - a.durationMs || a.id.localeCompare(b.id),
    );

  const bins: { totalMs: number; files: T[] }[] = Array.from(
    { length: count },
    () => ({ totalMs: 0, files: [] }),
  );

  for (const item of weighted) {
    let lightest = bins[0];

    if (lightest === undefined) {
      break;
    }

    for (const bin of bins) {
      if (bin.totalMs < lightest.totalMs) {
        lightest = bin;
      }
    }

    lightest.totalMs += item.durationMs;
    lightest.files.push(item.file);
  }

  return bins[index - 1]?.files ?? [];
}

/** Reads `{ "tests/foo.test.ts": 1200 }` as milliseconds per file. */
export function readDurations(path: string): Map<string, number> {
  const parsed = v.parse(
    durationsSchema,
    JSON.parse(readFileSync(path, "utf-8")),
  );

  return new Map(Object.entries(parsed));
}

function median(durationsMs: ReadonlyMap<string, number>): number {
  const values = [...durationsMs.values()].toSorted((a, b) => a - b);
  const mid = values[Math.floor((values.length - 1) / 2)];

  return mid ?? 0;
}
