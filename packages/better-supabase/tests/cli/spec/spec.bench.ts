/**
 * What `better-supabase spec` costs per output: a cold render, a cache
 * hit, a render checked against the official schema, and every OpenAPI
 * version at once. Run with `pnpm --filter better-supabase bench`.
 */
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import type { SpecEntry } from "../../../src/cli/spec/entry.ts";
import type { SpecTarget } from "../../../src/cli/spec/targets.ts";

import { formatRegistry } from "../../../src/cli/spec/formats.ts";
import { renderTarget } from "../../../src/cli/spec/render.ts";
import { resolveTargets } from "../../../src/cli/spec/targets.ts";
import { defineSupabase } from "../../../src/core/define.ts";
import { defineApi } from "../../../src/spec/api.ts";
import { schema } from "../../fixtures/generated-camel.ts";

const RUNS = 200;

/** Generous on purpose: the gate catches work that scales wrongly, not noise. */
const MAX_RATIO = 6;

const api = defineApi(defineSupabase(schema), {
  info: { title: "CRM", version: "1.0.0" },
  resources: Object.fromEntries(
    Object.keys(schema.meta.tables).map((table) => [table, true]),
  ),
});

const entry: SpecEntry = { api, documents: new Map(), formats: [] };
const registry = formatRegistry();

const targetsFor = (versions: readonly string[]): readonly SpecTarget[] =>
  resolveTargets(
    versions.map((version) => ({
      format: "openapi",
      version,
      output: `openapi-${version}.json`,
    })),
    registry,
    {},
  );

const [single] = targetsFor(["3.1"]);

if (!single) {
  throw new Error("No OpenAPI 3.1 target");
}

const every = targetsFor(["3.0", "3.1", "3.2"]);

const root = await mkdtemp(join(tmpdir(), "better-supabase-spec-bench-"));

async function measure(
  work: () => Promise<unknown>,
  runs = RUNS,
): Promise<number> {
  for (let warm = 0; warm < 20; warm++) {
    await work();
  }

  const started = performance.now();

  for (let run = 0; run < runs; run++) {
    await work();
  }

  return (performance.now() - started) / runs;
}

try {
  const cold = { root, entry, cache: false, validate: false };
  const cached = { ...cold, cache: true };

  const timings = {
    "render ms": await measure(() => renderTarget(single, cold)),
    "cache hit ms": await measure(() => renderTarget(single, cached)),
    "render and validate ms": await measure(
      () => renderTarget(single, { ...cold, validate: true }),
      50,
    ),
    "3 versions at once ms": await measure(() =>
      Promise.all(every.map((target) => renderTarget(target, cold))),
    ),
  };

  console.table(
    Object.fromEntries(
      Object.entries(timings).map(([label, value]) => [
        label,
        value.toFixed(2),
      ]),
    ),
  );

  const gates: readonly [string, number, number, number][] = [
    // A hit hashes the model and reads one file instead of rendering and validating.
    [
      "a cache hit against a validated render",
      timings["cache hit ms"],
      timings["render and validate ms"],
      1,
    ],
    [
      "validating against rendering",
      timings["render and validate ms"],
      timings["render ms"],
      MAX_RATIO,
    ],
    // Three renders in one batch; more means the versions block each other.
    [
      "three versions against one",
      timings["3 versions at once ms"],
      timings["render ms"],
      MAX_RATIO,
    ],
  ];

  for (const [label, slow, base, limit] of gates) {
    const ratio = slow / base;
    console.log(`${label}: ${ratio.toFixed(2)}x`);

    if (ratio > limit) {
      console.error(
        `${label} costs ${ratio.toFixed(1)}x its baseline (limit ${String(limit)}x).`,
      );
      process.exitCode = 1;
    }
  }
} finally {
  await rm(root, { recursive: true, force: true });
}
