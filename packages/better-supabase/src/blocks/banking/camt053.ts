import type { Money } from "../../commerce/money.ts";
import type {
  ParsedBankAccount,
  ParsedBankStatement,
  ParsedBankTransaction,
} from "./statement.ts";

import { negateMoney, parseMoney } from "../../commerce/money.ts";
import { importOptionalPeer, memoized } from "../../core/optional-peer.ts";

const NAMESPACE = /urn:iso:std:iso:20022:tech:xsd:camt\.053\.001\.(\d{2})/;

const REPEATED = new Set([
  "Stmt",
  "Bal",
  "Ntry",
  "NtryDtls",
  "TxDtls",
  "Ustrd",
  "Strd",
]);

const OPENING = new Set(["OPBD", "PRCD"]);
const CLOSING = new Set(["CLBD"]);

interface XmlParserModule {
  readonly XMLParser: new (options: Record<string, unknown>) => {
    parse(xml: string): unknown;
  };
}

const isParserModule = (value: unknown): value is XmlParserModule =>
  typeof value === "object" &&
  value !== null &&
  "XMLParser" in value &&
  typeof value.XMLParser === "function";

// fast-xml-parser is an optional peer: only apps that read CAMT files install it.
const loadParser = memoized(async (): Promise<XmlParserModule> => {
  const module = await importOptionalPeer("fast-xml-parser");

  if (!isParserModule(module)) {
    throw new TypeError(
      "parseCamt053 needs the fast-xml-parser package: pnpm add fast-xml-parser",
    );
  }

  return module;
});

type Node = Readonly<Record<string, unknown>>;

const isNode = (value: unknown): value is Node =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/** The child at `path`, or `undefined`. */
function at(value: unknown, ...path: readonly string[]): unknown {
  let current = value;

  for (const key of path) {
    current = isNode(current) ? current[key] : undefined;
  }

  return current;
}

const list = (value: unknown): readonly unknown[] =>
  Array.isArray(value) ? value : value === undefined ? [] : [value];

/** The text of an element, whether it has attributes or not. */
function text(value: unknown): string | undefined {
  const raw = isNode(value) ? value["#text"] : value;

  if (typeof raw === "string" || typeof raw === "number") {
    const trimmed = String(raw).trim();

    return trimmed === "" ? undefined : trimmed;
  }

  return undefined;
}

/** A `Dt` or `DtTm` child as `YYYY-MM-DD`. */
const dateOf = (value: unknown): string | undefined =>
  (text(at(value, "Dt")) ?? text(at(value, "DtTm")))?.slice(0, 10);

/** A signed amount from an `Amt` element and its `CdtDbtInd`. */
function amountOf(
  amount: unknown,
  indicator: unknown,
  reversal = false,
): Money {
  const value = text(amount);
  const currency = isNode(amount) ? text(amount["@_Ccy"]) : undefined;

  if (value === undefined || currency === undefined) {
    throw new TypeError("A CAMT.053 amount has a value and a Ccy attribute");
  }

  const money = parseMoney(value, currency);
  const debit = (text(indicator) === "DBIT") !== reversal;

  return debit ? negateMoney(money) : money;
}

/** A party's name: `Nm` in .001.02, `Pty/Nm` from .001.08. */
const nameOf = (party: unknown): string | undefined =>
  text(at(party, "Nm")) ?? text(at(party, "Pty", "Nm"));

function detailsOf(
  details: unknown,
  credit: boolean,
): Omit<ParsedBankTransaction, "bookedOn" | "amount"> {
  const parties = at(details, "RltdPties");
  const counterparty = credit ? "Dbtr" : "Cdtr";
  const name = nameOf(at(parties, counterparty));
  const iban = text(at(parties, `${counterparty}Acct`, "Id", "IBAN"));

  const remittance = list(at(details, "RmtInf", "Ustrd"))
    .map(text)
    .filter((line) => line !== undefined)
    .join(" ");

  const structured = list(at(details, "RmtInf", "Strd"))
    .map((strd) => text(at(strd, "CdtrRefInf", "Ref")))
    .find((ref) => ref !== undefined);

  const endToEndId = text(at(details, "Refs", "EndToEndId"));

  return {
    ...(name ? { counterpartyName: name } : {}),
    ...(iban
      ? { counterpartyIban: iban.replaceAll(/\s/g, "").toUpperCase() }
      : {}),
    ...(remittance ? { remittance } : {}),
    ...(structured ? { structuredReference: structured } : {}),
    ...(endToEndId && endToEndId !== "NOTPROVIDED" ? { endToEndId } : {}),
  };
}

/** Booked entries only: pending and information entries can still change. */
function booked(entry: unknown): boolean {
  const status = at(entry, "Sts");

  return (text(at(status, "Cd")) ?? text(status)) === "BOOK";
}

