import { performance } from "node:perf_hooks";
import { setTimeout as sleep } from "node:timers/promises";

import { Client } from "./client.ts";
import { connect, runsOf, unique } from "./db.ts";
import { startServer } from "./server.ts";

/** Output tokens one scripted turn produces; the model emits one token per word. */
const TOKENS = 200;

/** Milliseconds between tokens, so the stream is spread out like a real model's. */
const PACE_MS = 10;
const ROUNDS = 3;
const FLUSH_MS = [0, 20, 50, 100] as const;
const IDLE_MS = 3000;

const pool = connect();

async function counters(): Promise<{ rows: number; statements: number }> {
  await sleep(1500);

  const rows = await pool.query<{ n: string }>(
    "select coalesce(sum(n_tup_ins), 0) as n from pg_stat_user_tables where schemaname in ('workflow', 'pgmq')",
  );

  const statements = await pool.query<{ n: string }>(
    `select coalesce(sum(calls), 0) as n from pg_stat_statements
     where query ~* '(workflow|pgmq)' and query !~* 'pg_stat_'`,
  );

  return {
    rows: Number(rows.rows[0]?.n),
    statements: Number(statements.rows[0]?.n),
  };
}

function median(values: readonly number[]): number {
  const sorted = values.toSorted((a, b) => a - b);

  return sorted[Math.floor(sorted.length / 2)] ?? Number.NaN;
}

async function measure(flush: number): Promise<Record<string, number>> {
  const server = await startServer({
    command: "start",
    delivery: "poll",
    env: { WORKFLOW_POSTGRES_STREAM_FLUSH_INTERVAL_MS: String(flush) },
  });

  const client = new Client(server.url);
  const samples: Record<string, number[]> = {
    rows: [],
    statements: [],
    first: [],
    done: [],
    reconnect: [],
  };

  try {
    for (let round = 0; round < ROUNDS; round += 1) {
      const title = unique("hello");
      const id = await client.create(title);
      await client.waitFor(id, "turn.settled");

      const idleStart = await counters();
      await sleep(IDLE_MS);
      const idleEnd = await counters();
      const idleRate =
        (idleEnd.statements - idleStart.statements) / (IDLE_MS + 1500);

      const before = await counters();
      const tail = (await client.history(id)).tailIndex ?? 0;
      const sentAt = new Date();
      const sent = performance.now();
      await client.send(id, `words:${String(TOKENS)} pace:${String(PACE_MS)}`);
      const { times } = await client.follow(
        id,
        (event) => event.type === "turn.settled",
        tail + 1,
      );
      const finished = performance.now();
      const after = await counters();
      const elapsed = finished - sent + 1500;

      samples["first"]?.push((times[0] ?? finished) - sent);
      samples["done"]?.push(finished - sent);
      const runIds = (await runsOf(pool, id, title)).map((run) => run.id);

      const written = await pool.query<{ n: string }>(
        `select (select count(*) from workflow.workflow_events where run_id = any($1) and created_at >= $2)
              + (select count(*) from workflow.workflow_stream_chunks where run_id = any($1) and created_at >= $2) as n`,
        [runIds, sentAt],
      );

      samples["rows"]?.push((Number(written.rows[0]?.n) / TOKENS) * 1000);
      samples["statements"]?.push(
        ((after.statements - before.statements - idleRate * elapsed) / TOKENS) *
          1000,
      );

      const total = (await client.history(id)).tailIndex ?? 0;
      const reconnectStart = performance.now();
      await client.follow(id, () => true, Math.max(0, total - 20));
      samples["reconnect"]?.push(performance.now() - reconnectStart);
    }
  } finally {
    await server.stop();
  }

  return Object.fromEntries(
    Object.entries(samples).map(([key, values]) => [
      key,
      Math.round(median(values) * 10) / 10,
    ]),
  );
}

const results: Record<string, Record<string, number>> = {};

for (const flush of FLUSH_MS) {
  results[`flush ${String(flush)} ms`] = await measure(flush);
  console.log(
    `flush ${String(flush)} ms`,
    JSON.stringify(results[`flush ${String(flush)} ms`]),
  );
}

console.table(results);

console.log(
  "rows are exact for the session; statements come from pg_stat_statements on the shared database, so they include other clients (an upper bound). Both are per 1,000 output tokens; first, done and reconnect are milliseconds",
);

await pool.end();
