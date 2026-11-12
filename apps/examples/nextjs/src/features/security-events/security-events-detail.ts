import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { readAdminRows } from "@/features/admin-lists/admin-detail-read";
import { readPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { bsbShell } from "@/lib/supabase/server-shell";

export interface SecurityStreamDetail {
  readonly id: string;
  readonly receiver: string;
  readonly status: string;
  readonly delivery: "push" | "poll";
  readonly description: string | null;
  readonly audience: readonly string[];
  readonly requested: readonly string[];
  readonly delivered: readonly string[];
  readonly reason: string | null;
  readonly verifiedAt: string | null;
  readonly createdAt: string;
}

interface StreamRaw {
  readonly id: string;
  readonly receiver: string;
  readonly status: string;
  readonly delivery_method: string;
  readonly description: string | null;
  readonly audience: readonly string[];
  readonly events_requested: readonly string[];
  readonly events_delivered: readonly string[];
  readonly reason: string | null;
  readonly verified_at: string | null;
  readonly created_at: string;
}

/**
 * `"forbidden"` without `audit.read`, `null` when the stream is not in this
 * organization.
 */
export async function getSecurityStream(
  id: string,
): Promise<SecurityStreamDetail | "forbidden" | null> {
  "use cache: private";
  const request = await bsbShell.cached({ id });
  cacheTag("security-events");
  const tenant = tenantOf(request.session);
  const permissions = await readPermissions(request);

  if (!tenant || !can(permissions, "audit.read")) {
    return "forbidden";
  }

  const [row] = await readAdminRows<StreamRaw>(
    request.session,
    `select s.id::text as id, s.receiver, s.status, s.delivery_method, s.description, s.audience,
       s.events_requested, s.events_delivered, s.reason,
       s.verified_at::text as verified_at, s.created_at::text as created_at
     from better_supabase.ssf_streams s
     where s.id::text = $2 and (s.tenant is null or s.tenant = $1::text)`,
    [tenant, id],
  );

  if (!row) {
    return null;
  }

  return {
    id: row.id,
    receiver: row.receiver,
    status: row.status,
    delivery: row.delivery_method === "urn:ietf:rfc:8935" ? "push" : "poll",
    description: row.description,
    audience: row.audience,
    requested: row.events_requested,
    delivered: row.events_delivered,
    reason: row.reason,
    verifiedAt: row.verified_at,
    createdAt: row.created_at,
  };
}
