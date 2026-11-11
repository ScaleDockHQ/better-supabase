/** One row of a finance overview, as the list function sends it. */
export type FinanceRow = { readonly id: string } & Readonly<
  Record<string, unknown>
>;

/** One record with its child rows, as `api.finance_detail` sends it. */
export type FinanceRecord = Readonly<Record<string, unknown>>;
