import { ISO_4217_MINOR_UNITS } from "./iso4217.ts";

/**
 * An amount in the currency's minor units (cents for EUR, yen for JPY) and an
 * ISO 4217 code. SQL stores the same pair as `bigint` and `char(3)`.
 */
export interface Money {
  readonly amount: bigint;
  readonly currency: string;
}

/**
 * `Money` as JSON: the amount as a string of minor units, since JSON has no
 * bigint.
 */
export interface MoneyJson {
  readonly amount: string;
  readonly currency: string;
}

/**
 * Thrown when two amounts in different currencies meet; lines never mix
 * currencies.
 */
export class CurrencyMismatchError extends TypeError {
  readonly currencies: readonly [string, string];

  constructor(a: string, b: string) {
    super(`Can't combine ${a} and ${b}: amounts must share one currency`);
    this.name = "CurrencyMismatchError";
    this.currencies = [a, b];
  }
}

const RATE = /^(\d+)(?:\.(\d+))?$/;
const DECIMAL = /^(-)?(\d+)(?:\.(\d+))?$/;

/** Whether `code` is an ISO 4217 code with minor units, such as `EUR`. */
export function isCurrency(code: unknown): code is string {
  return typeof code === "string" && Object.hasOwn(ISO_4217_MINOR_UNITS, code);
}

/** The number of minor units of `currency`: 2 for EUR, 0 for JPY, 3 for KWD. */
export function minorUnits(currency: string): number {
  if (!isCurrency(currency)) {
    throw new RangeError(
      `"${String(currency)}" is not an ISO 4217 currency code with minor units`,
    );
  }

  return ISO_4217_MINOR_UNITS[currency] ?? 0;
}

/**
 * `Money` from an integer number of minor units: `money(1999n, "EUR")` is 19.99
 * EUR.
 */
export function money(amount: bigint | number, currency: string): Money {
  minorUnits(currency);

  if (typeof amount === "number" && !Number.isSafeInteger(amount)) {
    throw new RangeError(
      `${amount} is not a whole number of minor units; use parseMoney for a decimal`,
    );
  }

  return Object.freeze({ amount: BigInt(amount), currency });
}

/** Whether `value` is a `Money` with a bigint amount and a known currency. */
export function isMoney(value: unknown): value is Money {
  return (
    typeof value === "object" &&
    value !== null &&
    "amount" in value &&
    "currency" in value &&
    typeof value.amount === "bigint" &&
    isCurrency(value.currency)
  );
}

/**
 * Reads a decimal such as `"19.99"` in `currency`. More decimals than the
 * currency has minor units throw instead of rounding.
 */
export function parseMoney(decimal: string, currency: string): Money {
  const units = minorUnits(currency);
  const match = DECIMAL.exec(decimal.trim());

  if (!match) {
    throw new RangeError(`"${decimal}" is not a decimal amount`);
  }

  const [, sign, whole = "0", fraction = ""] = match;

  if (fraction.length > units) {
    throw new RangeError(
      `"${decimal}" has more decimals than ${currency}'s ${units} minor units`,
    );
  }

  const amount = BigInt(whole + fraction.padEnd(units, "0"));

  return money(sign === "-" ? -amount : amount, currency);
}

/**
 * The amount as a decimal string with every minor unit: `"19.90"`, `"500"` for
 * JPY.
 */
export function toDecimal(value: Money): string {
  const units = minorUnits(value.currency);
  const negative = value.amount < 0n;

  const digits = (negative ? -value.amount : value.amount)
    .toString()
    .padStart(units + 1, "0");

  const whole = digits.slice(0, digits.length - units);
  const fraction = units === 0 ? "" : `.${digits.slice(-units)}`;

  return `${negative ? "-" : ""}${whole}${fraction}`;
}

/**
 * Formats with `Intl.NumberFormat`, passing the exact decimal string so large
 * amounts keep every digit.
 */
export function formatMoney(
  value: Money,
  locale?: Intl.LocalesArgument,
  options: Omit<Intl.NumberFormatOptions, "style" | "currency"> = {},
): string {
  return new Intl.NumberFormat(locale, {
    ...options,
    style: "currency",
    currency: value.currency,
  }).format(
    // SAFETY: toDecimal writes an optional minus, digits and an optional
    // fraction, which is a numeric string literal.
    toDecimal(value) as Intl.StringNumericLiteral,
  );
}

/** `{ amount: "1999", currency: "EUR" }`, for JSON bodies and `jsonb` columns. */
export function moneyToJson(value: Money): MoneyJson {
  return { amount: value.amount.toString(), currency: value.currency };
}

/** Reads `MoneyJson` back; throws for anything else. */
export function moneyFromJson(value: unknown): Money {
  if (
    typeof value !== "object" ||
    value === null ||
    !("amount" in value) ||
    !("currency" in value) ||
    typeof value.amount !== "string" ||
    typeof value.currency !== "string" ||
    !/^-?\d+$/.test(value.amount)
  ) {
    throw new TypeError(
      'Money JSON is { amount: "<minor units>", currency: "<ISO 4217 code>" }',
    );
  }

  return money(BigInt(value.amount), value.currency);
}

