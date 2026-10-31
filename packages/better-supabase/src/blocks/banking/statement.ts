import type { Money } from "../../commerce/money.ts";
import type { STATEMENT_FORMATS } from "../../sql/modules/banking-sql.ts";

/** What a statement was read from. */
export type BankStatementFormat = (typeof STATEMENT_FORMATS)[number];

/** A date as `Temporal.PlainDate` or `YYYY-MM-DD`. */
export type BankDate = Temporal.PlainDate | string;

/**
 * One transaction to import; `amount` is signed: negative money left the
 * account.
 */
export interface BankTransactionInput {
  /**
   * The bank's id of the transaction, unique per account: importing it again
   * adds nothing. Without one the import hashes the fields and the position.
   */
  readonly externalId?: string;
  readonly bookedOn: BankDate;
  readonly valueOn?: BankDate;
  readonly amount: Money;
  readonly counterpartyName?: string;
  readonly counterpartyIban?: string;
  /** The unstructured remittance information. */
  readonly remittance?: string;
  /** A creditor reference, such as an RF reference or a betalingskenmerk. */
  readonly structuredReference?: string;
  readonly endToEndId?: string;
}

/** A statement, a file or a feed page, to import into one bank account. */
export interface BankStatementInput {
  /** The statement's id; importing the same reference adds to that statement. */
  readonly reference?: string;
  readonly fromOn?: BankDate;
  readonly untilOn?: BankDate;
  readonly openingBalance?: Money;
  readonly closingBalance?: Money;
  /** Default `feed`. */
  readonly format?: BankStatementFormat;
  /** The attachments block's record of the uploaded file. */
  readonly attachmentId?: string;
  readonly transactions: readonly BankTransactionInput[];
}

/** The account a parsed statement is for. */
export interface ParsedBankAccount {
  readonly iban?: string;
  /** The account identification when it isn't an IBAN. */
  readonly identification?: string;
  readonly currency: string;
}

/** A statement read from a CAMT.053 or MT940 file, ready to import. */
export interface ParsedBankStatement extends BankStatementInput {
  readonly format: "camt053" | "mt940";
  readonly account: ParsedBankAccount;
  readonly fromOn?: string;
  readonly untilOn?: string;
  readonly transactions: readonly ParsedBankTransaction[];
}

/** A transaction read from a statement file, its dates as `YYYY-MM-DD`. */
export interface ParsedBankTransaction extends BankTransactionInput {
  readonly bookedOn: string;
  readonly valueOn?: string;
}
