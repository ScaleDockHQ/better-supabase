import { defineAdminList } from "@/lib/admin-list";

/** `/settings/flags?q=state=&sort=&after=`. */
export const flagList = defineAdminList({
  facets: { state: ["on", "off", "archived"] },
  sorts: ["newest", "oldest"],
  defaultSort: "newest",
  pageSize: 25,
});

/** One row as the overview and the list route send it. */
export interface FlagRow {
  readonly id: string;
  readonly key: string;
  readonly description: string | null;
  readonly defaultVariant: string;
  readonly rollout: number | null;
  readonly state: "on" | "off" | "archived";
  readonly createdAt: string;
}
