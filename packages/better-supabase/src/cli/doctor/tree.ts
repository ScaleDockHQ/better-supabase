/**
 * Facts the source rules read from the syntax tree of one file: the module
 * specifiers it imports, the directives that open it and the calls it makes. A
 * comment, a string or a type annotation never counts.
 */
import type { Node } from "oxc-parser";

import { walk } from "oxc-walker";

import { lineColumn, parseSource } from "../config-document/parse.ts";

/** One module specifier, with the line it is written on. */
export interface SpecifierSite {
  readonly specifier: string;
  readonly line: number;
}

/**
 * Every specifier of a static import or export-from and every `import("...")`
 * with a string argument, in source order.
 */
export function moduleSpecifiers(text: string): SpecifierSite[] {
  const found: SpecifierSite[] = [];

  const add = (source: Node): void => {
    if (source.type === "Literal" && typeof source.value === "string") {
      found.push({
        specifier: source.value,
        line: lineColumn(text, source.start).line,
      });
    }
  };

  walk(parseSource(text).program, {
    enter(node) {
      if (node.type === "ImportDeclaration") {
        add(node.source);
      } else if (
        (node.type === "ExportNamedDeclaration" ||
          node.type === "ExportAllDeclaration") &&
        node.source !== null
      ) {
        add(node.source);
      } else if (node.type === "ImportExpression") {
        add(node.source);
      }
    },
  });

  return found;
}

/** Whether `directive` is in the directive prologue that opens the file. */
export function hasDirective(text: string, directive: string): boolean {
  for (const statement of parseSource(text).program.body) {
    if (
      statement.type !== "ExpressionStatement" ||
      typeof statement.directive !== "string"
    ) {
      return false;
    }

    if (statement.directive === directive) {
      return true;
    }
  }

  return false;
}

/** The name a call goes by: `f(` or `a.f(`. */
function calleeName(callee: Node): string | undefined {
  if (callee.type === "Identifier") {
    return callee.name;
  }

  return callee.type === "MemberExpression" &&
    !callee.computed &&
    callee.property.type === "Identifier"
    ? callee.property.name
    : undefined;
}

/** The line of the first call of `name`, as `name(` or `object.name(`. */
export function firstCallLine(text: string, name: string): number | undefined {
  let line: number | undefined;

  walk(parseSource(text).program, {
    enter(node) {
      if (
        line === undefined &&
        node.type === "CallExpression" &&
        calleeName(node.callee) === name
      ) {
        line = lineColumn(text, node.start).line;
      }
    },
  });

  return line;
}

/** Whether code uses `name` as an identifier or as a whole string. */
export function mentionsExactly(text: string, name: string): boolean {
  let found = false;

  walk(parseSource(text).program, {
    enter(node) {
      found ||=
        (node.type === "Identifier" && node.name === name) ||
        (node.type === "Literal" && node.value === name);
    },
  });

  return found;
}

/**
 * Whether a call goes by one of `names`, as `name(` and, unless `plain`,
 * `a.name(`.
 */
export function callsAny(
  text: string,
  names: readonly string[],
  plain = false,
): boolean {
  let found = false;

  walk(parseSource(text).program, {
    enter(node) {
      if (found || node.type !== "CallExpression") {
        return;
      }

      const name = plain
        ? node.callee.type === "Identifier"
          ? node.callee.name
          : undefined
        : calleeName(node.callee);

      found = name !== undefined && names.includes(name);
    },
  });

  return found;
}

/**
 * Whether code names `name`: an identifier, a property, or a string or template
 * that holds it. A comment never does.
 */
export function mentionsName(text: string, name: string): boolean {
  let found = false;

  walk(parseSource(text).program, {
    enter(node) {
      if (found) {
        return;
      }

      if (node.type === "Identifier") {
        found = node.name.includes(name);
      } else if (node.type === "Literal") {
        found = typeof node.value === "string" && node.value.includes(name);
      } else if (node.type === "TemplateElement") {
        found = node.value.raw.includes(name);
      }
    },
  });

  return found;
}

