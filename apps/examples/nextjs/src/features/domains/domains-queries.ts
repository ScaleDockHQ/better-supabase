import "server-only";
import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";

import type {
  RecordListPage,
  RecordListUrlQuery,
} from "@/components/record-list/record-list-types";

import { readPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { pageEntityRows } from "@/lib/block-entity-page";
import { bsb } from "@/lib/supabase/server";

import type { DomainRow } from "./domains-list";

import { DOMAINS_TAG } from "./domains-cache";
import { domainList, domainMap } from "./domains-list";

type Db = Awaited<ReturnType<typeof bsb.cached>>["db"];

/**
 * One page of the organization's hostnames for a list query, searched, filtered
 * and sorted by the domains block's `page` and counted by `facets`.
 */
export function getDomainPage(
  db: Db,
  organizationId: string,
  { q: _search, ...query }: RecordListUrlQuery,
): Promise<RecordListPage<DomainRow>> {
  // The hostname list has no text search, so a `q` in the URL is ignored.
  return pageEntityRows({
    pager: {
      page: (options) => db.domains.page({ organizationId, ...options }),
      facets: (options) => db.domains.facets({ organizationId, ...options }),
    },
    map: domainMap,
    query,
    pageSize: domainList.config.pageSize,
    rowsOf: (hostnames) =>
      hostnames.map((hostname): DomainRow => ({
        id: hostname.id,
        hostname: hostname.hostname,
        kind: hostname.kind,
        verified: hostname.verifiedAt !== undefined,
        primary: hostname.primary,
        createdAt: hostname.createdAt.toString(),
        record: hostname.record
          ? { name: hostname.record.name, value: hostname.record.value }
          : null,
      })),
  });
}

/**
 * The first page of the organization's hostnames with the count per state and
 * kind. `null` without an organization or `domains.read`. The page doesn't read
 * `searchParams`, so it stays in the instant App Shell; filtered pages go
 * through `/api/domains/list`.
 */
export async function getDomains() {
  "use cache: private";
  const request = await bsb.cached();
  cacheTag(DOMAINS_TAG);
  const tenant = tenantOf(request.session);
  const permissions = await readPermissions(request);

  if (!tenant || !can(permissions, "domains.read")) {
    return null;
  }

  return getDomainPage(request.db, tenant, domainList.defaults);
}
