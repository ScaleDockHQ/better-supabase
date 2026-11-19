import type { DoctorContext, FindingInput, Rule, TextFile } from "./rules.ts";

import { writtenByBlocks } from "../sql-layout.ts";

const RAISE = /raise\s+exception\b/iu;

/**
 * The raise statement from `start` to its closing `;`, skipping `;` inside a
 * string, so a `using` list spread over many lines is read whole.
 */
function statementFrom(text: string, start: number): string {
  let quoted = false;

  for (let at = start; at < text.length; at += 1) {
    if (text[at] === "'") {
      quoted = !quoted;
    } else if (text[at] === ";" && !quoted) {
      return text.slice(start, at);
    }
  }

  return text.slice(start);
}

/** A raise in schema SQL that does not name a stable hint code. */
export function raisesWithoutCode(file: TextFile): readonly FindingInput[] {
  const lines = file.text.split("\n");
  let offset = 0;

  return lines.flatMap((line, index): FindingInput[] => {
    const start = offset;

    offset += line.length + 1;

    const trimmed = line.trim();
    const raise = RAISE.exec(line);

    const window =
      raise === null ? "" : statementFrom(file.text, start + raise.index);

    if (
      trimmed.startsWith("--") ||
      raise === null ||
      /hint\s*=/iu.test(window)
    ) {
      return [];
    }

    return [
      {
        message: `${file.path}:${String(index + 1)} raises without a hint code. Pass the stable code as hint, as fail(code, message) does, so an app can translate it.`,
        target: file.path,
      },
    ];
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
