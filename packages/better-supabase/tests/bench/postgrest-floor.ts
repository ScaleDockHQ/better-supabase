/**
 * The per-request floor of a project: the time PostgREST needs to answer `GET
 * /rest/v1/` (the OpenAPI root, no table work), from this machine, with the
 * global `fetch` and with `keepAliveFetch`. Subtract it from a read's time to
 * see what the query itself costs.
 *
 *     SUPABASE_URL=https://<ref>.supabase.co SUPABASE_ANON_KEY=... \
 *       node tests/bench/postgrest-floor.ts [runs]
 */
import { keepAliveFetch } from "../../src/node/keep-alive.ts";
import { format, summarize, time } from "./stats.ts";

const url = process.env["SUPABASE_URL"];
const key = process.env["SUPABASE_ANON_KEY"];
const runs = Number(process.argv[2] ?? 200);

if (!url || !key) {
  console.error("Set SUPABASE_URL and SUPABASE_ANON_KEY.");
  process.exit(1);
}

const headers = { apikey: key, authorization: `Bearer ${key}` };

async function measure(label: string, fetcher: typeof fetch): Promise<void> {
  // The first request opens the connection and is not the floor.
  await fetcher(`${url}/rest/v1/`, { headers }).then((r) => r.arrayBuffer());

  const samples: number[] = [];

  for (let index = 0; index < runs; index += 1) {
    samples.push(
      await time(async () => {
        const response = await fetcher(`${url}/rest/v1/`, { headers });
        await response.arrayBuffer();
      }),
    );
  }

  console.log(format(label, summarize(samples)));
}

await measure("global fetch", fetch);

await measure("keepAliveFetch", keepAliveFetch({ connections: 4 }));
