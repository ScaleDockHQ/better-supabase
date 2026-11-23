import type { ScanToken } from "@supabase/pg-parser";

/**
 * The word a scan token reads as when looking for statement ends: a keyword in
 * lower case, a single-character token (`ASCII_59` is `;`) as written, and `""`
 * for names, literals and operators, so a quoted `"begin"` or a `';'` string
 * never counts.
 */
export function scanWord(token: ScanToken): string {
  if (token.keywordKind !== "none") {
    return token.text.toLowerCase();
  }

  return token.kind.startsWith("ASCII_") ? token.text : "";
}

function ends(words: readonly string[], nested: boolean): Set<number> {
  const found = new Set<number>();
  let parens = 0;
  let blocks = 0;
  let previous = "";

  for (const [at, word] of words.entries()) {
    if (word === ";") {
      if (!nested || (parens === 0 && blocks === 0)) {
        found.add(at);
      }
    } else if (word === "(") {
      parens += 1;
    } else if (word === ")") {
      parens = Math.max(0, parens - 1);
    } else if (word === "atomic" && previous === "begin") {
      blocks += 1;
    } else if (blocks > 0 && word === "case") {
      blocks += 1;
    } else if (blocks > 0 && word === "end") {
      blocks -= 1;
    }

    previous = word;
  }

  if (nested && (parens !== 0 || blocks !== 0)) {
    return ends(words, false);
  }

  return found;
}

/**
 * The indexes of the semicolons that end a statement: those outside parentheses
 * (a multi-action rule, `do also (...; ...)`) and outside a SQL-standard
 * function body (`begin atomic ... end`, whose `case` expressions close with
 * `end` too). A text whose nesting never closes, which does not parse anyway,
 * ends at every semicolon so the statements after a typo are still read.
 *
 * @param words - The code tokens in order: keywords in lower case and
 *   punctuation as written, `""` for anything else (see `scanWord`).
 * @returns The token indexes of the ending semicolons.
 */
export function statementEnds(words: readonly string[]): ReadonlySet<number> {
  return ends(words, true);
}
