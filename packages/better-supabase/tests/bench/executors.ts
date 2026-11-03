/**
 * The same read as the same user through PostgREST and through
 * `better-supabase/postgres` over the connection string you pass (use the
 * Supavisor pooler to measure what a serverless function sees).
 *
 *     SUPABASE_URL=... SUPABASE_ANON_KEY=... SUPABASE_DB_URL=postgres://... \
 *       node tests/bench/executors.ts --jwt <access token> --user <sub> \
 *       [--table public.notes] [--runs 100]
 */
import { parseArgs } from "node:util";

import { keepAliveFetch } from "../../src/node/keep-alive.ts";
import { createPostgres } from "../../src/postgres/index.ts";
import { format, summarize, time } from "./stats.ts";

const url = process.env["SUPABASE_URL"];
const key = process.env["SUPABASE_ANON_KEY"];

const { values } = parseArgs({
  options: {
    jwt: { type: "string" },
    user: { type: "string" },
    table: { type: "string", default: "public.notes" },
    runs: { type: "string", default: "100" },
  },
});

const jwt = values.jwt;
const sub = values.user;
const { table } = values;
const runs = Number(values.runs);

if (!url || !key || !jwt || !sub) {
  console.error(
    "Set SUPABASE_URL and SUPABASE_ANON_KEY, and pass --jwt and --user.",
  );
  process.exit(1);
}

const [schema = "public", name = "notes"] = table.split(".");
const fetcher = keepAliveFetch({ connections: 4 });
const postgres = createPostgres({ max: 4 });
const user = postgres.asUser({ sub, role: "authenticated" });

const viaPostgrest = async (): Promise<void> => {
  const response = await fetcher(`${url}/rest/v1/${name}?limit=25`, {
    headers: {
      apikey: key,
      authorization: `Bearer ${jwt}`,
      "accept-profile": schema,
    },
  });

  await response.arrayBuffer();
};

const viaPostgres = async (): Promise<void> => {
  await user.queryRaw(`select * from "${schema}"."${name}" limit 25`, []);
};

async function measure(label: string, run: () => Promise<void>): Promise<void> {
  await run();

  const samples: number[] = [];

  for (let index = 0; index < runs; index += 1) {
    samples.push(await time(run));
  }

  console.log(format(label, summarize(samples)));
}

try {
  await measure("PostgREST", viaPostgrest);
  await measure("better-supabase/postgres", viaPostgres);
} finally {
  await postgres.end();
}
