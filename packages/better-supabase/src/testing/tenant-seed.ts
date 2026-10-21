import type { EventHub } from "../core/events.ts";
import type { SqlClient } from "../postgres/executor.ts";
import type { TenantSeed } from "./seed.ts";

import { organizationsEvents } from "../blocks/organizations/events.ts";
import { onBlockEvent } from "../core/block-events.ts";

export interface SeedTenantOnCreateOptions {
  /** A service-role client the seed inserts through. */
  readonly sql: SqlClient;
  /** Defaults to `NODE_ENV === 'development'`. */
  readonly enabled?: boolean;
  /** Called when the seed fails. Defaults to `console.error`. */
  readonly onError?: (error: unknown, organizationId: string) => void;
}

const development = (): boolean => process.env["NODE_ENV"] === "development";

/**
 * Applies `seed` to each organization created through the organizations block,
 * so a new tenant starts with demo data in development. The seed runs after the
 * event and can never change the result of the create call. Returns a function
 * that stops listening.
 *
 * ```ts
 * seedTenantOnCreate(betterSupabase, tenantSeed, { sql: serviceSql });
 * ```
 */
export function seedTenantOnCreate(
  betterSupabase: { readonly events: EventHub },
  seed: TenantSeed,
  options: SeedTenantOnCreateOptions,
): () => void {
  if (!(options.enabled ?? development())) {
    return () => {};
  }

  const report =
    options.onError ??
    ((error: unknown, organizationId: string): void => {
      console.error(
        `better-supabase: the tenant seed failed for ${organizationId}`,
        error,
      );
    });

  return onBlockEvent(
    betterSupabase,
    organizationsEvents,
    "organization.created",
    (event) => {
      const id = event.data.organizationId;

      void seed.insert(options.sql, { id }).catch((error: unknown) => {
        report(error, id);
      });
    },
  );
}
