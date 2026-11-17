/**
 * The English MessageFormat text of every memo key a block writes next to a
 * ledger transaction's or accounting entry's `memo`. The values come from
 * `memoParams`; the stored `memo` is this text with them filled in.
 */
export const BLOCK_MEMO_MESSAGES: Readonly<Record<string, string>> = {
  "accounting.asset_depreciation": "Depreciation of {asset} for {periodStart}",
  "accounting.asset_disposal": "Disposal of {asset}",
  "accounting.expense_reimbursement": "Reimbursed: {title}",
  "accounting.expense_report": "Expenses: {title}",
  "accounting.gift": "Gift",
  "accounting.invoice_charge": "Charge on {invoice}",
  "accounting.invoice_discount": "Early payment discount on {invoice}",
  "accounting.invoice_party_payment": "Payment on account",
  "accounting.invoice_payment": "Payment of {invoice}",
  "accounting.invoice_write_off": "Write-off of {invoice}",
  "accounting.lease_payment": "Rent payment: {lease}",
  "accounting.lease_rent": "Rent from {periodStart}: {lease}",
  "accounting.opening_balances": "Opening balances of fiscal year {fiscalYear}",
  "accounting.production_order": "Production labor {number}",
  "accounting.revenue_deferral": "Defer revenue",
  "accounting.revenue_recognition": "Recognize revenue",
  "accounting.reversal": "Reversal of {number}",
  "accounting.stock_movement": "Stock {reason}",
  "accounting.till_count": "Till count: {till}",
  "accounting.till_deposit": "Cash deposit: {till}",
  "billing.proration": "Proration for {plan}",
  "donation.gift": "Gift",
  "donation.refund": "Gift refunded",
  "expense.approved": "Expenses: {title}",
  "expense.reimbursed": "Reimbursed: {title}",
  "lease.deposit": "Deposit received",
  "lease.deposit_refund": "Deposit refunded",
  "lease.payment": "Rent payment",
  "lease.rent": "Rent from {periodStart}",
};
