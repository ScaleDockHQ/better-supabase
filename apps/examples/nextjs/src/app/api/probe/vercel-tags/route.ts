import { getCache, invalidateByTag } from "@vercel/functions";
import { revalidateTag, updateTag } from "next/cache";

import { env } from "@/env";

type Expire = (tags: string[]) => Promise<void> | void;

interface Step {
  readonly method: string;
  readonly stored: boolean;
  readonly goneAtOnce: boolean;
  readonly goneAfter: number | null;
  readonly error: string | null;
}

const READ_AFTER_MS = [0, 250, 1000, 3000];

const sleep = (ms: number): Promise<void> =>
  new Promise((resolve) => {
    setTimeout(resolve, ms);
  });

const message = (cause: unknown): string =>
  cause instanceof Error ? cause.message : String(cause);

/**
 * Writes an entry to the Runtime Cache with one tag, expires the tag one way,
 * and reads the entry back until it is gone. `goneAfter` is the first read
 * delay, in milliseconds, at which it was gone.
 */
async function probe(method: string, expire: Expire): Promise<Step> {
  const cache = getCache({ namespace: "bsb-tag-probe" });
  const nonce = crypto.randomUUID();
  const key = `probe:${method}:${nonce}`;
  const tag = `bsb:probe-${method}-${nonce}`;

  await cache.set(key, { nonce }, { tags: [tag], ttl: 300 });
  const stored = (await cache.get(key)) !== undefined;

  try {
    await expire([tag]);
  } catch (cause) {
    return {
      method,
      stored,
      goneAtOnce: false,
      goneAfter: null,
      error: message(cause),
    };
  }

  let goneAfter: number | null = null;
  let waited = 0;

  for (const delay of READ_AFTER_MS) {
    await sleep(delay - waited);
    waited = delay;

    if ((await cache.get(key)) === undefined) {
      goneAfter = delay;
      break;
    }
  }

  return {
    method,
    stored,
    goneAtOnce: goneAfter === 0,
    goneAfter,
    error: null,
  };
}

/** Whether `expireTag` takes `count` tags in one call, and how it fails. */
async function limit(
  count: number,
): Promise<{ count: number; error: string | null }> {
  const tags = Array.from(
    { length: count },
    (_, index) => `bsb:probe-limit-${String(index)}`,
  );

  try {
    await getCache({ namespace: "bsb-tag-probe" }).expireTag(tags);

    return { count, error: null };
  } catch (cause) {
    return { count, error: message(cause) };
  }
}

/**
 * Answers how tag invalidation behaves on this deployment, for
 * scripts/probe-vercel-tags.ts. Needs `Authorization: Bearer
 * $BSB_TAG_PROBE_SECRET`; without the key, or with one shorter than 32
 * characters, the route does not exist.
 */
export async function POST(request: Request): Promise<Response> {
  const secret = env.BSB_TAG_PROBE_SECRET;

  if (!secret || secret.length < 32) {
    return new Response(null, { status: 404 });
  }

  if (request.headers.get("authorization") !== `Bearer ${secret}`) {
    return new Response(null, { status: 401 });
  }

  const steps = [
    await probe("updateTag", (tags) => {
      for (const tag of tags) {
        updateTag(tag);
      }
    }),
    await probe("revalidateTag", (tags) => {
      for (const tag of tags) {
        revalidateTag(tag, { expire: 0 });
      }
    }),
    await probe("expireTag", (tags) =>
      getCache({ namespace: "bsb-tag-probe" }).expireTag(tags),
    ),
    await probe("invalidateByTag", (tags) => invalidateByTag(tags)),
  ];

  const limits = await Promise.all([16, 64, 128, 129, 512].map(limit));

  const rejected = await getCache({ namespace: "bsb-tag-probe" })
    .expireTag("x".repeat(1024))
    .then(
      () => null,
      (cause: unknown) => message(cause),
    );

  return Response.json(
    {
      steps,
      limits,
      oversizedTag: { rejects: rejected !== null, error: rejected },
    },
    { headers: { "cache-control": "no-store" } },
  );
}
