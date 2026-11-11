import "server-only";
import type { DbError } from "better-supabase";

import { tenantOf } from "better-supabase/next";
import * as v from "valibot";

import { getSession } from "@/features/user/user-queries";
import { bsbCore } from "@/lib/supabase/server-core";

import { aiProviders } from "./ai-providers-server";

/** `settings` is free-form JSON; the app only reads its `model`. */
const KeySettings = v.object({
  model: v.optional(v.string()),
  priority: v.optional(v.number()),
});

export interface ProviderKeyRow {
  readonly id: string;
  /** The AI Gateway's provider slug, such as `anthropic`. */
  readonly provider: string;
  readonly name: string;
  /** `settings.model`, the model the app calls with this key. */
  readonly model: string | undefined;
  /** Lower tries first; keys without one come after the ranked ones. */
  readonly priority: number | undefined;
  readonly enabled: boolean;
  /** ISO 8601. */
  readonly updatedAt: string;
}

/** A read that failed renders its error in the card, with a Retry. */
export type ProviderKeysRead =
  | { readonly ok: true; readonly keys: readonly ProviderKeyRow[] }
  | { readonly ok: false; readonly error: DbError };

/** The organization's provider keys, without their secrets. */
export async function getProviderKeys(): Promise<ProviderKeysRead> {
  const [session, { supabase }] = await Promise.all([
    getSession(),
    bsbCore.context(),
  ]);

  const organizationId = tenantOf(session);

  if (!organizationId) {
    return { ok: true, keys: [] };
  }

  const result = await aiProviders(supabase).keys.list(organizationId, {
    limit: 100,
  });

  if (!result.ok) {
    return { ok: false, error: result.error };
  }

  return {
    ok: true,
    keys: result.data.map((key) => {
      const settings = v.safeParse(KeySettings, key.settings);

      return {
        id: key.id,
        provider: key.provider,
        name: key.name,
        model: settings.success ? settings.output.model : undefined,
        priority: settings.success ? settings.output.priority : undefined,
        enabled: key.enabled,
        updatedAt: key.updatedAt.toString(),
      };
    }),
  };
}
