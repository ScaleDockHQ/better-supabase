import { defineBlockList } from "@/lib/block-status-list";

export const SESSION_STATUSES = [
  "open",
  "ready",
  "completed",
  "canceled",
] as const;

export const SESSION_PROTOCOLS = ["acp", "ucp"] as const;

/**
 * `/shop/checkout-sessions?status=&protocol=`. The agent-checkout block pages
 * sessions by keyset and filters by one status and one protocol, so a
 * multi-select facet makes one call per value and merges the answers.
 */
export const sessionList = defineBlockList({
  facets: [
    { key: "status", values: SESSION_STATUSES },
    { key: "protocol", values: SESSION_PROTOCOLS },
  ],
  sorts: ["newest"],
  defaultSort: "newest",
});

export const SESSION_PAGE_SIZE = 50;
