import type { Money } from "../../commerce/money.ts";
import type {
  ParsedBankAccount,
  ParsedBankStatement,
  ParsedBankTransaction,
} from "./statement.ts";

import { negateMoney, parseMoney } from "../../commerce/money.ts";

const TAG = /^:(\d{2}[A-Z]?):/;
const BALANCE = /^([CD])(\d{6})([A-Z]{3})([\d,]+)$/;

const ENTRY =
  /^(\d{6})(\d{4})?(R?[CD])([A-Z])?([\d,]+)([NSF][A-Z0-9]{3})([^/\n]*)(?:\/\/([^\n]*))?(?:\n([\s\S]*))?$/;

const IBAN = /^[A-Z]{2}\d{2}[A-Z0-9]{11,30}$/;

const NONREF = "NONREF";

/** The keys of the SEPA layout Dutch and Belgian banks write in `:86:`. */
const SEPA_KEYS = new Set([
  "BENM",
  "BIC",
  "CNTP",
  "CSID",
  "EREF",
  "FX",
  "IBAN",
  "ID",
  "ISDT",
  "MARF",
  "NAME",
  "ORDP",
  "PREF",
  "PURP",
  "REMI",
  "RTRN",
  "SVCL",
  "TRTP",
  "ULTB",
  "ULTC",
  "ULTD",
]);

interface Field {
  readonly tag: string;
  readonly value: string;
}

/** YYMMDD as YYYY-MM-DD; two-digit years from 80 are 19xx. */
function dateOf(yymmdd: string): string {
  const year = Number(yymmdd.slice(0, 2));

  return `${year >= 80 ? "19" : "20"}${yymmdd.slice(0, 6)}`.replace(
    /^(\d{4})(\d{2})(\d{2})$/,
    "$1-$2-$3",
  );
}

const amountOf = (text: string, currency: string): Money =>
  parseMoney(text.replace(",", ".").replace(/\.$/, ""), currency);

/** The statements in the text, each a run of fields from `:20:`. */
function statementsOf(text: string): Field[][] {
  const statements: Field[][] = [];
  let current: Field[] | undefined;
  let last: { tag: string; lines: string[] } | undefined;

  const flush = (): void => {
    if (last && current) {
      current.push({ tag: last.tag, value: last.lines.join("\n").trim() });
    }

    last = undefined;
  };

  for (const raw of text.split(/\r?\n/)) {
    const line = raw.replace(/^\{\d:[^}]*\}?/, "");

    if (line.startsWith("-}") || line === "-") {
      flush();
      continue;
    }

    const tag = TAG.exec(line);

    if (tag?.[1] !== undefined) {
      flush();

      if (tag[1] === "20") {
        current = [];
        statements.push(current);
      }

      last = { tag: tag[1], lines: [line.slice(tag[0].length)] };
    } else if (last) {
      last.lines.push(line);
    }
  }

  flush();

  return statements;
}

/** The SEPA keys of a `:86:` field: `/EREF/…/IBAN/…/NAME/…/REMI/…`. */
function slashed(info: string): Map<string, string> | undefined {
  const text = info.replaceAll("\n", "");

  if (!text.startsWith("/")) {
    return undefined;
  }

  const keys = new Map<string, string>();
  const parts = text.slice(1).split("/");

  for (let i = 0; i < parts.length; i += 1) {
    const key = parts[i] ?? "";

    if (!SEPA_KEYS.has(key)) {
      continue;
    }

    const values: string[] = [];

    while (i + 1 < parts.length && !SEPA_KEYS.has(parts[i + 1] ?? "")) {
      i += 1;
      values.push(parts[i] ?? "");
    }

    keys.set(key, values.join("/"));
  }

  return keys;
}

/** The `?20`…`?63` subfields of a German `:86:` field. */
function subfields(info: string): Map<string, string> | undefined {
  const text = info.replaceAll("\n", "");

  if (!/^\d{3}\?/.test(text)) {
    return undefined;
  }

  const fields = new Map<string, string>();

  for (const match of text.matchAll(/\?(\d{2})([^?]*)/g)) {
    const [, code = "", value = ""] = match;

    fields.set(code, (fields.get(code) ?? "") + value);
  }

  return fields;
}

/** Counterparty and remittance from a `:86:` field, as banks write them. */
function detailsOf(
  info: string | undefined,
): Partial<
  Pick<
    ParsedBankTransaction,
    | "counterpartyName"
    | "counterpartyIban"
    | "remittance"
    | "structuredReference"
    | "endToEndId"
  >
