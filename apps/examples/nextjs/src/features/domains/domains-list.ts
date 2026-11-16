import type { EntityListMap } from "@/lib/block-entity-page";

import { defineBlockList } from "@/lib/block-list-url";

/** `/settings/domains?q=&verified=&kind=&sort=&after=`. */
export const domainList = defineBlockList({
  facets: ["verified", "kind"],
  sorts: ["newest", "oldest", "hostname"],
  defaultSort: "newest",
  pageSize: 25,
});

/** The list's URL names on the domains block's `page` and `facets`. */
export const domainMap: EntityListMap = {
  sorts: {
    newest: { by: "createdAt", direction: "desc" },
    oldest: { by: "createdAt", direction: "asc" },
    hostname: { by: "hostname" },
  },
};

/** One hostname as the overview and the list route send it. */
export interface DomainRow {
  readonly id: string;
  readonly hostname: string;
  readonly kind: "custom" | "subdomain";
  readonly verified: boolean;
  readonly primary: boolean;
  readonly createdAt: string;
  /** The TXT record to publish while the hostname is not verified. */
  readonly record: { readonly name: string; readonly value: string } | null;
}
