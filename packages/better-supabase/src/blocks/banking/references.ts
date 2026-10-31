const ALNUM = /[^A-Za-z0-9]/g;
const RF = /^RF\d{2}[A-Z0-9]{1,21}$/;
const KENMERK = /^\d{16}$/;
const KENMERK_WEIGHTS = [2, 4, 8, 5, 10, 9, 7, 3, 6, 1, 2, 4, 8, 5, 10];

/** The ISO 7064 MOD 97-10 remainder, letters counting as 10 to 35. */
function mod97(value: string): number {
  let remainder = 0;

  for (const char of value) {
    const code = char.codePointAt(0) ?? 0;
    const digits = code >= 65 ? String(code - 55) : char;

    for (const digit of digits) {
      remainder = (remainder * 10 + Number(digit)) % 97;
    }
  }

  return remainder;
}

const normalize = (value: string): string =>
  value.replaceAll(ALNUM, "").toUpperCase();

/**
 * An ISO 11649 creditor reference for `payload`, such as an invoice number:
 * `creditorReference("INV-2026-0042")` is `RF73INV20260042`. Throws for a
 * payload of more than 21 letters and digits.
 */
export function creditorReference(payload: string): string {
  const body = normalize(payload);

  if (body.length === 0 || body.length > 21) {
    throw new RangeError(
      `An ISO 11649 reference carries 1 to 21 letters and digits, not "${payload}"`,
    );
  }

  const check = 98 - mod97(`${body}RF00`);

  return `RF${String(check).padStart(2, "0")}${body}`;
}

/**
 * What a structured payment reference carries, checked: the payload of an ISO
 * 11649 creditor reference (`RF73INV20260042` gives `INV20260042`), or the 15
 * digits of a Dutch betalingskenmerk after its check digit, without leading
 * zeros. `undefined` when the check digits are wrong or it is neither, as the
 * banking block's `bank_reference` decides in SQL.
 */
export function referencePayload(reference: string): string | undefined {
  const ref = normalize(reference);

  if (RF.test(ref)) {
    return mod97(`${ref.slice(4)}${ref.slice(0, 4)}`) === 1
      ? ref.slice(4)
      : undefined;
  }

  if (KENMERK.test(ref)) {
    let sum = 0;

    for (const [index, weight] of KENMERK_WEIGHTS.entries()) {
      sum += Number(ref[15 - index]) * weight;
    }

    const raw = 11 - (sum % 11);
    const check = raw === 10 ? 1 : raw === 11 ? 0 : raw;

    return check === Number(ref[0])
      ? ref.slice(1).replace(/^0+/, "") || undefined
      : undefined;
  }

  return undefined;
}

/** Whether `iban` passes its ISO 13616 check digits; spaces are ignored. */
export function isIban(iban: string): boolean {
  const value = iban.replaceAll(/\s/g, "").toUpperCase();

  return (
    /^[A-Z]{2}\d{2}[A-Z0-9]{11,30}$/.test(value) &&
    mod97(`${value.slice(4)}${value.slice(0, 4)}`) === 1
  );
}
