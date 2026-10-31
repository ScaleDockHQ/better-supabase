import type { AuditRecord, AuditWarning } from "./model.ts";
import type { XmlNode } from "./xml.ts";

import { AuditFileError } from "./model.ts";
import { childNode, childText } from "./xml.ts";

const DEFAULT_DECIMALS = 2;
const DECIMAL = /^([+-])?(\d+)(?:\.(\d+))?$/u;
const DATE = /^(\d{4})-(\d{2})-(\d{2})/u;

/** Reads a decimal such as `-1234.50` as minor units, refusing lost digits. */
export function parseAmount(
  text: string,
  decimals: number | undefined,
  where: string,
): bigint {
  const scale = decimals ?? DEFAULT_DECIMALS;
  const match = DECIMAL.exec(text.trim());

  if (match === null) {
    throw new AuditFileError(
      "AUDIT_AMOUNT_INVALID",
      `${where}: "${text}" is not a decimal amount`,
    );
  }

  const [, sign, whole = "0", fraction = ""] = match;
  const trimmed = fraction.replace(/0+$/u, "");

  if (trimmed.length > scale) {
    throw new AuditFileError(
      "AUDIT_AMOUNT_INVALID",
      `${where}: "${text}" has more than ${scale} decimals`,
    );
  }

  const minor = BigInt(whole + trimmed.padEnd(scale, "0"));

  return sign === "-" ? -minor : minor;
}

/** Writes minor units as a decimal with `decimals` digits. */
export function formatAmount(
  amount: bigint,
  decimals: number | undefined,
): string {
  const scale = decimals ?? DEFAULT_DECIMALS;
  const negative = amount < 0n;

  const digits = (negative ? -amount : amount)
    .toString()
    .padStart(scale + 1, "0");

  const whole = digits.slice(0, digits.length - scale);
  const fraction = digits.slice(digits.length - scale);
  const text = scale === 0 ? whole : `${whole}.${fraction}`;

  return negative ? `-${text}` : text;
}

/** Reads the date part of `YYYY-MM-DD` or a date-time. */
export function parseDate(text: string, where: string): string {
  const match = DATE.exec(text.trim());

  if (match === null) {
    throw new AuditFileError(
      "AUDIT_FILE_INVALID",
      `${where}: "${text}" is not a date`,
    );
  }

  const [, year = "", month = "", day = ""] = match;
  const parsed = new Date(`${year}-${month}-${day}T00:00:00Z`);

  if (
    Number.isNaN(parsed.getTime()) ||
    parsed.toISOString().slice(0, 10) !== `${year}-${month}-${day}`
  ) {
    throw new AuditFileError(
      "AUDIT_FILE_INVALID",
      `${where}: "${text}" is not a calendar date`,
    );
  }

  return `${year}-${month}-${day}`;
}

/** A debit and a credit from one signed amount and its side. */
export function sides(
  amount: bigint,
  side: "debit" | "credit",
): { readonly debit: bigint; readonly credit: bigint } {
  const debit = side === "debit" ? amount : -amount;

  return debit >= 0n ? { debit, credit: 0n } : { debit: 0n, credit: -debit };
}

/** The text of `name`, or of its `Amount` child, as minor units. */
export function amountChild(
  node: XmlNode,
  name: string,
  decimals: number | undefined,
  where: string,
): bigint | undefined {
  const element = childNode(node, name);

  if (element === undefined) {
    return undefined;
  }

  const text = childText(element, "Amount") ?? element.text.trim();

  return text === "" ? undefined : parseAmount(text, decimals, where);
}

export function requiredText(
  node: XmlNode,
  name: string,
  where: string,
): string {
  const text = childText(node, name);

  if (text === undefined) {
    throw new AuditFileError("AUDIT_FILE_INVALID", `${where} has no <${name}>`);
  }

  return text;
}

/** Keeps a count per message so a repeat is one warning, not thousands. */
export class WarningLog {
  readonly #unmapped = new Map<string, number>();
  readonly #counts = new Map<string, AuditWarning>();

  unmapped(path: string): void {
    this.#unmapped.set(path, (this.#unmapped.get(path) ?? 0) + 1);
  }

  add(code: AuditWarning["code"], message: string, path?: string): void {
    const key = `${code}\u0000${message}`;
    const seen = this.#counts.get(key);

    this.#counts.set(key, {
      code,
      message,
      count: (seen?.count ?? 0) + 1,
      ...(path === undefined ? {} : { path }),
    });
  }

  *records(): Generator<AuditRecord> {
    for (const [path, count] of this.#unmapped) {
      yield {
        kind: "warning",
        warning: {
          code: "AUDIT_ELEMENT_UNMAPPED",
          message: `<${path.split("/").at(-1) ?? path}> is not mapped; its content was not imported`,
          path,
          count,
        },
      };
    }

    for (const warning of this.#counts.values()) {
      yield { kind: "warning", warning };
    }
  }
}

/** Compares the control totals a file states with what it holds. */
export function controlTotals(
  log: WarningLog,
  stated: {
    readonly debit?: bigint | undefined;
    readonly credit?: bigint | undefined;
  },
  actual: { readonly debit: bigint; readonly credit: bigint },
): void {
  if (stated.debit !== undefined && stated.debit !== actual.debit) {
    log.add(
      "AUDIT_CONTROL_TOTAL_MISMATCH",
      `the stated total debit ${String(stated.debit)} differs from the entries' ${String(actual.debit)} (minor units)`,
    );
  }

  if (stated.credit !== undefined && stated.credit !== actual.credit) {
    log.add(
      "AUDIT_CONTROL_TOTAL_MISMATCH",
      `the stated total credit ${String(stated.credit)} differs from the entries' ${String(actual.credit)} (minor units)`,
    );
  }
}

/** The calendar months from `start` to `end`, as `[number, from, to]`. */
export function monthsBetween(
  start: string,
  end: string,
): readonly (readonly [number, string, string])[] {
  const months: [number, string, string][] = [];
  let year = Number(start.slice(0, 4));
  let month = Number(start.slice(5, 7));
  const last = Number(end.slice(0, 4)) * 12 + Number(end.slice(5, 7));
  let number = 1;

  while (year * 12 + month <= last && number <= 24) {
    const first = `${String(year).padStart(4, "0")}-${String(month).padStart(2, "0")}-01`;

    const lastDay = new Date(Date.UTC(year, month, 0)).getUTCDate();

    const to = `${String(year).padStart(4, "0")}-${String(month).padStart(2, "0")}-${String(lastDay).padStart(2, "0")}`;

    months.push([number, first, to]);
    number += 1;
    month += 1;

    if (month === 13) {
      month = 1;
      year += 1;
    }
  }

  return months;
}
