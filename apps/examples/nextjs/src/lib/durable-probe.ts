import type { RemoteCacheKey } from "better-supabase/next";

import "server-only";

import { bsbCore } from "@/lib/supabase/server-core";

/** Which `next start` process filled an entry, so a later build can tell. */
export interface Fill {
  readonly filledBy: string;
  readonly key: RemoteCacheKey | null;
}

const PROCESS = Symbol.for("bsb.durable-probe.process");

/** One id per server process; never an env var, which would join the key. */
export function processId(): string {
  // SAFETY: PROCESS is a registered symbol only this module writes.
  const scope = globalThis as { [PROCESS]?: string };

  scope[PROCESS] ??= crypto.randomUUID();

  return scope[PROCESS];
}

/** A `bsb.public()` read: its key is the arguments and Next's code hash. */
export async function publicRead(): Promise<Fill> {
  "use cache: remote";

  await bsbCore.public({ tables: ["customers"] });

  return { filledBy: processId(), key: null };
}

/**
 * A `bsb.remote()` read through `bsb.cached({ scope: "remote" })`: its key also
 * holds the `RemoteCacheKey`.
 */
export const remoteRead: () => Promise<Fill> = bsbCore.remote(
  async (key): Promise<Fill> => {
    "use cache: remote";

    await bsbCore.cached({ scope: "remote", key });

    return { filledBy: processId(), key };
  },
);

/**
 * A `bsb.kept()` read in the durable kept store. Its key holds the schema hash
 * and the library version, not the build, so a rebuild or an app code change
 * reads the entry an earlier process filled.
 */
export const keptRead = bsbCore.kept(
  (): Promise<Fill> => Promise.resolve({ filledBy: processId(), key: null }),
  {
    name: "durable-probe",
    tables: ["customers"],
    share: "public",
    life: { revalidate: 3600, expire: 86_400 },
  },
);
