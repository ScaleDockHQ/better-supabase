const DECIMAL = /^([+-])?(\d+)(?:\.(\d+))?$/;

/** Why `parseScaled` refused a text: not a decimal, or digits would be lost. */
export type ParseScaledError = "syntax" | "scale";

/**
 * Reads a decimal such as `"-1234.50"` as an integer count of 10^-`scale`
 * units. Digits that would be lost fail with `"scale"`; with `trimZeros`,
 * trailing zeros past the scale don't count as lost. `parseMoney` and the audit
 * file readers share it and add their own errors.
 */
export function parseScaled(
  text: string,
  scale: number,
  trimZeros = false,
): bigint | ParseScaledError {
  const match = DECIMAL.exec(text.trim());

  if (!match) {
    return "syntax";
  }

  const [, sign, whole = "0", rawFraction = ""] = match;
  const fraction = trimZeros ? rawFraction.replace(/0+$/u, "") : rawFraction;

  if (fraction.length > scale) {
    return "scale";
  }

  const amount = BigInt(whole + fraction.padEnd(scale, "0"));

  return sign === "-" ? -amount : amount;
}
