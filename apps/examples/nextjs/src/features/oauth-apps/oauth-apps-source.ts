import "server-only";
import type {
  AdminListRaw,
  AdminListSource,
} from "@/features/admin-lists/admin-list-sql";

import type { OAuthAppRow } from "./oauth-apps-list";

interface OAuthAppRaw extends AdminListRaw {
  readonly name: string | null;
  readonly type: string;
  readonly registration: string;
  readonly redirect_uris: string;
  readonly created_at: string;
}

/**
 * OAuth apps: the rows the page reads as the database owner after its
 * permission check.
 */
export const oauthAppSource: AdminListSource<OAuthAppRaw, OAuthAppRow> = {
  from: "auth.oauth_clients c",
  idColumn: "c.id",
  idType: "uuid",
  timeColumn: "c.created_at",
  scope: "c.deleted_at is null and $1::text <> ''",
  search: ["c.client_name", "c.client_uri"],
  facetSql: {
    type: "c.client_type::text",
    registration: "c.registration_type::text",
  },
  select: `c.client_name as name, c.client_type::text as type, c.registration_type::text as registration,
    c.redirect_uris, c.created_at::text as created_at`,
  map: (raw) => ({
    id: raw.id,
    name: raw.name ?? raw.id,
    type: raw.type,
    registration: raw.registration,
    redirectUris: raw.redirect_uris,
    createdAt: raw.created_at,
  }),
};
