# 0663: Bank accounts take a holder and a primary flag

- Status: accepted
- Date: 2026-11-10

## Context

The performance audit listed the banking primary and holder columns as an open item of the block
gaps. An organization with several accounts in one currency had no way to say which one it pays from
first, and a statement import could not check who owned the account.

## Decision

`bank_accounts` gets two columns. `holder` is optional text of 1 to 200 characters, as the bank prints
it. `is_primary` is a boolean that defaults to false, with a partial unique index on
`(tenant_id, currency)` for active primary rows, so each organization has at most one primary account
per currency.

`save_bank_account` reads `holder` and `primary` from its input. Setting `primary` to true clears the
flag on the organization's other accounts in the same currency in the same statement, so the caller
never sees the unique index fire. Archiving an account clears its own flag. The returned JSON carries
`holder` and `primary`, and `BankAccount` and `BankAccountInput` carry them in TypeScript.

## Consequences

The migration adds two columns with a default, so existing rows stay valid and none is primary until a
caller sets it. Nothing in matching or statement import reads the flag yet; it is data for the
app. Row timings are unchanged: the new index covers a handful of rows per tenant.
