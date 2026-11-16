import { defineBlockList } from "@/lib/block-list-url";

/** `/settings/oauth-apps?q=type=&registration=&sort=&after=`. */
export const oauthAppList = defineBlockList({
  facets: ["type", "registration"],
  sorts: ["newest", "oldest"],
  defaultSort: "newest",
  pageSize: 25,
});

/** One row as the overview and the list route send it. */
export interface OAuthAppRow {
  readonly id: string;
  readonly name: string;
  readonly type: string;
  readonly registration: string;
  readonly redirectUris: string;
  readonly createdAt: string;
}
