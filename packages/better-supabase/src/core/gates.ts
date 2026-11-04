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

  const answers = new Map<string, boolean>();
  const open = new Set<string>();
  let tenant: unknown;

  for (const [key, spec] of Object.entries(specs)) {
    const gate = spec.gate;

    if (gate === undefined) {
      open.add(key);
      continue;
    }

    let id = gate.id;

    if (id === undefined) {
      if (tenant === undefined) {
        const current = await rpc("current_tenant_id", {}, options);

        if (!current.ok) {
          return current;
        }

        tenant = current.data;
      }

      id = tenant;
    }

    const cacheKey = JSON.stringify([gate.scope, id, gate.permission]);
    let allowed = answers.get(cacheKey);

    if (allowed === undefined) {
      const called = await rpc(
        "can",
        { scope: gate.scope, scope_id: id, permission: gate.permission },
        options,
      );

      if (!called.ok) {
        return called;
      }

      allowed = called.data === true;
      answers.set(cacheKey, allowed);
    }

    if (allowed) {
      open.add(key);
    }
  }

  return ok(open);
}
