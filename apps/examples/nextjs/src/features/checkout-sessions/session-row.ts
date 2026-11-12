/** One row of the checkout sessions overview. */
export interface SessionRow {
  readonly id: string;
  readonly protocol: "acp" | "ucp";
  readonly status: "open" | "ready" | "completed" | "canceled";
  readonly buyer: string | null;
  readonly orderId: string | null;
  readonly expired: boolean;
  readonly createdAt: string;
}
