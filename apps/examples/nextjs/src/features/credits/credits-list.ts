import { defineAdminList } from "@/lib/admin-list";

/** `/settings/billing/credits?q=&kind=&sort=&after=`. */
export const creditList = defineAdminList({
  facets: { kind: ["credit.grant", "credit.purchase", "credit.usage"] },
  sorts: ["newest", "oldest"],
  defaultSort: "newest",
  pageSize: 25,
});

/** One entry of the credit balance as the overview and the list route send it. */
export interface CreditEntryRow {
  readonly id: string;
  readonly transactionId: string;
  readonly kind: string;
  readonly memo: string | null;
  readonly amount: number;
  readonly reference: string | null;
  readonly effectiveAt: string;
}
