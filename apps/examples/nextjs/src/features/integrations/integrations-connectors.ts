import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { readAdminRows } from "@/features/admin-lists/admin-detail-read";
import { readPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { bsbShell } from "@/lib/supabase/server-shell";

export interface ConnectorSummary {
  readonly id: string;
  readonly name: string;
  readonly url: string;
  readonly transport: string;
  readonly enabled: boolean;
}

export interface ConnectorDetail extends ConnectorSummary {
  readonly authType: string;
  readonly scopes: readonly string[];
  readonly grants: number;
  readonly createdAt: string;
}

interface SummaryRaw {
  readonly id: string;
  readonly name: string;
  readonly url: string;
  readonly transport: string;
  readonly enabled: boolean;
}

interface DetailRaw extends SummaryRaw {
  readonly auth_type: string;
  readonly scopes: readonly string[];
  readonly grants: string;
  readonly created_at: string;
}

export const CONNECTORS_TAG = "connectors";

/** The organization's connector servers; `null` without `connectors.read`. */
export async function getConnectors(): Promise<
  readonly ConnectorSummary[] | null
> {
  "use cache: private";
  const request = await bsbShell.cached();
  cacheTag(CONNECTORS_TAG);
  const tenant = tenantOf(request.session);
  const permissions = await readPermissions(request);

  if (!tenant || !can(permissions, "connectors.read")) {
    return null;
  }

  return readAdminRows<SummaryRaw>(
    request.session,
    `select s.id::text as id, s.name, s.url, s.transport, s.enabled
     from better_supabase.connector_servers s
     where s.tenant_id::text = $1
     order by s.created_at desc, s.id desc
     limit 50`,
    [tenant],
  );
}

/** One connector server; `"forbidden"` without `connectors.read`. */
export async function getConnector(
  id: string,
): Promise<ConnectorDetail | "forbidden" | null> {
  "use cache: private";
  const request = await bsbShell.cached({ id });
  cacheTag(CONNECTORS_TAG);
  const tenant = tenantOf(request.session);
  const permissions = await readPermissions(request);

  if (!tenant || !can(permissions, "connectors.read")) {
    return "forbidden";
  }

  const [row] = await readAdminRows<DetailRaw>(
    request.session,
    `select s.id::text as id, s.name, s.url, s.transport, s.enabled, s.auth_type, s.scopes,
       (select count(*) from better_supabase.connector_grants g
         where g.server_id = s.id and g.revoked_at is null)::text as grants,
       s.created_at::text as created_at
     from better_supabase.connector_servers s
     where s.id::text = $2 and s.tenant_id::text = $1`,
    [tenant, id],
  );

  if (!row) {
    return null;
  }

  return {
    id: row.id,
    name: row.name,
    url: row.url,
    transport: row.transport,
    enabled: row.enabled,
    authType: row.auth_type,
    scopes: row.scopes,
    grants: Number(row.grants),
    createdAt: row.created_at,
  };
}
