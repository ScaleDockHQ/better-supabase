import { defineAdminList } from "@/lib/admin-list";

/** `/settings/domains?q=&state=&kind=&sort=&after=`. */
export const domainList = defineAdminList({
  facets: { state: ["verified", "pending"], kind: ["custom", "subdomain"] },
  sorts: ["newest", "oldest"],
  defaultSort: "newest",
  pageSize: 25,
});

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
