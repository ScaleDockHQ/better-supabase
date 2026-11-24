import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import { AREAS, PRESET_AREA } from "@/features/areas/areas";

const SRC = join(process.cwd(), "src");

const sources = (dir: string): string[] =>
  readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);

    if (statSync(path).isDirectory()) {
      return sources(path);
    }

    return path.endsWith(".tsx") ? [path] : [];
  });

const FILES = sources(SRC).map((path) => ({
  path,
  text: readFileSync(path, "utf-8"),
}));

const count = (pattern: RegExp, only = FILES) =>
  only.reduce(
    (total, file) => total + (file.text.match(pattern)?.length ?? 0),
    0,
  );

// Ratchets: the numbers are today's, so they can go down and never up. A new
// page uses a skeleton fallback, leaves prefetching to the default viewport
// policy or turns it off, and keeps skeleton markup out of client modules.
describe("architecture guards", () => {
  it("never forces prefetch on a link (prefetch budget)", () => {
    expect(count(/prefetch=\{true\}/gu)).toBe(0);
    expect(count(/prefetch=\{false\}/gu)).toBeLessThanOrEqual(9);
  });

  it("keeps fallback={null} to the files that have it today", () => {
    const files = FILES.filter((file) => file.text.includes("fallback={null}"));

    expect(files.length).toBeLessThanOrEqual(34);
    expect(count(/fallback=\{null\}/gu)).toBeLessThanOrEqual(39);
  });

  it("defines skeletons in client modules no more than today", () => {
    const client = FILES.filter((file) => file.text.startsWith('"use client"'));

    expect(
      count(/export function [A-Za-z]*Skeleton/gu, client),
    ).toBeLessThanOrEqual(10);
  });

  it("gives every preset a product area and every area a preset", () => {
    const used = new Set<string>(Object.values(PRESET_AREA));

    for (const area of AREAS) {
      expect(used.has(area.id)).toBe(true);
    }
  });
});
