import { createTwoFilesPatch } from "diff";

import { type Paint, plain } from "./style.ts";

/** Diff lines shown per file; the rest are counted. */
export const DIFF_LINES = 40;

function paintLine(line: string, paint: Paint): string {
  if (line.startsWith("---") || line.startsWith("+++"))
    return paint("bold", line);
  if (line.startsWith("@@")) return paint("cyan", line);
  if (line.startsWith("+")) return paint("green", line);
  if (line.startsWith("-")) return paint("red", line);
  return line;
}

/** A unified diff from the file on disk (`current`, missing when `undefined`) to `next`, capped at `DIFF_LINES`. */
export function fileDiff(
  path: string,
  current: string | undefined,
  next: string,
  paint: Paint = plain,
): string {
  const lines = createTwoFilesPatch(
    path,
    path,
    current ?? "",
    next,
    current === undefined ? "missing" : "on disk",
    "generated",
    { context: 2 },
  )
    .split("\n")
    .filter(
      (line) =>
        line !== "" && !line.startsWith("=====") && !line.startsWith("Index:"),
    );
  const shown = lines
    .slice(0, DIFF_LINES)
    .map((line) => paintLine(line, paint));
  const hidden = lines.length - shown.length;
  return [
    ...shown,
    ...(hidden > 0 ? [paint("dim", `... ${hidden} more diff lines`)] : []),
  ].join("\n");
}
