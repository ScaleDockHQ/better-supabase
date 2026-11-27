import "server-only";
import type { Result } from "better-supabase";

import * as v from "valibot";

import { bsb } from "@/lib/supabase/server";
import { bsbCore } from "@/lib/supabase/server-core";

const versionValue = v.union([
  v.pipe(v.number(), v.finite()),
  v.pipe(v.string(), v.minLength(1), v.transform(Number), v.finite()),
]);

/**
 * A server that can read `api.caller_authz_version()` as the caller. `context`
 * is the request client: `cached()` would call `cacheLife` and throw outside a
 * `"use cache"` function. The version is not kept. The client uses it to skip
 * its own catch-up call, so a stale entry would hide a permission change.
 */
interface VersionClient {
  context(): Promise<{
    auth: { readonly kind: string };
    db: {
      readonly $executor: {
        rpc?(
          name: string,
          args: Readonly<Record<string, never>>,
          context: {
            readonly schema: string;
            readonly errorMappers: readonly [];
          },
        ): Promise<Result<unknown>>;
      };
    };
  }>;
}

async function readVersion(client: VersionClient): Promise<number | null> {
  const { auth, db } = await client.context();

  if (auth.kind !== "user") {
    return null;
  }

  const result = await db.$executor.rpc?.(
    "caller_authz_version",
    {},
    { schema: "api", errorMappers: [] },
  );

  if (result?.ok !== true) {
    return null;
  }

  const parsed = v.safeParse(versionValue, result.data);

  return parsed.success ? parsed.output : null;
}

/** The live authorization version for the app layout. */
export function liveAuthzVersion(): Promise<number | null> {
  return readVersion(bsb);
}

/** The live authorization version for the islands page, outside that layout. */
export function liveCoreAuthzVersion(): Promise<number | null> {
  return readVersion(bsbCore);
}
