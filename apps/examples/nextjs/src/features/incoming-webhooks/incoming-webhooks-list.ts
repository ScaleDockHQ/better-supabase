import { defineBlockList } from "@/lib/block-list-url";

/** `/settings/webhooks/incoming?q=&state=&verify=&sort=&after=`. */
export const incomingWebhookList = defineBlockList({
  facets: ["state", "verify"],
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
