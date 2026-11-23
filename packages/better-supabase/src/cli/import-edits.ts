import type { MagicString } from "magic-string";
import type { Program } from "oxc-parser";

const importedName = (specifier: {
  readonly imported: {
    readonly type: string;
    readonly name?: string;
    readonly value?: unknown;
  };
}): string | undefined =>
  specifier.imported.type === "Identifier"
    ? specifier.imported.name
    : typeof specifier.imported.value === "string"
      ? specifier.imported.value
      : undefined;

/**
 * Adds `names` to the imports of `module` through `out`, which edits the text
 * `program` was parsed from. The names join an existing value import of the
 * module (a default import gets a `{ ... }` clause, a namespace import gets a
 * statement of its own), and a file without one gets `import { a, b } from
 * "module";` after its last import, or at the top. A name the file already
 * imports is left alone. A file with no import gets the statement after its
 * leading directive (`"use client"`) so the file keeps its header. Every
 * codemod that adds an import goes through here, so the output is the same for
 * all of them.
 */
export function addNamedImports(
  out: MagicString,
  program: Program,
  module: string,
  names: readonly string[],
  eol = "\n",
): void {
  const imports = program.body.filter(
    (statement) => statement.type === "ImportDeclaration",
  );

  const existing = imports.find(
    (statement) =>
      statement.source.value === module &&
      statement.importKind !== "type" &&
      !statement.specifiers.some(
        (specifier) => specifier.type === "ImportNamespaceSpecifier",
      ),
  );

  const statement = `import { ${names.join(", ")} } from "${module}";`;

  if (existing === undefined) {
    const last =
      imports.at(-1) ??
      program.body.findLast(
        (each) =>
          each.type === "ExpressionStatement" && each.directive !== null,
      );

    if (last === undefined) {
      out.prepend(`${statement}${eol}`);
    } else {
      out.appendLeft(last.end, `${eol}${statement}`);
    }

    return;
  }

  const have = new Set(
    existing.specifiers.flatMap((specifier) =>
      specifier.type === "ImportSpecifier" && specifier.importKind !== "type"
        ? [importedName(specifier)]
        : [],
    ),
  );

  const missing = names.filter((name) => !have.has(name));

  if (missing.length === 0) {
    return;
  }

  const named = existing.specifiers.filter(
    (specifier) => specifier.type === "ImportSpecifier",
  );

  const last = named.at(-1);

  if (last !== undefined) {
    out.appendLeft(last.end, `, ${missing.join(", ")}`);
  } else if (existing.specifiers.length === 0) {
    out.overwrite(
      existing.start,
      existing.end,
      `import { ${missing.join(", ")} } from "${module}";`,
    );
  } else {
    const [first] = existing.specifiers;

    out.appendLeft(first!.end, `, { ${missing.join(", ")} }`);
  }
}
