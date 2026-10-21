import { styleText } from "node:util";

export type Format = Parameters<typeof styleText>[0];

/** Styles text, or returns it unchanged when colors are off. */
export type Paint = (format: Format, text: string) => string;

export const plain: Paint = (_format, text) => text;

const colored: Paint = (format, text) =>
  styleText(format, text, { validateStream: false });

export function painter(color: boolean | undefined): Paint {
  return color === true ? colored : plain;
}

/**
 * Whether `stream` takes colors: a TTY, and neither `NO_COLOR` nor
 * `NODE_DISABLE_COLORS` set (`FORCE_COLOR` overrides).
 */
export function colorEnabled(stream: NodeJS.WritableStream): boolean {
  return styleText("red", "x", { stream }) !== "x";
}

const VERBS: readonly (readonly [RegExp, Format])[] = [
  [/^(?:Wrote|Created|Updated|Removed)\b/, "green"],
  [/^Would (?:write|create|update|remove)\b/, "yellow"],
  [/^(?:Unchanged|Kept|Same|Skipped)\b/, "dim"],
];

/**
 * Colors the verb that starts each `Created`, `Updated`, `Skipped`, `Unchanged`
 * or `Would create` line.
 */
export function highlight(text: string, paint: Paint): string {
  if (paint === plain) {
    return text;
  }

  return text
    .split("\n")
    .map((line) => {
      for (const [pattern, format] of VERBS) {
        const verb = pattern.exec(line)?.[0];

        if (verb) {
          return `${paint(format, verb)}${line.slice(verb.length)}`;
        }
      }

      return line;
    })
    .join("\n");
}