> {
  if (info === undefined || info === "") {
    return {};
  }

  const sepa = slashed(info);

  if (sepa) {
    const counterparty = (sepa.get("CNTP") ?? "").split("/");
    const iban = sepa.get("IBAN") ?? counterparty[0];
    const name = sepa.get("NAME") ?? counterparty[2];
    const remi = sepa.get("REMI") ?? "";
    const structured = /^STRD\/[^/]*\/(.+)$/.exec(remi)?.[1];
    const remittance = remi.replace(/^USTD\/\//, "").replace(/\/$/, "");
    const eref = sepa.get("EREF");

    return {
      ...(iban && IBAN.test(iban) ? { counterpartyIban: iban } : {}),
      ...(name ? { counterpartyName: name.trim() } : {}),
      ...(structured
        ? { structuredReference: structured.replace(/\/$/, "") }
        : remittance
          ? { remittance: remittance.trim() }
          : {}),
      ...(eref && eref !== "NOTPROVIDED" ? { endToEndId: eref } : {}),
    };
  }

  const german = subfields(info);

  if (german) {
    const text = [
      ...["20", "21", "22", "23", "24", "25", "26", "27", "28", "29"],
      ...["60", "61", "62", "63"],
    ]
      .map((code) => german.get(code) ?? "")
      .join("");

    const eref = /EREF\+(.*?)(?=[A-Z]{4}\+|$)/.exec(text)?.[1];
    const svwz = /SVWZ\+(.*?)(?=[A-Z]{4}\+|$)/.exec(text)?.[1];
    const iban = german.get("31");
    const name = `${german.get("32") ?? ""}${german.get("33") ?? ""}`.trim();

    return {
      ...(iban && IBAN.test(iban) ? { counterpartyIban: iban } : {}),
      ...(name ? { counterpartyName: name } : {}),
      remittance: (svwz ?? text).trim(),
      ...(eref && eref !== "NOTPROVIDED" ? { endToEndId: eref.trim() } : {}),
    };
  }

  return { remittance: info.replaceAll("\n", " ").trim() };
}

function accountOf(
  value: string | undefined,
  currency: string,
): ParsedBankAccount {
  const text = (value ?? "").replaceAll(/\s/g, "").toUpperCase();
  const iban = /([A-Z]{2}\d{2}[A-Z0-9]{11,30}?)(?:[A-Z]{3})?$/.exec(text)?.[1];

  return iban && IBAN.test(iban)
    ? { iban, currency }
    : { identification: value ?? "", currency };
}

function statementOf(fields: readonly Field[]): ParsedBankStatement {
  const get = (tag: string): string | undefined =>
    fields.find((field) => field.tag === tag)?.value;

  const opening = BALANCE.exec(
    (get("60F") ?? get("60M") ?? "").replaceAll("\n", ""),
  );

  const closing = BALANCE.exec(
    (get("62F") ?? get("62M") ?? "").replaceAll("\n", ""),
  );

  const currency = opening?.[3] ?? closing?.[3];

  if (currency === undefined) {
    throw new TypeError(
      "An MT940 statement has an opening or closing balance (:60F: or :62F:)",
    );
  }

  const balance = (match: RegExpExecArray | null): Money | undefined => {
    if (!match?.[4]) {
      return undefined;
    }

    const amount = amountOf(match[4], currency);

    return match[1] === "D" ? negateMoney(amount) : amount;
  };

  const transactions: ParsedBankTransaction[] = [];

  for (const [index, field] of fields.entries()) {
    if (field.tag !== "61") {
      continue;
    }

    const entry = ENTRY.exec(field.value);

    if (!entry) {
      throw new TypeError(`Not an MT940 :61: line: ${field.value}`);
    }

    const [
      ,
      valueDate = "",
      entryDate,
      mark = "",
      ,
      amountText = "",
      ,
      customer = "",
      bank,
    ] = entry;

    const valueOn = dateOf(valueDate);

    const bookedOn = entryDate
      ? `${valueOn.slice(0, 5)}${entryDate.slice(0, 2)}-${entryDate.slice(2)}`
      : valueOn;

    const amount = amountOf(amountText, currency);
    const credit = mark === "C" || mark === "RD";
    const next = fields[index + 1];
    const details = detailsOf(next?.tag === "86" ? next.value : undefined);

    const externalId = [bank, customer]
      .map((ref) => ref?.trim())
      .find((ref) => ref && ref !== NONREF);

    transactions.push({
      bookedOn,
      valueOn,
      amount: credit ? amount : negateMoney(amount),
      ...(externalId ? { externalId } : {}),
      ...details,
    });
  }

  const openingBalance = balance(opening);
  const closingBalance = balance(closing);
  const reference = get("20");
  const sequence = get("28C") ?? get("28");

  return {
    format: "mt940",
    account: accountOf(get("25"), currency),
    ...(reference
      ? { reference: sequence ? `${reference}/${sequence}` : reference }
      : {}),
    ...(opening?.[2] ? { fromOn: dateOf(opening[2]) } : {}),
    ...(closing?.[2] ? { untilOn: dateOf(closing[2]) } : {}),
    ...(openingBalance ? { openingBalance } : {}),
    ...(closingBalance ? { closingBalance } : {}),
    transactions,
  };
}

/**
 * Reads an MT940 customer statement file: one statement per `:20:`, with
 * balances, transactions signed by their debit or credit mark, and counterparty
 * and remittance from the `:86:` fields in the SEPA layout
 * (`/IBAN/…/NAME/…/REMI/…`) or the German `?20` subfields. Throws a `TypeError`
 * for a file it can't read.
 */
export function parseMt940(text: string): ParsedBankStatement[] {
  const statements = statementsOf(text).map(statementOf);

  if (statements.length === 0) {
    throw new TypeError("No MT940 statement (:20:) in the text");
  }

  return statements;
}
