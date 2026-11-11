import type { AsyncResult, Result } from "./result.ts";
import type { ReadSetEntry } from "./spec.ts";

import { ok } from "./result.ts";

/**
 * The `$rpc` a connection offers, which gates call `better_supabase.can`
 * through.
 */
export type GateRpc = (
  name: string,
  args: Readonly<Record<string, unknown>>,
  options?: { signal?: AbortSignal; schema?: string },
) => AsyncResult<unknown>;

/**
 * The keys of the read set entries that run: those without a gate, and those
 * whose gate the caller passes. Checks each distinct gate once, through the
 * same `better_supabase.can` the read set function calls.
 */
export async function openGates(
  rpc: GateRpc,
  specs: Readonly<Record<string, ReadSetEntry>>,
  signal: AbortSignal | undefined,
): Promise<Result<ReadonlySet<string>>> {
  const options = { schema: "better_supabase", ...(signal ? { signal } : {}) };

  const entries = Object.entries(specs);

  const needsTenant = entries.some(
    ([, spec]) => spec.gate !== undefined && spec.gate.id === undefined,
  );

  let tenant: unknown;

  if (needsTenant) {
    const current = await rpc("current_tenant_id", {}, options);

    if (!current.ok) {
      return current;
    }

    tenant = current.data;
  }

  // Each distinct gate is asked once, and all of them in the same wave.
  const pending = new Map<string, ReturnType<GateRpc>>();
  const cacheKeys = new Map<string, string>();

  for (const [key, spec] of entries) {
    const gate = spec.gate;

    if (gate === undefined) {
      continue;
    }

    const id = gate.id ?? tenant;
    const cacheKey = JSON.stringify([gate.scope, id, gate.permission]);

    cacheKeys.set(key, cacheKey);

    if (!pending.has(cacheKey)) {
      pending.set(
        cacheKey,
        rpc(
          "can",
          { scope: gate.scope, scope_id: id, permission: gate.permission },
          options,
        ),
      );
    }
  }

  const answers = new Map<string, boolean>();

  for (const [cacheKey, call] of pending) {
    const called = await call;

    if (!called.ok) {
      return called;
    }

    answers.set(cacheKey, called.data === true);
  }

  const open = new Set<string>();

  for (const [key, spec] of entries) {
    const cacheKey = cacheKeys.get(key);

    if (spec.gate === undefined || answers.get(cacheKey ?? "") === true) {
      open.add(key);
    }
  }

  return ok(open);
}