const sameCurrency = (a: Money, b: Money): void => {
  if (a.currency !== b.currency) {
    throw new CurrencyMismatchError(a.currency, b.currency);
  }
};

export function addMoney(a: Money, b: Money): Money {
  sameCurrency(a, b);

  return money(a.amount + b.amount, a.currency);
}

export function subtractMoney(a: Money, b: Money): Money {
  sameCurrency(a, b);

  return money(a.amount - b.amount, a.currency);
}

/** The total of `values`, all in `currency`; zero for an empty list. */
export function sumMoney(values: readonly Money[], currency: string): Money {
  let total = money(0n, currency);

  for (const value of values) {
    total = addMoney(total, value);
  }

  return total;
}

/**
 * `value` times a whole `quantity`, such as a unit price times the line's
 * quantity.
 */
export function multiplyMoney(value: Money, quantity: bigint | number): Money {
  if (typeof quantity === "number" && !Number.isSafeInteger(quantity)) {
    throw new RangeError(`${quantity} is not a whole quantity`);
  }

  return money(value.amount * BigInt(quantity), value.currency);
}

export function negateMoney(value: Money): Money {
  return money(-value.amount, value.currency);
}

/** -1, 0 or 1; throws for different currencies. */
export function compareMoney(a: Money, b: Money): -1 | 0 | 1 {
  sameCurrency(a, b);

  if (a.amount === b.amount) {
    return 0;
  }

  return a.amount < b.amount ? -1 : 1;
}

/**
 * `numerator / denominator` rounded half to even (banker's rounding): ties go
 * to the even neighbour, so rounding many lines doesn't drift one way.
 */
export function roundHalfEven(numerator: bigint, denominator: bigint): bigint {
  if (denominator === 0n) {
    throw new RangeError("Division by zero");
  }

  const [n, d] =
    denominator < 0n ? [-numerator, -denominator] : [numerator, denominator];

  const quotient = n / d;
  const remainder = n % d;
  const twice = 2n * (remainder < 0n ? -remainder : remainder);

  if (twice < d) {
    return quotient;
  }

  const away = n < 0n ? quotient - 1n : quotient + 1n;

  if (twice > d) {
    return away;
  }

  return quotient % 2n === 0n ? quotient : away;
}

/** Whether `rate` is a non-negative decimal fraction such as `"0.21"`. */
export function isRate(rate: unknown): rate is string {
  return typeof rate === "string" && RATE.test(rate);
}

const rateParts = (rate: string): readonly [bigint, bigint] => {
  const match = RATE.exec(rate);

  if (!match) {
    throw new RangeError(
      `"${rate}" is not a rate; write a decimal fraction such as "0.21"`,
    );
  }

  const [, whole = "0", fraction = ""] = match;

  return [BigInt(whole + fraction), 10n ** BigInt(fraction.length)];
};

/**
 * `value` times `rate` (a decimal fraction such as `"0.21"`), rounded half to
 * even. With `included: true`, `value` already contains the rate (a
 * tax-inclusive price) and the result is the part the rate accounts for: `value *
 * rate / (1 + rate)`.
 */
export function applyRate(
  value: Money,
  rate: string,
  options: { readonly included?: boolean } = {},
): Money {
  const [numerator, denominator] = rateParts(rate);
  const divisor = options.included ? denominator + numerator : denominator;

  return money(
    roundHalfEven(value.amount * numerator, divisor),
    value.currency,
  );
}

/**
 * Splits `value` by `weights` so the parts add up to it exactly. Each part is
 * rounded down, and the leftover minor units go to the largest remainders,
 * earlier parts first on a tie.
 */
export function allocateMoney(
  value: Money,
  weights: readonly (bigint | number)[],
): Money[] {
  const shares = weights.map((weight) => {
    if (typeof weight === "number" && !Number.isSafeInteger(weight)) {
      throw new RangeError(`${weight} is not a whole weight`);
    }

    const share = BigInt(weight);

    if (share < 0n) {
      throw new RangeError("Weights can't be negative");
    }

    return share;
  });

  const total = shares.reduce((sum, share) => sum + share, 0n);

  if (total === 0n) {
    throw new RangeError("Weights must add up to more than 0");
  }

  const negative = value.amount < 0n;
  const amount = negative ? -value.amount : value.amount;

  const parts = shares.map((share) => ({
    base: (amount * share) / total,
    remainder: (amount * share) % total,
  }));

  let left = amount - parts.reduce((sum, part) => sum + part.base, 0n);

  const order = parts
    .map((part, index) => ({ index, remainder: part.remainder }))
    .toSorted((a, b) =>
      a.remainder === b.remainder
        ? a.index - b.index
        : a.remainder > b.remainder
          ? -1
          : 1,
    );

  const extra = new Set<number>();

  for (const { index } of order) {
    if (left === 0n) {
      break;
    }

    extra.add(index);
    left -= 1n;
  }

  return parts.map((part, index) => {
    const share = part.base + (extra.has(index) ? 1n : 0n);

    return money(negative ? -share : share, value.currency);
  });
}
