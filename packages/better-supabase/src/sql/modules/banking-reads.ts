import type { ReadType } from "../../core/read-type.ts";
import type { BlockSqlContext } from "../context.ts";
import type { BlockSqlRead } from "../reads.ts";

import { declareRead } from "../reads.ts";
import { userGrant } from "../shared.ts";
import { linked } from "./banking-sql.ts";

const MONEY_TEXT = "text";

/** What `bank_reconciliation_board` returns. */
export const BANK_RECONCILIATION_BOARD_RESULT: ReadType = {
  status: {
    accountId: "text",
    asOf: "text",
    currency: "text",
    statementId: "text?",
    statementBalance: "text?",
    transactionTotal: MONEY_TEXT,
    unmatchedCount: "number",
    unmatchedTotal: MONEY_TEXT,
    ledgerBalance: "text?",
    difference: "text?",
    reconciled: "bool",
  },
  lines: [
    {
      id: "text",
      bookedOn: "text",
      amount: "text",
      currency: "text",
      counterpartyName: "text?",
      counterpartyIban: "text?",
      remittance: "text?",
      status: "text",
    },
  ],
  suggestions: [
    {
      transactionId: "text",
      targetType: "text",
      targetId: "text",
      label: "text",
      balance: "text",
      currency: "text",
      score: "number",
      reasons: ["text"],
    },
  ],
};

export interface BankBoardStatus {
  readonly accountId: string;
  readonly asOf: string;
  readonly currency: string;
  readonly statementId: string | null;
  readonly statementBalance: string | null;
  readonly transactionTotal: string;
  readonly unmatchedCount: number;
  readonly unmatchedTotal: string;
  readonly ledgerBalance: string | null;
  readonly difference: string | null;
  readonly reconciled: boolean;
}

export interface BankBoardSuggestion {
  readonly transactionId: string;
  readonly targetType: string;
  readonly targetId: string;
  readonly label: string;
  readonly balance: string;
  readonly currency: string;
  readonly score: number;
  readonly reasons: readonly string[];
}

export interface BankBoardLine {
  readonly id: string;
  readonly bookedOn: string;
  readonly amount: string;
  readonly currency: string;
  readonly counterpartyName: string | null;
  readonly counterpartyIban: string | null;
  readonly remittance: string | null;
  readonly status: string;
}

/** What `banking.reconciliationBoard` returns. */
export interface BankReconciliationBoard {
  readonly status: BankBoardStatus;
  readonly lines: readonly BankBoardLine[];
  /** The best open invoice for each unmatched line that has one. */
  readonly suggestions: readonly BankBoardSuggestion[];
}

export const BANK_READS: readonly BlockSqlRead[] = [
  declareRead(
    "reconciliationBoard",
    "bank_reconciliation_board",
    {
      accountId: { param: "account_id", type: "id" },
      limit: { param: "line_limit", type: "int", optional: true },
    },
    BANK_RECONCILIATION_BOARD_RESULT,
    "A bank account's reconciliation status and its latest transactions, each unmatched one with its best invoice suggestion.",
    ["accounts", "transactions", "matches"],
  ),
];

/**
 * `bank_reconciliation_board`: the status and the transactions as the existing
 * functions return them, so renamed columns and permissions stay in one place.
 */
export function bankingReads(ctx: BlockSqlContext): string {
  const fn = (name: string): string => ctx.fn(name);

  const suggestions = linked(ctx, "invoices")
    ? `coalesce((
      select jsonb_agg(best.s || jsonb_build_object('transactionId', x.line ->> 'id') order by x.position)
      from jsonb_array_elements(src.payload) with ordinality as x(line, position)
      cross join lateral (
        select s from jsonb_array_elements(${fn("suggest_bank_matches")}((x.line ->> 'id')::uuid)) s
        where x.line ->> 'status' = 'unmatched' and s ->> 'targetType' = 'invoice' limit 1) best
    ), '[]'::jsonb)`
    : "'[]'::jsonb";

  return `
-- An account's reconciliation page in one call: where it stands, and its latest
-- transactions with the best invoice for each unmatched one. It runs as the
-- caller and reads through the status and listing functions.
create or replace function ${fn("bank_reconciliation_board")}(account_id uuid, line_limit integer default 50)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  with src as (
    select ${fn("list_bank_transactions")}(bank_reconciliation_board.account_id,
      jsonb_build_object('limit', bank_reconciliation_board.line_limit)) as payload
  )
  select jsonb_build_object(
    'status', ${fn("bank_reconciliation_status")}(bank_reconciliation_board.account_id, null),
    'lines', coalesce((
      select jsonb_agg(jsonb_build_object(
          'id', x.line -> 'id', 'bookedOn', x.line -> 'bookedOn', 'amount', x.line -> 'amount',
          'currency', x.line -> 'currency', 'counterpartyName', x.line -> 'counterpartyName',
          'counterpartyIban', x.line -> 'counterpartyIban', 'remittance', x.line -> 'remittance',
          'status', x.line -> 'status') order by x.position)
      from jsonb_array_elements(src.payload) with ordinality as x(line, position)
    ), '[]'::jsonb),
    'suggestions', ${suggestions})
  from src;
$$;
${userGrant(`${fn("bank_reconciliation_board")}(uuid, integer)`)}
`;
}
