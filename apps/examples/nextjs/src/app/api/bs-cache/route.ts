import { connection } from "next/server";
import * as v from "valibot";

import { env } from "@/env";

/** The global `cache-handlers/counting.ts` writes the counters to. */
interface CounterHolder {
  bsbRemoteCacheCounters?: unknown;
}

// SAFETY: the property is optional and read through `v.safeParse`.
const holder = globalThis as CounterHolder;

const Counters = v.object({
  gets: v.number(),
  hits: v.number(),
  sets: v.number(),
  bytesSet: v.number(),
  bytesRead: v.number(),
  updateTags: v.number(),
  expiredTags: v.array(v.string()),
});

const EMPTY = {
  gets: 0,
  hits: 0,
  sets: 0,
  bytesSet: 0,
  bytesRead: 0,
  updateTags: 0,
  expiredTags: [],
};

/**
 * What Next.js asked of the `"use cache: remote"` handler since the last
 * `?reset=1`, in a testing build only (`cache-handlers/counting.ts` writes the
 * counters). `tests/cache.spec.ts` reads them around a page load.
 */
export async function GET(request: Request): Promise<Response> {
  // The counters change on every call, so the handler must never be prerendered.
  await connection();

  if (env.EXPOSE_TESTING_API !== "1") {
    return Response.json(
      { error: "debug is off" },
      { status: 404, headers: { "cache-control": "no-store" } },
    );
  }

  const found = v.safeParse(Counters, holder.bsbRemoteCacheCounters);
  const counters = found.success ? found.output : EMPTY;

  if (new URL(request.url).searchParams.get("reset") === "1") {
    delete holder.bsbRemoteCacheCounters;
  }

  return Response.json(counters, { headers: { "cache-control": "no-store" } });
}
