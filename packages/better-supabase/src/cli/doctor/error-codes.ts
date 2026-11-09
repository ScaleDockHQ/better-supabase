import type { DoctorContext, FindingInput, Rule, TextFile } from "./rules.ts";

const RAISE = /raise\s+exception\b/iu;

/** A raise in schema SQL that does not name a stable hint code. */
export function raisesWithoutCode(file: TextFile): readonly FindingInput[] {
  const lines = file.text.split("\n");

  return lines.flatMap((line, index): FindingInput[] => {
    const trimmed = line.trim();
    // The hint often sits on the following `using` line.
    const window = lines.slice(index, index + 3).join(" ");

    if (
      trimmed.startsWith("--") ||
      !RAISE.test(line) ||
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
        file.path.includes("/migrations/") ? [] : raisesWithoutCode(file),
      ),
  },
];
