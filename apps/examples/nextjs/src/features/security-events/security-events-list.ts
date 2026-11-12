import { defineAdminList } from "@/lib/admin-list";

/** `/settings/security/events?q=status=&delivery=&sort=&after=`. */
export const securityStreamList = defineAdminList({
  facets: {
    status: ["enabled", "paused", "disabled"],
    delivery: ["push", "poll"],
  },
  sorts: ["newest", "oldest"],
  defaultSort: "newest",
  pageSize: 25,
});

/** One row as the overview and the list route send it. */
export interface SecurityStreamRow {
  readonly id: string;
  readonly receiver: string;
  readonly status: string;
  readonly delivery: "push" | "poll";
  readonly events: readonly string[];
  readonly verifiedAt: string | null;
  readonly createdAt: string;
}
