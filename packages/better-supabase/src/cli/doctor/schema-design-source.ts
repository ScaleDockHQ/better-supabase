/**
 * What the schema design rules read from app source files, taken from the
 * syntax tree: the supabase-js containment filters, the signs of a serverless
 * app, a postgres.js or Prisma client, and offset pagination or exact counts. A
 * comment or a string that only mentions one of them never counts.
 */
import type { Node } from "oxc-parser";

import { walk } from "oxc-walker";

import { lineColumn, parseSource } from "../config-document/parse.ts";
import { isMethodCall, isStringProperty } from "./tree.ts";

const HTTP_METHODS: ReadonlySet<string> = new Set([
  "GET",
  "POST",
  "PUT",
  "PATCH",
  "DELETE",
]);

const nameOf = (node: Node): string | undefined => {
  if (node.type === "Identifier") {
    return node.name;
  }

  return node.type === "Literal" && typeof node.value === "string"
    ? node.value
    : undefined;
};

const stringOf = (node: Node | undefined): string | undefined =>
  node?.type === "Literal" && typeof node.value === "string"
    ? node.value
    : node?.type === "TemplateLiteral" &&
        node.expressions.length === 0 &&
        node.quasis[0]
      ? (node.quasis[0].value.cooked ?? undefined)
      : undefined;

/** Runs `visit` for every node of the file's tree. */
function each(text: string, visit: (node: Node) => void): void {
  walk(parseSource(text).program, { enter: visit });
}

/** The columns named in `.contains("tags"`, `.containedBy(` and `.overlaps(`. */
export function containmentColumns(text: string): string[] {
  const columns: string[] = [];

  each(text, (node) => {
    if (
      node.type === "CallExpression" &&
      isMethodCall(node, "contains", "containedBy", "overlaps")
    ) {
      const column = stringOf(node.arguments[0]);

      if (column !== undefined && /^[A-Za-z_]\w*$/.test(column)) {
        columns.push(column);
      }
    }
  });

  return columns;
}

/**
 * Whether the file shows the app runs on serverless or edge functions: an
 * exported `runtime` or route handler, a default export with `fetch`, or
 * `Deno.serve(`.
 */
export function isServerlessSource(text: string): boolean {
  let found = false;

  each(text, (node) => {
    if (found) {
      return;
    }

    if (node.type === "ExportNamedDeclaration" && node.declaration) {
      const { declaration } = node;

      found =
        (declaration.type === "VariableDeclaration" &&
          declaration.kind === "const" &&
          declaration.declarations.some(
            (item) =>
              item.id.type === "Identifier" && item.id.name === "runtime",
          )) ||
        (declaration.type === "FunctionDeclaration" &&
          declaration.async &&
          declaration.id !== null &&
          HTTP_METHODS.has(declaration.id.name));
    } else if (
      node.type === "ExportDefaultDeclaration" &&
      node.declaration.type === "ObjectExpression"
    ) {
      found = node.declaration.properties.some(
        (property) =>
          property.type === "Property" &&
          !property.computed &&
          nameOf(property.key) === "fetch",
      );
    } else if (node.type === "CallExpression") {
      found =
        node.callee.type === "MemberExpression" &&
        !node.callee.computed &&
        node.callee.object.type === "Identifier" &&
        node.callee.object.name === "Deno" &&
        node.callee.property.type === "Identifier" &&
        node.callee.property.name === "serve";
    }
  });

  return found;
}

/** The line of the first import or `require` of `module`. */
function moduleUseLine(text: string, module: string): number | undefined {
  let line: number | undefined;

  each(text, (node) => {
    if (line !== undefined) {
      return;
    }

    if (
      (node.type === "ImportDeclaration" &&
        node.source.value === module &&
        node.importKind !== "type") ||
      (node.type === "CallExpression" &&
        node.callee.type === "Identifier" &&
        node.callee.name === "require" &&
        stringOf(node.arguments[0]) === module)
    ) {
      line = lineColumn(text, node.start).line;
    }
  });

  return line;
}

/** The line where the file imports postgres.js, if it does. */
export const postgresJsLine = (text: string): number | undefined =>
  moduleUseLine(text, "postgres");

/** Whether the file sets `prepare: false` anywhere. */
export function turnsPrepareOff(text: string): boolean {
  let found = false;

  each(text, (node) => {
    found ||=
      node.type === "Property" &&
      !node.computed &&
      nameOf(node.key) === "prepare" &&
      node.value.type === "Literal" &&
      node.value.value === false;
  });

  return found;
}

/** Whether the file imports `@prisma/client` or builds `new PrismaClient`. */
export function usesPrisma(text: string): boolean {
  if (moduleUseLine(text, "@prisma/client") !== undefined) {
    return true;
  }

  let found = false;

  each(text, (node) => {
    found ||=
      node.type === "NewExpression" &&
      node.callee.type === "Identifier" &&
      node.callee.name === "PrismaClient";
  });

  return found;
}

/** The lines of the paging and counting choices that scan every row. */
export interface ScaleLines {
  readonly offset: readonly number[];
  readonly exact: readonly number[];
  readonly countMode: readonly number[];
}

/**
 * Lines with `pagination: "offset"`, `count: "exact"` and a `.count()` or
 * `.count({ ... })` call that sets no `mode`, which counts exactly.
 */
export function scaleLines(text: string): ScaleLines {
  const offset = new Set<number>();
  const exact = new Set<number>();
  const countMode = new Set<number>();
  const lineOf = (node: Node): number => lineColumn(text, node.start).line;

  each(text, (node) => {
    if (isStringProperty(node, "pagination", "offset")) {
      offset.add(lineOf(node));
    } else if (isStringProperty(node, "count", "exact")) {
      exact.add(lineOf(node));
    } else if (node.type === "CallExpression" && isMethodCall(node, "count")) {
      const [options] = node.arguments;

      const withoutMode =
        options === undefined ||
        (options.type === "ObjectExpression" &&
          !options.properties.some(
            (property) =>
              property.type === "Property" &&
              !property.computed &&
              nameOf(property.key) === "mode",
          ));

      if (withoutMode) {
        countMode.add(lineOf(node));
      }
    }
  });

  const sorted = (lines: Set<number>): number[] =>
    [...lines].toSorted((a, b) => a - b);

  return {
    offset: sorted(offset),
    exact: sorted(exact),
    countMode: sorted(countMode),
  };
}
