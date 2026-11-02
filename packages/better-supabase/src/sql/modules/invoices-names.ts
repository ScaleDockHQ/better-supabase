import type { ExtraColumn } from "../context.ts";
import type { ApprovalNames } from "./invoices-approval.ts";
import type { CollectionNames } from "./invoices-collections.ts";
import type { EDeliveryNames } from "./invoices-e-delivery.ts";
import type { PurchaseNames } from "./invoices-purchase.ts";

export interface InvoiceNames
  extends PurchaseNames, CollectionNames, ApprovalNames, EDeliveryNames {
  readonly fn: (name: string) => string;
  readonly t: (table: string) => string;
  readonly c: (table: string, column: string) => string;
  readonly read: string;
  readonly write: string;
  readonly manage: string;
  readonly create: string;
  readonly update: string;
  readonly issue: string;
  readonly payment: string;
  readonly credit: string;
  readonly charge: string;
  readonly void: string;
  readonly writeOff: string;
  readonly reverse: string;
  readonly remove: string;
  readonly company: string;
  readonly contact: string;
  readonly prefix: string;
  readonly creditPrefix: string;
  /** Days from issue to due date by default. */
  readonly termsDays: number;
  readonly providerMethods: readonly string[];
  readonly service: string;
  /** `options.extraColumns`, which `create_invoice` writes by name. */
  readonly extras: readonly ExtraColumn[];
  readonly lineExtras: readonly ExtraColumn[];
  /**
   * `options.chargeExtraColumns`, which `add_invoice_charge` writes from
   * `fields`.
   */
  readonly chargeExtras: readonly ExtraColumn[];
  /** `options.totals: "app"`: the app keeps the totals, the block reads them. */
  readonly appTotals: boolean;
  /** `options.depositKind`: the kind value that marks a deposit invoice. */
  readonly depositKind: string | undefined;
  readonly depositLine: {
    readonly description: string;
    readonly fields: Readonly<Record<string, unknown>>;
  };
  readonly quoteLineValues: Readonly<
    Record<string, Readonly<Record<string, string>>>
  >;
}
