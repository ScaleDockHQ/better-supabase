import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import { readAdminRows } from "@/features/admin-lists/admin-detail-read";
import { readPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { bsbShell } from "@/lib/supabase/server-shell";

export interface OAuthAppDetail {
  readonly id: string;
  readonly name: string;
  readonly type: string;
  readonly registration: string;
  readonly uri: string | null;
  readonly redirectUris: readonly string[];
  readonly grantTypes: readonly string[];
  readonly authMethod: string;
  readonly createdAt: string;
}

interface AppRaw {
  readonly id: string;
  readonly name: string | null;
  readonly type: string;
  readonly registration: string;
  readonly uri: string | null;
  readonly redirect_uris: string;
  readonly grant_types: string;
  readonly auth_method: string;
  readonly created_at: string;
}

const split = (value: string): readonly string[] =>
  value
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean);

/** `"forbidden"` without `settings.manage`, `null` when there is no such client. */
export async function getOAuthApp(
  id: string,
): Promise<OAuthAppDetail | "forbidden" | null> {
  "use cache: private";
  const request = await bsbShell.cached({ id });
  cacheTag("oauth-apps");
  const tenant = tenantOf(request.session);
  const permissions = await readPermissions(request);

  if (!tenant || !can(permissions, "settings.manage")) {
    return "forbidden";
  }

  const [row] = await readAdminRows<AppRaw>(
    request.session,
    `select c.id::text as id, c.client_name as name, c.client_type::text as type,
       c.registration_type::text as registration, c.client_uri as uri, c.redirect_uris,
       c.grant_types, c.token_endpoint_auth_method as auth_method, c.created_at::text as created_at
     from auth.oauth_clients c
     where c.id::text = $2 and c.deleted_at is null and $1::text <> ''`,
    [tenant, id],
  );

  if (!row) {
    return null;
  }

  return {
    id: row.id,
    name: row.name ?? row.id,
    type: row.type,
    registration: row.registration,
    uri: row.uri,
    redirectUris: split(row.redirect_uris),
    grantTypes: split(row.grant_types),
    authMethod: row.auth_method,
    createdAt: row.created_at,
  };
}
