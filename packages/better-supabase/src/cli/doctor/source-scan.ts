/**
 * The parse tree of one source file, shared by the code checks: its calls,
 * functions, declarations, loops and object properties with offsets into the
 * text, the code with strings and comments blanked, and line-independent
 * finding targets. Nothing here matches brackets or functions with a regular
 * expression, so a regex literal with a quote, a nested template literal or JSX
 * text cannot hide code or invent it.
 */
import type { CallExpression, ForOfStatement, Node, Program } from "oxc-parser";

import { walk } from "oxc-walker";

import { parseSource } from "../config-document/parse.ts";
import { codeRangesIn } from "../config-document/ranges.ts";

/** A call, with where it opens and closes and the callee written as a path. */
export interface CallSite {
  readonly node: CallExpression;
  readonly start: number;
  /** The offset of the `(` that opens the arguments. */
  readonly open: number;
  /** The offset of the `)` that closes them. */
  readonly close: number;
  /** The `)` of the last call in a chain such as `.from(x).select().eq()`. */
  readonly chainClose: number;
  /**
   * The callee as `db.customers.get`: `name()` for a call without arguments and
   * `name(...)` for one with, so `bsb.db().customers.get` and
   * `supabase.from(...).select` read as written. Undefined for a callee that is
   * not a chain of names.
   */
  readonly path: string | undefined;
  /** The source offset of each name in `path`, by its index there. */
  readonly names: ReadonlyMap<number, number>;
}

/** A named function and its body, for target keys. */
export interface NamedFunction {
  readonly name: string;
  readonly start: number;
  readonly end: number;
  /**
   * `const reorder = tenantAction(..., async () => {...})`: the call, used when
   * no function names the code.
   */
  readonly wrapped?: true;
  /**
   * Written as `function name()` or `const name = () => {}`, with no wrapper
   * call around the function.
   */
  readonly local?: true;
}

/** `const name = init`, with the names the binding declares. */
export interface Declaration {
  readonly start: number;
  readonly names: readonly string[];
  /** The binding pattern: `rows`, `{ a, b }` or `[first, second]`. */
  readonly pattern: Node;
  readonly init: Node;
  /** The end of the block the declaration sits in. */
  readonly scopeEnd: number;
}

/** `key: value` in an object literal. */
export interface PropertySite {
  readonly key: string;
  readonly start: number;
  readonly valueStart: number;
  readonly valueEnd: number;
}

export interface SourceModel {
  readonly text: string;
  /** `text` with strings, comments, regular expressions and JSX text blanked. */
  readonly code: string;
  readonly program: Program;
  readonly calls: readonly CallSite[];
  readonly functions: readonly NamedFunction[];
  readonly declarations: readonly Declaration[];
  readonly loops: readonly ForOfStatement[];
  readonly properties: readonly PropertySite[];
  /** Names declared with a service or repository type. */
  readonly typedServices: ReadonlySet<string>;
}

/** The string a non-computed key or a string literal holds. */
function keyText(node: Node): string | undefined {
  if (node.type === "Identifier") {
    return node.name;
  }

  return node.type === "Literal" && typeof node.value === "string"
    ? node.value
    : undefined;
}

/** The names a binding pattern declares: `x`, `{ a, b: c }`, `[d, ...e]`. */
export function bindingNames(pattern: Node | null | undefined): string[] {
  if (pattern === null || pattern === undefined) {
    return [];
  }

  if (pattern.type === "Identifier") {
    return [pattern.name];
  }

  if (pattern.type === "ObjectPattern") {
    return pattern.properties.flatMap((property) =>
      bindingNames(property.type === "Property" ? property.value : property),
    );
  }

  if (pattern.type === "ArrayPattern") {
    return pattern.elements.flatMap((element) => bindingNames(element));
  }

  if (pattern.type === "AssignmentPattern") {
    return bindingNames(pattern.left);
  }

  if (pattern.type === "RestElement") {
    return bindingNames(pattern.argument);
  }

  return pattern.type === "TSParameterProperty"
    ? bindingNames(pattern.parameter)
    : [];
}

/** The expression under `await`, parentheses, `as` and `!`. */
export function unwrap(node: Node): Node {
  if (node.type === "AwaitExpression") {
    return unwrap(node.argument);
  }

  return node.type === "ParenthesizedExpression" ||
    node.type === "ChainExpression" ||
    node.type === "TSAsExpression" ||
    node.type === "TSSatisfiesExpression" ||
    node.type === "TSNonNullExpression"
    ? unwrap(node.expression)
    : node;
}

const SERVICE_TYPE = /(?:Services?|Repositor(?:y|ies)|Repos?|Queries)$/;

