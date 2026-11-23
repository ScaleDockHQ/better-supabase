import type { DoctorContext, FindingInput, Rule, TextFile } from "./rules.ts";

import { codeStatementsOf, wordsAt } from "../schema-reader/index.ts";
import { writtenByBlocks } from "../sql-layout.ts";

/**
 * A raise in schema SQL that does not name a stable hint code. The tokens of
 * the function bodies are read in place, so a comment or a string that says
 * `raise exception` is not a raise.
 */
export function raisesWithoutCode(file: TextFile): readonly FindingInput[] {
  return codeStatementsOf(file.text).flatMap((statement) => {
    const { tokens } = statement;

    return tokens.flatMap((token, at): FindingInput[] => {
      if (!wordsAt(tokens, at, "raise", "exception")) {
        return [];
      }

      let end = at;

      while (
        end < tokens.length &&
        !(tokens[end]!.text === ";" && tokens[end]!.depth === token.depth)
      ) {
        end += 1;
      }

      const hinted = tokens
        .slice(at, end)
        .some(
          (_word, index, window) =>
            wordsAt(window, index, "hint") && window[index + 1]?.text === "=",
        );

      return hinted
        ? []
        : [
            {
              message: `${file.path}:${String(token.line)} raises without a hint code. Pass the stable code as hint, as fail(code, message) does, so an app can translate it.`,
              target: file.path,
            },
          ];
    });
  });
}

export const ERROR_CODE_RULES: readonly Rule[] = [
  {
    code: "BS627",
    severity: "warning",
    title: "A raise has no stable code",
    description:
      "A raise exception without a hint leaves the app matching English message text. The hint is the stable code from `better-supabase codes --json`.",
    check: (context: DoctorContext): FindingInput[] =>
      (context.sqlFiles ?? []).flatMap((file) =>
        file.path.includes("/migrations/") || writtenByBlocks(file)
          ? []
          : raisesWithoutCode(file),
      ),
  },
];
