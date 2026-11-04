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

/**
 * `export const name = /*#__PURE__*\/ callee(args);` as the formatter prints
 * it: on one line when it fits, else one argument per line. The annotation lets
 * a bundler drop the binding when nothing imports it.
 */
export function pureExport(
  name: string,
  callee: string,
  args: readonly string[],
): string[] {
  const head = `export const ${name} = /*#__PURE__*/ ${callee}`;
  const flat = `${head}(${args.join(", ")});`;

  if (flat.length <= WIDTH) {
    return [flat];
  }

  if (`${head}(`.length <= WIDTH) {
    return [`${head}(`, ...args.map((arg) => `  ${arg},`), ");"];
  }

  return [
    `export const ${name} =`,
    `  /*#__PURE__*/ ${callee}(`,
    ...args.map((arg) => `    ${arg},`),
    "  );",
  ];
}
