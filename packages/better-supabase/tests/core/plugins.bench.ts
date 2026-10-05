/**
 * What plugins add to `connect()` and `findMany` on an executor that answers
 * at once, with 0, 3 and 6 plugins installed.
 * Run with `pnpm --filter better-supabase bench`.
 */
import type { Executor } from "../../src/core/executor.ts";
import type { AnyPlugin } from "../../src/core/plugin.ts";

import { defineSupabase } from "../../src/core/define.ts";
import { definePlugin } from "../../src/core/plugin.ts";
import { ok } from "../../src/core/result.ts";
import { actor } from "../../src/plugins/actor/index.ts";
import { recommended, rules } from "../../src/plugins/rules/index.ts";
import { softDelete } from "../../src/plugins/soft-delete/index.ts";
import { tenant } from "../../src/plugins/tenant/index.ts";
import { timestamps } from "../../src/plugins/timestamps/index.ts";
import { schema } from "../fixtures/generated-camel.ts";

const ORG = "00000000-0000-4000-8000-000000000001";
const RUNS = 20_000;
/**
 * Six plugins may cost at most this many times the bare call. Generous on
 * purpose: the run is noisy, and the gate exists to catch a hook that starts
 * doing per-call work it should do once.
 */
const MAX_RATIO = 6;

const rows = Array.from({ length: 20 }, (_, i) => ({
  id: `c${String(i)}`,
  name: "Acme",
  organizationId: ORG,
}));
const executor: Executor = {
  name: "instant",
  execute: () => Promise.resolve(ok({ rows, count: null })),
};
const traced = definePlugin({
  name: "traced",
  wrapExecutor: (inner) => ({
    name: "traced",
    execute: (op, context) => inner.execute(op, context),
  }),
});

const SETS: Readonly<Record<string, readonly AnyPlugin[]>> = {
  "0 plugins": [],
  "3 plugins": [timestamps(), softDelete(), tenant()],
  "6 plugins": [
    timestamps(),
    softDelete(),
    tenant(),
    actor(),
    rules({ rules: recommended(), report: () => {} }),
    traced,
  ],
};
const context = { claims: { sub: "u1", org_id: ORG }, tenant: ORG };

async function measure(work: () => Promise<unknown>): Promise<number> {
  for (let warm = 0; warm < 2000; warm++) await work();
  const started = performance.now();
  for (let run = 0; run < RUNS; run++) await work();
  return ((performance.now() - started) / RUNS) * 1000;
}

const results: Record<string, { "connect µs": string; "findMany µs": string }> =
  {};
const findMany: Record<string, number> = {};
for (const [label, plugins] of Object.entries(SETS)) {
  let betterSupabase = defineSupabase(schema);
  for (const plugin of plugins) betterSupabase = betterSupabase.use(plugin);
  const db = betterSupabase.connect(executor, context);
  const connect = await measure(() =>
    Promise.resolve(betterSupabase.connect(executor, context)),
  );
  const read = await measure(() => db.customers.findMany({ limit: 20 }));
  findMany[label] = read;
  results[label] = {
    "connect µs": connect.toFixed(2),
    "findMany µs": read.toFixed(2),
  };
}
console.table(results);

const ratio = findMany["6 plugins"]! / findMany["0 plugins"]!;
console.log(`6 plugins: ${ratio.toFixed(1)}x the bare findMany`);
if (ratio > MAX_RATIO) {
  console.error(
    `findMany with 6 plugins costs ${ratio.toFixed(1)}x the bare call (limit ${String(MAX_RATIO)}x).`,
  );
  process.exitCode = 1;
}
