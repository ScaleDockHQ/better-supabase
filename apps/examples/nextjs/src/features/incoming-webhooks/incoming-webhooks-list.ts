import { defineAdminList } from "@/lib/admin-list";

/** `/settings/webhooks/incoming?q=&state=&verify=&sort=&after=`. */
export const incomingWebhookList = defineAdminList({
  facets: {
    state: ["enabled", "disabled"],
    verify: ["none", "standard-webhooks", "hmac-sha256", "shared-secret"],
  },
  sorts: ["newest", "oldest"],
  defaultSort: "newest",
  pageSize: 25,
});

/** One incoming endpoint as the overview and the list route send it. */
export interface IncomingWebhookRow {
  readonly id: string;
  readonly name: string;
  readonly verify: string;
  readonly enabled: boolean;
  readonly receiveCount: number;
  readonly lastReceivedAt: string | null;
  readonly lastStatus: number | null;
  readonly createdAt: string;
}
