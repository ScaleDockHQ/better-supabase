import type { CodemodConfigEdit, CodemodResult } from "./codemod.ts";

/** A design file Create downloaded (`better-supabase.design.json`). */
export const DESIGN_FILE_NAME: RegExp = /(?:^|[\\/])[^\\/]*\.design\.json$/;

const reviewOf = (edit: CodemodConfigEdit) =>
  edit.ok && "review" in edit ? edit.review : [];

/** A codemod's `designFile` rewrite as a result; a refusal is listed for review. */
export function designFileResult(
  source: string,
  rewrite: ((source: string) => CodemodConfigEdit) | undefined,
): CodemodResult {
  if (rewrite === undefined) {
    return { text: source, review: [] };
  }

  const edit = rewrite(source);

  return edit.ok
    ? { text: edit.text, review: reviewOf(edit) }
    : {
        text: source,
        review: [
          {
            line: 1,
            message: `The design file wasn't rewritten: ${edit.reason}`,
          },
        ],
      };
}
