/**
 * Orders strings by UTF-16 code unit, the order `Array.prototype.sort` uses.
 * Unlike `localeCompare`, the result does not depend on the machine's locale,
 * so generated files and reports are byte-identical everywhere.
 */
export const byCodePoint = (a: string, b: string): number =>
  a < b ? -1 : a > b ? 1 : 0;
