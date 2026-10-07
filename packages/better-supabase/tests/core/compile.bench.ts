/**
 * The per-call work the plugin bench skips: compiling an operation to a
 * PostgREST plan, decoding rows with codecs, and running a list query.
 * Run with `pnpm --filter better-supabase bench`.
 */
import type { Executor } from "../../src/core/executor.ts";
import type { Operation, Selection } from "../../src/ir/types.ts";

import { compilePostgrest } from "../../src/compile/postgrest.ts";
import { defineSupabase } from "../../src/core/define.ts";
import { ok } from "../../src/core/result.ts";
import { decodeRows } from "../../src/ir/codec.ts";
import { defineListQuery } from "../../src/list/list-query.ts";
import { schema } from "../fixtures/generated-camel.ts";

const RUNS = 20_000;
/**
 * Each pair may differ by at most this factor. Generous on purpose: the
 * gate catches work that starts scaling with the input, not noise.
 */
const MAX_RATIO = 15;

const ORG = "00000000-0000-4000-8000-000000000001";
const rows = Array.from({ length: 50 }, (_, i) => ({
  id: `c${String(i)}`,
  name: "Acme",
  organizationId: ORG,
  status: "active",
}));
let captured: Operation | undefined;
const executor: Executor = {
  name: "instant",
  execute: (op) => {
    captured = op;
    return Promise.resolve(ok({ rows, count: rows.length }));
  },
};
const betterSupabase = defineSupabase(schema);
const db = betterSupabase.connect(executor);

async function opOf(run: () => PromiseLike<unknown>): Promise<Operation> {
  await run();
  if (!captured) throw new Error("No operation captured");
  return captured;
}

function measure(work: () => unknown): number {
  for (let warm = 0; warm < 2000; warm++) work();
  const started = performance.now();
  for (let run = 0; run < RUNS; run++) work();
  return ((performance.now() - started) / RUNS) * 1000;
}

async function measureAsync(work: () => PromiseLike<unknown>): Promise<number> {
  for (let warm = 0; warm < 2000; warm++) await work();
  const started = performance.now();
  for (let run = 0; run < RUNS; run++) await work();
  return ((performance.now() - started) / RUNS) * 1000;
}

const simple = await opOf(() => db.customers.findMany({ select: ["id"] }));
const complex = await opOf(() =>
  db.customers.findMany({
    select: ["id", "name", "status", "createdAt"],
    where: {
      organizationId: ORG,
      status: { in: ["lead", "active"] },
      name: { contains: "acme" },
      OR: [{ kvk: null }, { kvk: { startsWith: "10" } }],
    },
    include: { notes: { select: ["id", "body"], limit: 3 } },
    orderBy: [{ createdAt: "desc" }, { id: "asc" }],
  }),
);

const coded: Selection = {
  columns: [
    { alias: "id", column: "id" },
    { alias: "total", column: "total", codec: "bigint" },
  ],
  includes: [],
};
const wire = Array.from({ length: 200 }, (_, i) => ({
  id: `r${String(i)}`,
  total: String(9_007_199_254_740_993n + BigInt(i)),
}));

const list = defineListQuery(betterSupabase, "customers", {
  search: ["name"],
  facets: { status: "status" },
  sorts: { name: [{ name: "asc" }, { id: "asc" }] },
  defaultSort: "name",
});
const query = list.parse(new URLSearchParams("q=acme&status=active")).value!;

const timings = {
  "compile simple µs": measure(() => compilePostgrest(simple)),
  "compile complex µs": measure(() => compilePostgrest(complex)),
  "decode 20 rows µs": measure(() => decodeRows(coded, wire.slice(0, 20))),
  "decode 200 rows µs": measure(() => decodeRows(coded, wire)),
  "paginate µs": await measureAsync(() =>
    db.customers.paginate({ ...list.args(query) }),
  ),
  "list run µs": await measureAsync(() => list.run(db, query)),
};
console.table(
  Object.fromEntries(
    Object.entries(timings).map(([label, value]) => [label, value.toFixed(2)]),
  ),
);

const gates: readonly [string, number, number][] = [
  [
    "compiling a filtered read with an include",
    timings["compile complex µs"],
    timings["compile simple µs"],
  ],
  // Linear decoding makes this 10x; more means per-row work grew.
  [
    "decoding 200 rows against 20",
    timings["decode 200 rows µs"],
    timings["decode 20 rows µs"],
  ],
  ["running a list", timings["list run µs"], timings["paginate µs"]],
];
for (const [label, slow, base] of gates) {
  const ratio = slow / base;
  console.log(`${label}: ${ratio.toFixed(1)}x`);
  if (ratio > MAX_RATIO) {
    console.error(
      `${label} costs ${ratio.toFixed(1)}x its baseline (limit ${String(MAX_RATIO)}x).`,
    );
    process.exitCode = 1;
  }
}