function typeName(name: Node): string | undefined {
  if (name.type === "Identifier") {
    return name.name;
  }

  return name.type === "TSQualifiedName" ? name.right.name : undefined;
}

/** `CustomersService` and `Readonly<CustomersService>`, not `Service[]`. */
function isServiceType(annotation: Node | null | undefined): boolean {
  if (annotation?.type !== "TSTypeAnnotation") {
    return false;
  }

  const type = annotation.typeAnnotation;

  if (type.type !== "TSTypeReference") {
    return false;
  }

  const name = typeName(type.typeName);
  const params = type.typeArguments?.params;

  if (name === "Readonly" && params?.length === 1) {
    const [inner] = params;

    return (
      inner?.type === "TSTypeReference" &&
      inner.typeArguments === null &&
      SERVICE_TYPE.test(typeName(inner.typeName) ?? "")
    );
  }

  return params === undefined && name !== undefined && SERVICE_TYPE.test(name);
}

/**
 * What names the function `fn`: `const load = async () => {}`, `load: () =>
 * {}`, `load() {}`, `const load = cache(async () => {})`. `stack` ends at
 * `fn`.
 */
function functionName(fn: Node, stack: readonly Node[]): string | undefined {
  if (
    (fn.type === "FunctionDeclaration" || fn.type === "FunctionExpression") &&
    fn.id
  ) {
    return fn.id.name;
  }

  let current: Node = fn;

  for (let index = stack.length - 2; index >= 0; index -= 1) {
    const parent = stack[index]!;

    if (parent.type === "CallExpression" && parent.arguments[0] === current) {
      current = parent;
      continue;
    }

    if (parent.type === "VariableDeclarator") {
      return parent.init === current && parent.id.type === "Identifier"
        ? parent.id.name
        : undefined;
    }

    if (parent.type === "AssignmentExpression") {
      if (parent.right !== current) {
        return undefined;
      }

      if (parent.left.type === "Identifier") {
        return parent.left.name;
      }

      return parent.left.type === "MemberExpression" &&
        !parent.left.computed &&
        parent.left.property.type === "Identifier"
        ? parent.left.property.name
        : undefined;
    }

    if (
      parent.type === "Property" ||
      parent.type === "PropertyDefinition" ||
      parent.type === "MethodDefinition"
    ) {
      return !parent.computed &&
        (parent.type === "MethodDefinition" || parent.value === current)
        ? keyText(parent.key)
        : undefined;
    }

    return undefined;
  }

  return undefined;
}

/** The callee as a path, with the offset of each name in it. */
function calleeOf(
  node: Node,
): { path: string; names: Map<number, number> } | undefined {
  const names = new Map<number, number>();

  const build = (current: Node): string | undefined => {
    if (current.type === "Identifier") {
      names.set(0, current.start);

      return current.name;
    }

    if (current.type === "ThisExpression") {
      return "this";
    }

    if (
      current.type === "ChainExpression" ||
      current.type === "ParenthesizedExpression" ||
      current.type === "TSNonNullExpression"
    ) {
      return build(current.expression);
    }

    if (current.type === "MemberExpression") {
      const object = build(current.object);

      if (
        object === undefined ||
        current.computed ||
        current.property.type !== "Identifier"
      ) {
        return undefined;
      }

      names.set(object.length + 1, current.property.start);

      return `${object}.${current.property.name}`;
    }

    if (current.type === "CallExpression") {
      const callee = build(current.callee);

      return callee === undefined
        ? undefined
        : `${callee}(${current.arguments.length > 0 ? "..." : ""})`;
    }

    return undefined;
  };

  const path = build(node);

  return path === undefined ? undefined : { path, names };
}

const BLOCKS = new Set([
  "BlockStatement",
  "Program",
  "StaticBlock",
  "TSModuleBlock",
]);

