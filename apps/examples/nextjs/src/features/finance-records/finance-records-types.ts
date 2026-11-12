/* oxlint-disable anti-slop/no-unsafe-dictionary-type -- the rows and records are the untyped jsonb of `api.finance_list` and `api.finance_detail`; each entity reads its own fields; 2 findings */
/** One row of a finance overview, as the list function sends it. */
export type FinanceRow = { readonly id: string } & Readonly<
  Record<string, unknown>
>;

/** One record with its child rows, as `api.finance_detail` sends it. */
export type FinanceRecord = Readonly<Record<string, unknown>>;