function transactionsOf(entry: unknown): ParsedBankTransaction[] {
  const bookedOn = dateOf(at(entry, "BookgDt")) ?? dateOf(at(entry, "ValDt"));

  if (bookedOn === undefined) {
    throw new TypeError("A CAMT.053 entry has a BookgDt or ValDt");
  }

  const valueOn = dateOf(at(entry, "ValDt"));
  const reversal = text(at(entry, "RvslInd")) === "true";
  const amount = amountOf(at(entry, "Amt"), at(entry, "CdtDbtInd"), reversal);
  const entryRef = text(at(entry, "AcctSvcrRef")) ?? text(at(entry, "NtryRef"));

  const details = list(at(entry, "NtryDtls")).flatMap((group) =>
    list(at(group, "TxDtls")),
  );

  const base = { bookedOn, ...(valueOn ? { valueOn } : {}) };

  // A batch entry lists its transactions; split it when each one has an amount.
  const split =
    details.length > 1 &&
    details.every(
      (tx) =>
        at(tx, "Amt") !== undefined ||
        at(tx, "AmtDtls", "TxAmt", "Amt") !== undefined,
    );

  if (!split) {
    return [
      {
        ...base,
        amount,
        ...(entryRef ? { externalId: entryRef } : {}),
        ...detailsOf(details[0], amount.amount >= 0n),
      },
    ];
  }

  return details.map((tx, index) => {
    const indicator = at(tx, "CdtDbtInd") ?? at(entry, "CdtDbtInd");

    const txAmount = amountOf(
      at(tx, "Amt") ?? at(tx, "AmtDtls", "TxAmt", "Amt"),
      indicator,
      reversal,
    );

    const ref =
      text(at(tx, "Refs", "AcctSvcrRef")) ?? text(at(tx, "Refs", "TxId"));

    const externalId =
      ref ?? (entryRef ? `${entryRef}/${index + 1}` : undefined);

    return {
      ...base,
      amount: txAmount,
      ...(externalId ? { externalId } : {}),
      ...detailsOf(tx, txAmount.amount >= 0n),
    };
  });
}

function balanceOf(statement: unknown, codes: ReadonlySet<string>): unknown {
  return list(at(statement, "Bal")).find((balance) => {
    const code = text(at(balance, "Tp", "CdOrPrtry", "Cd"));

    return code !== undefined && codes.has(code);
  });
}

function statementOf(statement: unknown): ParsedBankStatement {
  const account = at(statement, "Acct");
  const iban = text(at(account, "Id", "IBAN"));
  const opening = balanceOf(statement, OPENING);
  const closing = balanceOf(statement, CLOSING);

  const currency =
    text(at(account, "Ccy")) ??
    (isNode(at(closing ?? opening, "Amt"))
      ? text(at(closing ?? opening, "Amt", "@_Ccy"))
      : undefined);

  if (currency === undefined) {
    throw new TypeError(
      "A CAMT.053 statement names its account currency (Acct/Ccy)",
    );
  }

  const parsedAccount: ParsedBankAccount = iban
    ? { iban: iban.replaceAll(/\s/g, "").toUpperCase(), currency }
    : { identification: text(at(account, "Id", "Othr", "Id")) ?? "", currency };

  const reference = text(at(statement, "Id"));

  const fromOn =
    text(at(statement, "FrToDt", "FrDtTm"))?.slice(0, 10) ??
    dateOf(at(opening, "Dt"));

  const untilOn =
    text(at(statement, "FrToDt", "ToDtTm"))?.slice(0, 10) ??
    dateOf(at(closing, "Dt"));

  const balance = (node: unknown): Money | undefined =>
    node === undefined
      ? undefined
      : amountOf(at(node, "Amt"), at(node, "CdtDbtInd"));

  const openingBalance = balance(opening);
  const closingBalance = balance(closing);

  return {
    format: "camt053",
    account: parsedAccount,
    ...(reference ? { reference } : {}),
    ...(fromOn ? { fromOn } : {}),
    ...(untilOn ? { untilOn } : {}),
    ...(openingBalance ? { openingBalance } : {}),
    ...(closingBalance ? { closingBalance } : {}),
    transactions: list(at(statement, "Ntry"))
      .filter(booked)
      .flatMap(transactionsOf),
  };
}

/**
 * Reads an ISO 20022 bank-to-customer statement (camt.053.001.02 to .001.08):
 * one statement per `Stmt`, with the opening and closing booked balances and
 * the booked entries, signed by `CdtDbtInd`. A batch entry with an amount per
 * transaction splits into its transactions. Loads the `fast-xml-parser`
 * optional peer on first use; throws a `TypeError` without it or for a file
 * that isn't a camt.053 statement.
 */
export async function parseCamt053(
  xml: string,
): Promise<ParsedBankStatement[]> {
  const version = NAMESPACE.exec(xml)?.[1];

  if (version === undefined) {
    throw new TypeError(
      "Not a camt.053 statement: the document has no urn:iso:std:iso:20022:tech:xsd:camt.053.001 namespace",
    );
  }

  const { XMLParser } = await loadParser();

  const document = new XMLParser({
    ignoreAttributes: false,
    isArray: (name: string) => REPEATED.has(name),
    parseAttributeValue: false,
    parseTagValue: false,
    processEntities: true,
    removeNSPrefix: true,
  }).parse(xml);

  const statements = list(at(document, "Document", "BkToCstmrStmt", "Stmt"));

  if (statements.length === 0) {
    throw new TypeError(
      "A camt.053 document has at least one BkToCstmrStmt/Stmt",
    );
  }

  return statements.map(statementOf);
}
