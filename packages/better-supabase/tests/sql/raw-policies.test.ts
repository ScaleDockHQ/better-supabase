import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import baseline from "./raw-policies.baseline.json" with { type: "json" };

const MODULES = join(import.meta.dirname, "../../src/sql/modules");

function count(text: string): number {
  return text.split("create policy").length - 1;
}

/**
 * ADR 0103: block modules emit `Policy` values through `renderPolicy`. The
 * modules below still write `create policy` by hand; this ratchet lets that
 * backlog shrink and refuses new raw policies.
 */
describe("raw create policy in block modules", () => {
  const counts = new Map<string, number>();

  for (const file of readdirSync(MODULES)) {
    if (file.endsWith(".ts")) {
      const found = count(readFileSync(join(MODULES, file), "utf-8"));

      if (found > 0) {
        counts.set(file, found);
      }
    }
  }

  it("adds none and lowers the baseline as modules move to renderPolicy", () => {
    const allowed: Record<string, number> = baseline;
    const grew = [...counts].filter(([file, n]) => n > (allowed[file] ?? 0));
    const shrank = [...counts].filter(([file, n]) => n < (allowed[file] ?? 0));
    const gone = Object.keys(allowed).filter((file) => !counts.has(file));

    expect(grew, "raw create policy added, use renderPolicy").toEqual([]);
    expect(
      [...shrank.map(([file]) => file), ...gone],
      "lower the baseline",
    ).toEqual([]);
  });
});