/** Parses `text` once and collects what the checks read from the tree. */
export function sourceModel(text: string): SourceModel {
  const parsed = parseSource(text);
  const { program } = parsed;

  let code = "";
  let last = 0;
  const blank = (part: string): string => part.replaceAll(/[^\n]/g, " ");

  for (const [start, end] of codeRangesIn(parsed, text.length)) {
    code += blank(text.slice(last, start)) + text.slice(start, end);
    last = end;
  }

  code += blank(text.slice(last));

  const calls: CallSite[] = [];
  const functions: NamedFunction[] = [];
  const declarations: Declaration[] = [];
  const loops: ForOfStatement[] = [];
  const properties: PropertySite[] = [];
  const typedServices = new Set<string>();
  const stack: Node[] = [];

  walk(program, {
    enter(node) {
      stack.push(node);

      if (node.type === "CallExpression") {
        const callee = calleeOf(node.callee);
        let chainClose = node.end - 1;
        let current: Node = node;

        for (let index = stack.length - 1; index >= 2; index -= 2) {
          const member = stack[index - 1]!;
          const call = stack[index - 2]!;

          if (
            member.type === "MemberExpression" &&
            member.object === current &&
            call.type === "CallExpression" &&
            call.callee === member
          ) {
            chainClose = call.end - 1;
            current = call;
          } else {
            break;
          }
        }

        calls.push({
          node,
          start: node.start,
          open: text.indexOf("(", (node.typeArguments ?? node.callee).end),
          close: node.end - 1,
          chainClose,
          path: callee?.path,
          names: callee?.names ?? new Map(),
        });
      }

      if (
        node.type === "FunctionDeclaration" ||
        node.type === "FunctionExpression" ||
        node.type === "ArrowFunctionExpression"
      ) {
        const name = functionName(node, stack);

        if (name !== undefined && node.body) {
          const parent = stack.at(-2);

          const local =
            node.type === "FunctionDeclaration" ||
            (parent?.type === "VariableDeclarator" && parent.init === node) ||
            (node.type === "FunctionExpression" && node.id !== null);

          functions.push({
            name,
            start: node.body.start,
            end: node.body.end,
            ...(local ? { local: true as const } : {}),
          });
        }
      }

      if (node.type === "VariableDeclarator") {
        const scope = stack.findLast((item) => BLOCKS.has(item.type));

        if (node.init) {
          declarations.push({
            start: node.start,
            names: bindingNames(node.id),
            pattern: node.id,
            init: node.init,
            scopeEnd: scope?.end ?? text.length,
          });
        }

        if (node.id.type === "Identifier" && node.init) {
          const init = unwrap(node.init);

          if (init.type === "CallExpression") {
            functions.push({
              name: node.id.name,
              start: init.start,
              end: init.end,
              wrapped: true,
            });
          }
        }
      }

      if (node.type === "AssignmentExpression") {
        const init = unwrap(node.right);

        if (node.left.type === "Identifier" && init.type === "CallExpression") {
          functions.push({
            name: node.left.name,
            start: init.start,
            end: init.end,
            wrapped: true,
          });
        }
      }

      if (node.type === "ForOfStatement") {
        loops.push(node);
      }

      if (node.type === "Property") {
        const key = node.computed ? undefined : keyText(node.key);

        if (key !== undefined && !node.shorthand && !node.method) {
          properties.push({
            key,
            start: node.start,
            valueStart: node.value.start,
            valueEnd: node.value.end,
          });
        }
      }

      if (node.type === "Identifier" && isServiceType(node.typeAnnotation)) {
        typedServices.add(node.name);
      }

      if (
        node.type === "TSPropertySignature" ||
        node.type === "PropertyDefinition"
      ) {
        const key = node.computed ? undefined : keyText(node.key);

        if (key !== undefined && isServiceType(node.typeAnnotation)) {
          typedServices.add(key);
        }
      }
    },
    leave() {
      stack.pop();
    },
  });

  return {
    text,
    code,
    program,
    calls,
    functions,
    declarations,
    loops,
    properties,
    typedServices,
  };
}

/** The innermost named function around `at`, or `<module>`. */
function functionAt(functions: readonly NamedFunction[], at: number): string {
  const inside = functions.filter(
    (candidate) => candidate.start <= at && at < candidate.end,
  );

  const named = inside.filter((candidate) => candidate.wrapped !== true);
  const size = (item: NamedFunction): number => item.end - item.start;

  // The innermost function, or else the outermost wrapper: the export.
  const found =
    named.length > 0
      ? named.reduce((a, b) => (size(b) < size(a) ? b : a))
      : inside.reduce<NamedFunction | undefined>(
          (a, b) => (a === undefined || size(b) > size(a) ? b : a),
          undefined,
        );

  return found?.name ?? "<module>";
}

/**
 * Line-independent targets: `path#function:callee`, with `#2`, `#3` for the
 * second and later call of the same callee in one function. An edit elsewhere
 * in the file keeps them.
 */
export function targetKeys(
  path: string,
  functions: readonly NamedFunction[],
  calls: readonly { readonly start: number; readonly callee: string }[],
): Map<number, string> {
  const seen = new Map<string, number>();
  const keys = new Map<number, string>();

  for (const call of calls.toSorted((a, b) => a.start - b.start)) {
    const key = `${path}#${functionAt(functions, call.start)}:${call.callee}`;
    const count = (seen.get(key) ?? 0) + 1;

    seen.set(key, count);
    keys.set(call.start, count === 1 ? key : `${key}#${String(count)}`);
  }

  return keys;
}