/** A chain of names and members such as `blocks.enrichment`, with no call. */
function isPlainPath(node: Node): boolean {
  if (node.type === "Identifier" || node.type === "ThisExpression") {
    return true;
  }

  return (
    node.type === "MemberExpression" &&
    (!node.computed || node.property.type === "Literal") &&
    isPlainPath(node.object)
  );
}

/**
 * Whether an object literal property `key: <path>.with(...)` or `.using(...)`
 * exists for one of `keys`.
 */
export function hasWiredProperty(
  text: string,
  keys: readonly string[],
): boolean {
  let found = false;

  walk(parseSource(text).program, {
    enter(node) {
      if (
        found ||
        node.type !== "Property" ||
        node.computed ||
        node.value.type !== "CallExpression"
      ) {
        return;
      }

      const key =
        node.key.type === "Identifier"
          ? node.key.name
          : node.key.type === "Literal" && typeof node.key.value === "string"
            ? node.key.value
            : undefined;

      const callee = node.value.callee;

      found =
        key !== undefined &&
        keys.includes(key) &&
        callee.type === "MemberExpression" &&
        !callee.computed &&
        callee.property.type === "Identifier" &&
        (callee.property.name === "with" || callee.property.name === "using") &&
        isPlainPath(callee.object);
    },
  });

  return found;
}

/** The line of the first node of the tree that `test` accepts. */
export function findLine(
  text: string,
  test: (node: Node) => boolean,
): number | undefined {
  let line: number | undefined;

  walk(parseSource(text).program, {
    enter(node) {
      if (line === undefined && test(node)) {
        line = lineColumn(text, node.start).line;
      }
    },
  });

  return line;
}

/** A call written `name(` or `object.name(`. */
export function isCallOf(node: Node, ...names: readonly string[]): boolean {
  if (node.type !== "CallExpression") {
    return false;
  }

  const name = calleeName(node.callee);

  return name !== undefined && names.includes(name);
}

/**
 * A call to `<anything>.<owner>.<method>(`, or `<owner>().<method>(`: the
 * `.functions.invoke(` and `functions().invoke(` spellings.
 */
export function isMemberCall(
  node: Node,
  owner: string,
  method: string,
): boolean {
  if (
    node.type !== "CallExpression" ||
    node.callee.type !== "MemberExpression" ||
    node.callee.computed ||
    node.callee.property.type !== "Identifier" ||
    node.callee.property.name !== method
  ) {
    return false;
  }

  const object = node.callee.object;

  if (object.type === "MemberExpression") {
    return (
      !object.computed &&
      object.property.type === "Identifier" &&
      object.property.name === owner
    );
  }

  return (
    object.type === "CallExpression" &&
    object.callee.type === "Identifier" &&
    object.callee.name === owner
  );
}

/** A property `key: "value"` whose value is a plain string or template. */
export function isStringProperty(
  node: Node,
  key: string,
  value: string,
): boolean {
  if (node.type !== "Property" || node.computed) {
    return false;
  }

  const name =
    node.key.type === "Identifier"
      ? node.key.name
      : node.key.type === "Literal"
        ? node.key.value
        : undefined;

  if (name !== key) {
    return false;
  }

  const found = node.value;

  if (found.type === "Literal") {
    return found.value === value;
  }

  return (
    found.type === "TemplateLiteral" &&
    found.expressions.length === 0 &&
    found.quasis[0]?.value.cooked === value
  );
}

/** An import or export-from of `specifier`. */
export function isModuleOf(node: Node, specifier: string): boolean {
  return (
    (node.type === "ImportDeclaration" ||
      ((node.type === "ExportNamedDeclaration" ||
        node.type === "ExportAllDeclaration") &&
        node.source !== null)) &&
    node.source?.value === specifier
  );
}

/** A call written `object.name(`, with no bare `name(`. */
export function isMethodCall(node: Node, ...names: readonly string[]): boolean {
  return (
    node.type === "CallExpression" &&
    node.callee.type === "MemberExpression" &&
    isCallOf(node, ...names)
  );
}
