import { q } from "./shared.ts";

/** The repo formatter's print width; generated files must print the same. */
const WIDTH = 80;

const SPECIFIER = / from "([^"]+)";$/;

function specifier(line: string): string {
  return SPECIFIER.exec(line)?.[1] ?? line;
}

/** Import statements in the formatter's order: by module specifier. */
export function sortImports(lines: readonly string[]): string[] {
  return lines.toSorted((a, b) => specifier(a).localeCompare(specifier(b)));
}

/**
 * Where the formatter groups a value import: with the packages, with the repo's
 * internal aliases (`@/`, `@better-supabase/`), or with the relative imports
 * after them.
 */
export function importGroup(
  from: string,
): "external" | "internal" | "relative" {
  if (from.startsWith(".")) {
    return "relative";
  }

  return from.startsWith("@/") || from.startsWith("@better-supabase/")
    ? "internal"
    : "external";
}

/** `import { … } from "…";`, one name per line when it is wider than 80. */
export function importStatement(
  names: readonly string[],
  from: string,
): string[] {
  const line = `import { ${names.join(", ")} } from ${q(from)};`;

  if (line.length <= WIDTH) {
    return [line];
  }

  return [
    "import {",
    ...names.map((name) => `  ${name},`),
    `} from ${q(from)};`,
  ];
}

/** A JSDoc comment filled to 80 columns, on one line when it fits. */
export function docComment(text: string): string[] {
  const single = `/** ${text} */`;

  if (single.length <= WIDTH) {
    return [single];
  }

  const lines: string[] = [];
  let line = " *";

  for (const word of text.split(" ")) {
    if (line.length + 1 + word.length > WIDTH && line !== " *") {
      lines.push(line);
      line = " *";
    }

    line += ` ${word}`;
  }

  return ["/**", ...lines, line, " */"];
}

function call(
  callee: string,
  args: readonly string[],
  indent: string,
): string[] {
  return [
    `${callee}(`,
    ...args.map((arg) => `${indent}  ${arg},`),
    `${indent});`,
  ];
}

/**
 * `export const { key: name, … } = callee(args);` laid out as the formatter
 * prints it: on one line, then with the arguments broken, then broken after
 * `=`, and with the pattern broken when it is wider than 80 on its own.
 */
export function destructuredCall(
  bindings: readonly (readonly [key: string, name: string])[],
  callee: string,
  args: readonly string[],
): string[] {
  const pattern = bindings.map(([key, name]) => `${key}: ${name}`);
  const head = `export const { ${pattern.join(", ")} } =`;
  const flat = `${callee}(${args.join(", ")});`;

  if (head.length > WIDTH) {
    const tail = `} = ${flat}`;
    const opened = ["export const {", ...pattern.map((entry) => `  ${entry},`)];

    if (tail.length <= WIDTH) {
      return [...opened, tail];
    }

    const [first = "", ...rest] = call(callee, args, "");

    return [...opened, `} = ${first}`, ...rest];
  }

  if (`${head} ${flat}`.length <= WIDTH) {
    return [`${head} ${flat}`];
  }

  if (`${head} ${callee}(`.length <= WIDTH) {
    const [first = "", ...rest] = call(callee, args, "");

    return [`${head} ${first}`, ...rest];
  }

  if (`  ${flat}`.length <= WIDTH) {
    return [head, `  ${flat}`];
  }

  const [first = "", ...rest] = call(callee, args, "  ");

  return [head, `  ${first}`, ...rest];
}
