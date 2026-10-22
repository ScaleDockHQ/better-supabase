import "server-only";
import { tenantOf } from "better-supabase/next";
import * as v from "valibot";

import { postgres, userClaims } from "@/features/developer/postgres";
import { bsb } from "@/lib/supabase/server";

import type { WebhookDeliveryRow, WebhookEndpointRow } from "./webhook-types";

import { WebhookStatus } from "./webhook-types";

interface EndpointRecord {
  readonly id: string;
  readonly name: string;
  readonly url: string;
  readonly enabled: boolean;
  readonly event_types: readonly string[];
  readonly failing_since: Date | null;
  readonly disabled_reason: string | null;
  readonly created_at: Date;
}

interface DeliveryRecord {
  readonly id: string;
  readonly endpoint_name: string;
  readonly event_type: string;
  readonly status: string;
  readonly attempt: number;
  readonly response_status: number | null;
  readonly last_error: string | null;
  readonly created_at: Date;
}

export interface WebhooksOverview {
  readonly endpoints: readonly WebhookEndpointRow[];
  readonly deliveries: readonly WebhookDeliveryRow[];
}

/**
 * The organization's endpoints and its 20 latest deliveries. The tables are not
 * on the Data API, so this reads them over Postgres as the caller: RLS lets
 * members with `webhooks.read` see them. A failed read throws, so it is never
 * cached and Retry reads again. `null` without an organization.
 */
export async function loadWebhooks(): Promise<WebhooksOverview | null> {
  "use cache: private";
  const { session } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const connection = postgres();
  const claims = userClaims(session);

  if (!connection || !claims) {
    throw new Error("The webhooks page needs a database URL and a user");
  }

  const sql = connection.asUser(claims);

  const [endpoints, deliveries] = await Promise.all([
    sql.queryRaw<EndpointRecord>(
      `select id, name, url, enabled, event_types, failing_since, disabled_reason, created_at
       from better_supabase.webhook_endpoints
       where organization_id = $1
       order by created_at desc`,
      [tenant],
    ),
    sql.queryRaw<DeliveryRecord>(
      `select d.id, e.name as endpoint_name, d.event_type, d.status, d.attempt,
              d.response_status, d.last_error, d.created_at
       from better_supabase.webhook_deliveries d
       join better_supabase.webhook_endpoints e on e.id = d.endpoint_id
       where d.organization_id = $1
       order by d.created_at desc
       limit 20`,
      [tenant],
    ),
  ]);

  return {
    endpoints: endpoints.map((row) => ({
      id: row.id,
      name: row.name,
      url: row.url,
      enabled: row.enabled,
      eventTypes: row.event_types,
      failingSince: row.failing_since?.toISOString() ?? null,
      disabledReason: row.disabled_reason,
      createdAt: row.created_at.toISOString(),
    })),
    deliveries: deliveries.map((row) => ({
      id: row.id,
      endpointName: row.endpoint_name,
      eventType: row.event_type,
      status: v.parse(WebhookStatus, row.status),
      attempt: row.attempt,
      responseStatus: row.response_status,
      lastError: row.last_error,
      createdAt: row.created_at.toISOString(),
    })),
  };
}
