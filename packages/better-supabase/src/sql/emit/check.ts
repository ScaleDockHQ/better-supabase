import { closingParen } from "../schema-scan.ts";

const CHECK = /\bcheck\s*\(/gi;

/** A plain operand: a column, a qualified name, or a call of one level. */
const OPERAND = String.raw`(?:[a-z_][\w$]*\s*\([^()]*\)|"[^"]+"|[a-z_][\w$.]*)`;

/** A bound: a number or a name. */
const BOUND = String.raw`(?:-?\d+(?:\.\d+)?|"[^"]+"|[a-z_][\w$.]*)`;

/** What may stand before a whole operand: a paren, a comma, `and` or `or`. */
const STARTS_OPERAND = /(?:^|\(|,|\band|\bor)\s*$/i;

const BETWEEN = new RegExp(
  String.raw`(${OPERAND})\s+between\s+(${BOUND})\s+and\s+(${BOUND})`,
  "gi",
);

/**
 * `x between a and b` as `x >= a and x <= b` inside every `check (...)`. A
 * range inside a larger `and` re-parses differently in a schema diff, so the
 * compound range is written out. `not between` stays: it has no flat form that
 * keeps the operand once.
 */
export function rangeChecks(sql: string): string {
  let out = "";
  let cursor = 0;

  for (const match of sql.matchAll(CHECK)) {
    const open = match.index + match[0].length - 1;

    if (open < cursor) {
      continue;
    }

    const close = closingParen(sql, open);

    if (close === -1) {
      break;
    }

    const inner = sql
      .slice(open + 1, close)
      .replaceAll(
        BETWEEN,
        (
          whole: string,
          operand: string,
          low: string,
          high: string,
          at: number,
          text: string,
        ) =>
          operand.toLowerCase() !== "not" &&
          STARTS_OPERAND.test(text.slice(0, at))
            ? `${operand} >= ${low} and ${operand} <= ${high}`
            : whole,
      );

    out += sql.slice(cursor, open + 1) + inner;
    cursor = close;
  }

  return out + sql.slice(cursor);
}
