import type {
  ArrayExpression,
  ArrayExpressionElement,
  Expression,
  ImportDeclaration,
  Node,
  ObjectExpression,
  ObjectPropertyKind,
  Program,
  Statement,
} from "oxc-parser";

import { MagicString } from "magic-string";
import { walk } from "oxc-walker";

import type { ParsedModule } from "./parse.ts";

import { parseModule } from "./parse.ts";
import { referencedBindings } from "./scopes.ts";

/** A key of the config: an object key or an array index. */
export type PathSegment = string | number;

/** What the config file looks like, so an edit matches it. */
export interface Style {
  readonly eol: "\n" | "\r\n";
  /** One level of indentation: a tab or some spaces. */
  readonly indent: string;
  readonly quote: '"' | "'";
  /** Whether the config object's last entry ends in a comma. */
  readonly trailingComma: boolean;
}

/** An entry of an object or array, with the container it sits in. */
export interface Located {
  /** The entry as written: a property, or an array element. */
  readonly entry: ObjectPropertyKind | NonNullable<ArrayExpressionElement>;
  /** The value the entry holds, with a variable followed to its declaration. */
  readonly value: Node;
  readonly owner: ObjectExpression | ArrayExpression;
  /** The entries of `owner`, in source order. */
  readonly siblings: readonly Node[];
}

/** The outcome of an edit. `review` carries a line for the person to act on. */
export type EditResult =
  | { readonly status: "done" }
  | { readonly status: "absent" }
  | { readonly status: "review"; readonly review: string };

/** The names the config binds `defineConfig` to. */
const DEFINE_CONFIG = "defineConfig";

const IDENTIFIER = /^[A-Za-z_$][\w$]*$/;

/** `a.b` for a non-computed member expression of identifiers, else undefined. */
function text(node: Node): string | undefined {
  if (node.type === "Identifier") {
    return node.name;
  }

  if (
    node.type === "MemberExpression" &&
    !node.computed &&
    node.property.type === "Identifier"
  ) {
    const object = text(node.object);

    return object === undefined ? undefined : `${object}.${node.property.name}`;
  }

  return undefined;
}

/** `node` without the wrappers that only carry a type or parentheses. */
function unwrap(node: Node): Node {
  if (
    node.type === "TSSatisfiesExpression" ||
    node.type === "TSAsExpression" ||
    node.type === "TSNonNullExpression" ||
    node.type === "TSTypeAssertion" ||
    node.type === "ParenthesizedExpression"
  ) {
    return unwrap(node.expression);
  }

  return node;
}

/** The name an object key or a member names, when it is not computed. */
export function propertyName(property: Node): string | undefined {
  if (property.type !== "Property" || property.computed) {
    return undefined;
  }

  const { key } = property;

  if (key.type === "Identifier") {
    return key.name;
  }

  if (key.type === "Literal") {
    return String(key.value);
  }

  return undefined;
}

const lineStartOf = (text: string, at: number): number =>
  text.lastIndexOf("\n", at - 1) + 1;

/**
 * A TypeScript config file as a tree with text edits. Every edit splices the
 * text and parses it again, so the next lookup never reads a stale range. An
 * edit the document cannot follow returns a `review` line and never changes the
 * text without saying so.
 */
export class ConfigDocument {
  #module: ParsedModule;
  readonly #path: string;
  readonly #before: ReadonlySet<string>;
  readonly #review: string[] = [];
  readonly #wiring: boolean;

  private constructor(module: ParsedModule, path: string, wiring: boolean) {
    this.#module = module;
    this.#path = path;
    this.#wiring = wiring;
    this.#before = referencedBindings(module.program);
  }

  /** Parses `text`. A file that does not parse throws a usage error. */
  static parse(text: string, path = "config.ts"): ConfigDocument {
    return new ConfigDocument(parseModule(text, path), path, false);
  }

  /**
   * Parses `lib/blocks.ts`: the root is the blocks object passed to
   * `defineBlocks(blockConfig, { ... })` or `createBlocks(options, { ... })`.
   */
  static parseWiring(text: string, path = "blocks.ts"): ConfigDocument {
    return new ConfigDocument(parseModule(text, path), path, true);
  }

  /** The text with every edit applied. */
  get text(): string {
    return this.#module.text;
  }

  /** The review lines the edits so far returned, in order. */
  get review(): readonly string[] {
    return this.#review;
  }

  /** Line endings, indentation, quotes and trailing commas of the file. */
  get style(): Style {
    const { text } = this.#module;
    const eol = text.includes("\r\n") ? "\r\n" : "\n";
    const config = this.configObject();
    const first = config?.properties[0];
    let indent = "  ";

    if (first !== undefined) {
      const lead = text.slice(lineStartOf(text, first.start), first.start);

      if (/^[\t ]+$/.test(lead)) {
        indent = lead;
      }
    }

    const single = (text.match(/'[^'\n]*'/g) ?? []).length;
    const double = (text.match(/"[^"\n]*"/g) ?? []).length;
    const last = config?.properties.at(-1);

    return {
      eol,
      indent,
      quote: single > double ? "'" : '"',
      trailingComma:
        last !== undefined && this.#commaAfter(last.end, config!.end) !== -1,
    };
  }

  /** The object literal the default export (or `defineConfig`) holds. */
  configObject(): ObjectExpression | undefined {
    const { program } = this.#module;

    if (this.#wiring) {
      return this.#wiredObject();
    }

    const local = this.#defineConfigNames(program);

    for (const statement of program.body) {
      if (statement.type === "ExportDefaultDeclaration") {
        return this.#asConfig(statement.declaration, local, new Set());
      }

      // `module.exports = defineConfig({ ... })` in a CommonJS file.
      if (
        statement.type === "ExpressionStatement" &&
        statement.expression.type === "AssignmentExpression" &&
        statement.expression.left.type === "MemberExpression" &&
        text(statement.expression.left) === "module.exports"
      ) {
        return this.#asConfig(statement.expression.right, local, new Set());
      }
    }

    // A file that calls `defineConfig(...)` without exporting it.
    return this.defineConfigCalls()[0];
  }

  /**
   * The first `defineBlocks` or `createBlocks` call of a wiring file: its name,
   * and the blocks object it receives when that is a literal.
   */
  wiredCall():
    | { readonly name: string; readonly blocks: ObjectExpression | undefined }
    | undefined {
    let found:
      | { name: string; blocks: ObjectExpression | undefined }
      | undefined;

    walk(this.#module.program, {
      enter: (node: Node): void => {
        if (
          found === undefined &&
          node.type === "CallExpression" &&
          node.callee.type === "Identifier" &&
          (node.callee.name === "defineBlocks" ||
            node.callee.name === "createBlocks")
        ) {
          const second = node.arguments[1];
          const inner = second === undefined ? undefined : unwrap(second);

          found = {
            name: node.callee.name,
            blocks: inner?.type === "ObjectExpression" ? inner : undefined,
          };
        }
      },
    });

    return found;
  }

  /** The second argument of the first `defineBlocks` or `createBlocks` call. */
  #wiredObject(): ObjectExpression | undefined {
    return this.wiredCall()?.blocks;
  }

  /**
   * The object literal each `defineConfig(...)` call in the file receives, in
   * source order, wherever the call sits. A variable is followed to its
   * declaration.
   */
  defineConfigCalls(): readonly ObjectExpression[] {
    const names = this.#defineConfigNames(this.#module.program);
    const found: ObjectExpression[] = [];

    walk(this.#module.program, {
      enter: (node: Node): void => {
        if (
          node.type === "CallExpression" &&
          node.callee.type === "Identifier" &&
          names.has(node.callee.name)
        ) {
          const [argument] = node.arguments;

          const object =
            argument === undefined || argument.type === "SpreadElement"
              ? undefined
              : this.#asConfig(argument, names, new Set());

          if (object !== undefined && !found.includes(object)) {
            found.push(object);
          }
        }
      },
    });

    return found.toSorted((a, b) => a.start - b.start);
  }

  /** The entry at `path`, or undefined when the file has none. */
  locate(path: readonly PathSegment[]): Located | undefined {
    return this.#locateIn(this.configObject(), path);
  }

  #locateIn(
    config: ObjectExpression | undefined,
    path: readonly PathSegment[],
  ): Located | undefined {
    if (config === undefined) {
      return undefined;
    }

    let owner: Node = config;
    let found: Located | undefined;

    for (const segment of path) {
      found = this.#step(owner, segment);

      if (found === undefined) {
        return undefined;
      }

      owner = found.value;
    }

    return found;
  }

  /** Whether the file writes a value at `path`. */
  has(path: readonly PathSegment[]): boolean {
    return this.locate(path) !== undefined;
  }

  /** The source text of the value at `path`. */
  valueText(path: readonly PathSegment[]): string | undefined {
    const found = this.locate(path);

    return found === undefined
      ? undefined
      : this.#module.text.slice(found.value.start, found.value.end);
  }

  /**
   * Removes the entry at `path` with the comments in front of it and on its
   * line, then the declarations and imports the removal left unused.
   */
  remove(path: readonly PathSegment[]): EditResult {
    const found = this.locate(path);

    if (found === undefined) {
      return { status: "absent" };
    }

    const reason = this.#unsupported(found, path);

    if (reason !== undefined) {
      return this.#flag(reason);
    }

    const index = found.siblings.indexOf(found.entry);
    const bounds = this.#bounds(found.owner);
    const edited = new MagicString(this.#module.text);

    this.#removeSibling(edited, found.siblings, index, bounds);
    this.#apply(edited);
    this.removeUnused();

    return { status: "done" };
  }

  /**
   * Writes `valueText` at `path`: it replaces the value of an existing entry,
   * or adds a property to the object above `path` (which has to exist).
   */
  set(path: readonly PathSegment[], valueText: string): EditResult {
    const found = this.locate(path);

    if (found !== undefined) {
      const reason = this.#unsupported(found, path);

      if (reason !== undefined) {
        return this.#flag(reason);
      }

      const target =
        found.entry.type === "Property" ? found.entry.value : found.entry;

      const edited = new MagicString(this.#module.text);

      if (found.entry.type === "Property" && found.entry.shorthand) {
        edited.overwrite(
          found.entry.start,
          found.entry.end,
          `${String(path.at(-1))}: ${valueText}`,
        );
      } else {
        edited.overwrite(target.start, target.end, valueText);
      }

      this.#apply(edited);

      return { status: "done" };
    }

    const key = path.at(-1);

    const parent =
      path.length === 1 ? undefined : this.locate(path.slice(0, -1));

    const owner =
      path.length === 1
        ? this.configObject()
        : parent?.value.type === "ObjectExpression"
          ? parent.value
          : undefined;

    if (typeof key !== "string" || owner === undefined) {
      return this.#flag(
        `${this.#path}: cannot add ${path.join(".")}, because ${path
          .slice(0, -1)
          .join(".")} is not an object literal in this file; add it by hand.`,
      );
    }

    this.#addProperty(owner, key, valueText);

    return { status: "done" };
  }

  /**
   * The names of the entries of the object or list at `path` (an empty path is
   * the config), in source order. A spread contributes the names of the object
   * it spreads. Undefined when `path` is not an object or list literal here.
   */
  keys(path: readonly PathSegment[]): readonly string[] | undefined {
    const root =
      path.length === 0 ? this.configObject() : this.locate(path)?.value;

    if (root === undefined) {
      return undefined;
    }

    const names: string[] = [];
    const seen = new Set<Node>();

    const collect = (node: Node): boolean => {
      const resolved = this.#resolve(node);

      if (seen.has(resolved)) {
        return true;
      }

      seen.add(resolved);

      if (resolved.type === "ObjectExpression") {
        for (const property of resolved.properties) {
          if (property.type === "SpreadElement") {
            collect(property.argument);
          } else {
            const name = propertyName(property);

            if (name !== undefined && !names.includes(name)) {
              names.push(name);
            }
          }
        }

        return true;
      }

      if (resolved.type === "ArrayExpression") {
        for (const element of resolved.elements) {
          const label =
            element === null || element.type === "SpreadElement"
              ? undefined
              : this.#label(unwrap(element));

          if (label !== undefined && !names.includes(label)) {
            names.push(label);
          }
        }

        return true;
      }

      return false;
    };

    return collect(root) ? names : undefined;
  }

  /**
   * Writes `valueText` at `path` and creates the object literals above it that
   * the file lacks, so `ensure(["blocks", "drive", "columns", "nodes", "x"],
   * '"y"')` works in a block that has no `columns` yet. The deepest entry that
   * exists must be an object literal in this file; otherwise the result is a
   * review line and the text stays.
   */
  ensure(path: readonly PathSegment[], valueText: string): EditResult {
    let depth = path.length;

    while (depth > 0 && this.locate(path.slice(0, depth)) === undefined) {
      depth -= 1;
    }

    if (depth === path.length) {
      return this.set(path, valueText);
    }

    const owner =
      depth === 0 ? undefined : this.locate(path.slice(0, depth))?.value;

    const keys = path.slice(depth);

    if (
      keys.some((key) => typeof key !== "string") ||
      (depth > 0 && owner?.type !== "ObjectExpression")
    ) {
      return this.#flag(
        `${this.#path}: cannot add ${path.join(".")}, because ${path
          .slice(0, depth)
          .join(".")} is not an object literal in this file; add it by hand.`,
      );
    }

    const object =
      depth === 0
        ? this.configObject()
        : owner?.type === "ObjectExpression"
          ? owner
          : undefined;

    if (object === undefined) {
      return this.#flag(`${this.#path}: no config object found.`);
    }

    const { text } = this.#module;
    const style = this.style;
    const last = object.properties.at(-1);
    const closing = lineStartOf(text, object.end - 1);

    const base =
      last === undefined
        ? `${/^[\t ]*/.exec(text.slice(closing))?.[0] ?? ""}${style.indent}`
        : (/^[\t ]*/.exec(text.slice(lineStartOf(text, last.start)))?.[0] ??
          style.indent);

    const name = (key: PathSegment): string =>
      IDENTIFIER.test(String(key))
        ? String(key)
        : `${style.quote}${String(key)}${style.quote}`;

    const build = (at: number, pad: string): string =>
      at === keys.length - 1
        ? valueText
        : `{${style.eol}${pad}${style.indent}${name(keys[at + 1]!)}: ${build(at + 1, pad + style.indent)},${style.eol}${pad}}`;

    this.#addProperty(object, String(keys[0]), build(0, base));

    return { status: "done" };
  }

  /**
   * Adds `valueText` as the last element of the array at `path`, in the form
   * the array has (one line or one element per line).
   */
  append(path: readonly PathSegment[], valueText: string): EditResult {
    const found = this.locate(path);
    const list = found?.value;

    if (list?.type !== "ArrayExpression") {
      return this.#flag(
        `${this.#path}: cannot add to ${path.join(".")}, because it is not an array literal in this file; add it by hand.`,
      );
    }

    this.#addElement(list, valueText);

    return { status: "done" };
  }

  /**
   * Puts the keys of the object at `path` in ascending order. Each entry moves
   * with its comments; an object with a spread, a computed key or a method
   * stays as it is and gets a review line.
   */
  sortKeys(path: readonly PathSegment[], call?: number): EditResult {
    const root =
      call === undefined ? this.configObject() : this.defineConfigCalls()[call];

    const located = path.length === 0 ? undefined : this.#locateIn(root, path);

    const object =
      path.length === 0
        ? root
        : located?.value.type === "ObjectExpression"
          ? located.value
          : undefined;

    if (object === undefined) {
      return path.length > 0 && located === undefined
        ? { status: "absent" }
        : this.#flag(
            `${this.#path}: ${path.join(".")} is not an object literal; sort it by hand.`,
          );
    }

    const names = object.properties.map((each) =>
      each.type === "Property" ? propertyName(each) : undefined,
    );

    if (names.includes(undefined)) {
      return this.#flag(
        `${this.#path}: ${path.join(".") || "the config"} has a spread, a computed key or a method, so its keys stay in place.`,
      );
    }

    const { text } = this.#module;
    const bounds = this.#bounds(object);

    const cores = object.properties.map((each, at) => {
      const comma = this.#commaAfter(
        each.end,
        object.properties[at + 1]?.start ?? bounds.close,
      );

      const after = comma === -1 ? each.end : comma + 1;

      const note = this.#module.comments.find(
        (comment) =>
          comment.start >= after &&
          /^[\t ]*$/.test(text.slice(after, comment.start)),
      );

      return {
        from: this.#entryStart(object.properties, at, bounds),
        to: note?.end ?? after,
        body: text.slice(
          this.#entryStart(object.properties, at, bounds),
          each.end,
        ),
        comma: comma !== -1,
        note: note === undefined ? "" : ` ${text.slice(note.start, note.end)}`,
        name: names[at]!,
      };
    });

    const ordered = cores.toSorted((a, b) => a.name.localeCompare(b.name));
    const edited = new MagicString(text);

    // The line breaks between entries stay where they are.
    for (const [at, slot] of cores.entries()) {
      const source = ordered[at]!;

      if (source !== slot) {
        edited.overwrite(
          slot.from,
          slot.to,
          `${source.body}${slot.comma ? "," : ""}${source.note}`,
        );
      }
    }

    this.#apply(edited);

    return { status: "done" };
  }

  /**
   * Removes the imports and top-level constants an edit left unused. A name
   * that the file never used before the first edit stays.
   */
  removeUnused(): void {
    for (;;) {
      const used = referencedBindings(this.#module.program);
      const target = this.#unusedStatement(used);

      if (target === undefined) {
        return;
      }

      const edited = new MagicString(this.#module.text);

      if (target.kind === "specifier") {
        this.#removeSibling(
          edited,
          target.siblings,
          target.index,
          target.bounds,
        );
      } else {
        const from = lineStartOf(this.#module.text, target.node.start);
        const lead = this.#module.text.slice(from, target.node.start);
        const after = this.#lineEnd(target.node.end);

        edited.remove(
          /^\s*$/.test(lead) ? from : target.node.start,
          /^\s*$/.test(lead) ? after : target.node.end,
        );
      }

      this.#apply(edited);
    }
  }

  // --- lookup ---------------------------------------------------------------

  #defineConfigNames(program: Program): ReadonlySet<string> {
    const names = new Set<string>();

    for (const statement of program.body) {
      if (statement.type !== "ImportDeclaration") {
        continue;
      }

      for (const specifier of statement.specifiers) {
        if (
          specifier.type === "ImportSpecifier" &&
          specifier.imported.type === "Identifier" &&
          specifier.imported.name === DEFINE_CONFIG
        ) {
          names.add(specifier.local.name);
        }
      }
    }

    return names.size === 0 ? new Set([DEFINE_CONFIG]) : names;
  }

  #asConfig(
    node: Node,
    names: ReadonlySet<string>,
    seen: Set<Node>,
  ): ObjectExpression | undefined {
    const inner = unwrap(node);

    if (seen.has(inner)) {
      return undefined;
    }

    seen.add(inner);

    if (inner.type === "ObjectExpression") {
      return inner;
    }

    if (inner.type === "Identifier") {
      const declared = this.#declaration(inner.name);

      return declared === undefined
        ? undefined
        : this.#asConfig(declared, names, seen);
    }

    if (inner.type === "CallExpression") {
      const { callee } = inner;

      const named =
        (callee.type === "Identifier" && names.has(callee.name)) ||
        (callee.type === "MemberExpression" &&
          !callee.computed &&
          callee.property.type === "Identifier" &&
          callee.property.name === DEFINE_CONFIG);

      const [argument] = inner.arguments;

      return named &&
        argument !== undefined &&
        argument.type !== "SpreadElement"
        ? this.#asConfig(argument, names, seen)
        : undefined;
    }

    if (
      inner.type === "ArrowFunctionExpression" ||
      inner.type === "FunctionExpression"
    ) {
      return this.#returned(inner, names, seen);
    }

    return undefined;
  }

  #returned(
    fn: Node,
    names: ReadonlySet<string>,
    seen: Set<Node>,
  ): ObjectExpression | undefined {
    if (
      fn.type !== "ArrowFunctionExpression" &&
      fn.type !== "FunctionExpression"
    ) {
      return undefined;
    }

    const body = fn.body;

    if (body === null) {
      return undefined;
    }

    if (body.type !== "BlockStatement") {
      return this.#asConfig(body, names, seen);
    }

    for (const statement of body.body) {
      if (statement.type === "ReturnStatement" && statement.argument !== null) {
        return this.#asConfig(statement.argument, names, seen);
      }
    }

    return undefined;
  }

  /** The initializer of a top-level `const name = ...`. */
  #declaration(name: string): Expression | undefined {
    for (const statement of this.#module.program.body) {
      const declaration =
        statement.type === "ExportNamedDeclaration"
          ? statement.declaration
          : statement;

      if (declaration?.type !== "VariableDeclaration") {
        continue;
      }

      for (const each of declaration.declarations) {
        if (
          each.id.type === "Identifier" &&
          each.id.name === name &&
          each.init !== null
        ) {
          return each.init;
        }
      }
    }

    return undefined;
  }

  /** Resolves `node` to an object or array literal, following variables. */
  #resolve(node: Node, seen = new Set<Node>()): Node {
    const inner = unwrap(node);

    if (inner.type !== "Identifier" || seen.has(inner)) {
      return inner;
    }

    seen.add(inner);

    const declared = this.#declaration(inner.name);

    return declared === undefined ? inner : this.#resolve(declared, seen);
  }

  #step(
    container: Node,
    segment: PathSegment,
    seen = new Set<Node>(),
  ): Located | undefined {
    const resolved = this.#resolve(container);

    if (seen.has(resolved)) {
      return undefined;
    }

    seen.add(resolved);

    if (resolved.type === "ArrayExpression" && typeof segment === "number") {
      const element = resolved.elements[segment];

      return element === undefined || element === null
        ? undefined
        : {
            entry: element,
            value: this.#resolve(
              element.type === "SpreadElement" ? element.argument : element,
            ),
            owner: resolved,
            siblings: resolved.elements.filter((each) => each !== null),
          };
    }

    if (resolved.type === "ArrayExpression" && typeof segment === "string") {
      return this.#named(resolved, segment);
    }

    if (resolved.type !== "ObjectExpression" || typeof segment !== "string") {
      return undefined;
    }

    // Later entries win, as they do when the object is built.
    for (const property of resolved.properties.toReversed()) {
      if (property.type === "SpreadElement") {
        const inside = this.#step(property.argument, segment, seen);

        if (inside !== undefined) {
          return inside;
        }
      } else if (propertyName(property) === segment) {
        return {
          entry: property,
          value: this.#resolve(property.value),
          owner: resolved,
          siblings: resolved.properties,
        };
      }
    }

    return undefined;
  }

  /** The instance name a list element stands for: its text, `name` or `block`. */
  #label(inner: Node): string | undefined {
    const text = (node: Node | undefined): string | undefined =>
      node?.type === "Literal" && typeof node.value === "string"
        ? node.value
        : undefined;

    if (inner.type !== "ObjectExpression") {
      return text(inner);
    }

    const read = (key: string): string | undefined => {
      const property = inner.properties.find(
        (each) => each.type === "Property" && propertyName(each) === key,
      );

      return property?.type === "Property" ? text(property.value) : undefined;
    };

    return read("name") ?? read("block");
  }

  /**
   * The element of a list that an instance name picks: a string with that text,
   * or an object whose `name` (else `block`) is that text. This is how
   * `blocks.<name>` reads in the `blocks` list.
   */
  #named(list: ArrayExpression, name: string): Located | undefined {
    for (const element of list.elements) {
      if (element === null || element.type === "SpreadElement") {
        continue;
      }

      const inner = unwrap(element);

      if (this.#label(inner) === name) {
        return {
          entry: element,
          value: inner,
          owner: list,
          siblings: list.elements.filter((each) => each !== null),
        };
      }
    }

    return undefined;
  }

  /** The `[start, end)` of the value at `path` in the text. */
  valueRange(
    path: readonly PathSegment[],
  ): { readonly start: number; readonly end: number } | undefined {
    const found = this.locate(path);

    return found === undefined
      ? undefined
      : { start: found.value.start, end: found.value.end };
  }

  /**
   * Edits the text through `callback`, which gets the tree and a `MagicString`
   * to splice. The result is parsed again, so a callback that writes a syntax
   * error throws before the document changes.
   */
  rewrite(
    callback: (context: {
      readonly program: Program;
      readonly text: string;
      readonly edit: MagicString;
    }) => void,
  ): void {
    const edit = new MagicString(this.#module.text);

    callback({ program: this.#module.program, text: this.#module.text, edit });

    if (edit.hasChanged()) {
      this.#apply(edit);
    }
  }

  /**
   * Why the document cannot edit `found` in place: it sits in an object the
   * file builds elsewhere, or it is a method or computed entry.
   */
  #unsupported(
    found: Located,
    path: readonly PathSegment[],
  ): string | undefined {
    const config = this.configObject();
    const where = path.join(".");

    if (found.entry.type === "SpreadElement") {
      return `${this.#path}: ${where} is a spread; edit it by hand.`;
    }

    if (
      found.entry.type === "Property" &&
      (found.entry.method || found.entry.kind !== "init")
    ) {
      return `${this.#path}: ${where} is a method or accessor; edit it by hand.`;
    }

    if (config === undefined) {
      return `${this.#path}: no config object found.`;
    }

    // An owner in another top-level declaration is still in this file; only an
    // entry the lookup could not reach is unsupported, so there is nothing more
    // to check here.
    return undefined;
  }

  // --- text edits -----------------------------------------------------------

  #flag(review: string): EditResult {
    this.#review.push(review);

    return { status: "review", review };
  }

  #apply(edited: MagicString): void {
    const text = edited.toString();

    this.#module = parseModule(text, this.#path);
  }

  /** The offset of the comma between `from` and `to`, or -1. */
  #commaAfter(from: number, to: number): number {
    const { text } = this.#module;
    let at = from;

    while (at < to) {
      const here = at;

      const comment = this.#module.comments.find(
        (each) =>
          each.start === here ||
          (each.start >= here && /^\s*$/.test(text.slice(here, each.start))),
      );

      if (comment !== undefined && comment.start < to) {
        at = comment.end;
      } else if (/\s/.test(text[at]!)) {
        at += 1;
      } else {
        return text[at] === "," ? at : -1;
      }
    }

    return -1;
  }

  /** The end of the comment that follows `at` on the same line, else `at`. */
  #noteEnd(at: number): number {
    const { text } = this.#module;

    const note = this.#module.comments.find(
      (comment) =>
        comment.start >= at && /^[\t ]*$/.test(text.slice(at, comment.start)),
    );

    return note === undefined ? at : note.end;
  }

  /** Where the `{` and `}` or `[` and `]` of `owner` sit. */
  #bounds(owner: Node): { open: number; close: number } {
    return { open: owner.start, close: owner.end - 1 };
  }

  #lineEnd(at: number): number {
    const { text } = this.#module;
    const rest = text.slice(at);
    const match = /^[\t ]*(?:\r?\n|$)/.exec(rest);

    return match === null ? at : at + match[0].length;
  }

  /** The start of entry `at`, with the comments in front of it. */
  #entryStart(
    siblings: readonly Node[],
    at: number,
    bounds: { open: number; close: number },
  ): number {
    const { text } = this.#module;
    const node = siblings[at]!;

    const floor =
      at === 0
        ? bounds.open + 1
        : this.#commaAfter(siblings[at - 1]!.end, node.start) + 1;

    let start = node.start;

    // A comment on the line after the previous comma belongs to the entry in
    // front of it; one on its own line belongs to this entry.
    const owned = this.#module.comments
      .filter((each) => each.start >= floor && each.end <= node.start)
      .filter(
        (each) => at === 0 || text.slice(floor, each.start).includes("\n"),
      );

    if (owned.length > 0) {
      start = owned[0]!.start;
    }

    const from = lineStartOf(text, start);

    return /^[\t ]*$/.test(text.slice(from, start)) ? from : start;
  }

  #removeSibling(
    edited: MagicString,
    siblings: readonly Node[],
    index: number,
    bounds: { open: number; close: number },
  ): void {
    const { text } = this.#module;
    const node = siblings[index]!;
    const next = siblings[index + 1];
    const previous = siblings[index - 1];
    const start = this.#entryStart(siblings, index, bounds);

    const wholeLines =
      (start < node.start &&
        /^[\t ]*$/.test(
          text.slice(lineStartOf(text, node.start), node.start),
        )) ||
      (start === lineStartOf(text, start) && start !== node.start);

    const comma = this.#commaAfter(node.end, next?.start ?? bounds.close);
    let end = comma === -1 ? node.end : comma + 1;

    // A comment after the comma on the same line goes with the entry.
    for (const comment of this.#module.comments) {
      if (
        comment.start >= end &&
        /^[\t ]*$/.test(text.slice(end, comment.start))
      ) {
        end = comment.end;
      }
    }

    if (previous === undefined && next === undefined) {
      const inner = text.slice(bounds.open + 1, bounds.close);

      const kept =
        inner.slice(0, start - bounds.open - 1) +
        inner.slice(end - bounds.open - 1);

      if (/^\s*$/.test(kept)) {
        edited.remove(bounds.open + 1, bounds.close);

        return;
      }
    }

    const onOwnLines =
      /^[\t ]*$/.test(text.slice(lineStartOf(text, start), start)) &&
      /^[\t ]*(?:\r?\n|$)/.test(text.slice(end));

    if (onOwnLines) {
      edited.remove(lineStartOf(text, start), this.#lineEnd(end));
    } else if (comma === -1 && previous !== undefined) {
      // The last entry of a one-line object: take the comma in front with it.
      const before = this.#commaAfter(previous.end, node.start);

      edited.remove(before === -1 ? node.start : before, end);

      return;
    } else {
      let after = end;

      while (text[after] === " ") {
        after += 1;
      }

      edited.remove(wholeLines ? start : node.start, after);
    }

    if (comma === -1 && previous !== undefined) {
      const before = this.#commaAfter(previous.end, node.start);

      // The entry before it was the last one: drop its comma unless the file
      // ends entries with commas.
      if (before !== -1 && !this.style.trailingComma) {
        edited.remove(before, before + 1);
      }
    }
  }

  #addProperty(owner: ObjectExpression, key: string, valueText: string): void {
    const { text } = this.#module;
    const style = this.style;

    const name = IDENTIFIER.test(key)
      ? key
      : `${style.quote}${key}${style.quote}`;

    const entry = `${name}: ${valueText}`;
    const edited = new MagicString(text);
    const last = owner.properties.at(-1);
    const multiline = text.slice(owner.start, owner.end).includes("\n");

    if (last === undefined) {
      const closing = lineStartOf(text, owner.end - 1);
      const outer = /^[\t ]*/.exec(text.slice(closing))?.[0] ?? "";

      edited.overwrite(
        owner.start,
        owner.end,
        multiline || valueText.includes("\n")
          ? `{${style.eol}${outer}${style.indent}${entry},${style.eol}${outer}}`
          : `{ ${entry} }`,
      );
    } else if (multiline) {
      const lead =
        /^[\t ]*/.exec(text.slice(lineStartOf(text, last.start)))?.[0] ??
        style.indent;

      const comma = this.#commaAfter(last.end, owner.end - 1);

      if (comma === -1) {
        edited.appendLeft(last.end, ",");
        edited.appendLeft(
          this.#noteEnd(last.end),
          `${style.eol}${lead}${entry}`,
        );
      } else {
        edited.appendLeft(
          this.#noteEnd(comma + 1),
          `${style.eol}${lead}${entry},`,
        );
      }
    } else {
      edited.appendLeft(last.end, `, ${entry}`);
    }

    this.#apply(edited);
  }

  #addElement(owner: ArrayExpression, valueText: string): void {
    const { text } = this.#module;
    const style = this.style;
    const edited = new MagicString(text);
    const last = owner.elements.findLast((each) => each !== null);
    const multiline = text.slice(owner.start, owner.end).includes("\n");

    if (last === undefined) {
      const closing = lineStartOf(text, owner.end - 1);
      const outer = /^[\t ]*/.exec(text.slice(closing))?.[0] ?? "";

      edited.overwrite(
        owner.start,
        owner.end,
        multiline || valueText.includes("\n")
          ? `[${style.eol}${outer}${style.indent}${valueText},${style.eol}${outer}]`
          : `[${valueText}]`,
      );
    } else if (multiline) {
      const lead =
        /^[\t ]*/.exec(text.slice(lineStartOf(text, last.start)))?.[0] ??
        style.indent;

      const comma = this.#commaAfter(last.end, owner.end - 1);

      if (comma === -1) {
        edited.appendLeft(last.end, ",");
        edited.appendLeft(
          this.#noteEnd(last.end),
          `${style.eol}${lead}${valueText}`,
        );
      } else {
        edited.appendLeft(
          this.#noteEnd(comma + 1),
          `${style.eol}${lead}${valueText},`,
        );
      }
    } else {
      edited.appendLeft(last.end, `, ${valueText}`);
    }

    this.#apply(edited);
  }

  #unusedStatement(
    used: ReadonlySet<string>,
  ):
    | {
        kind: "specifier";
        siblings: readonly Node[];
        index: number;
        bounds: { open: number; close: number };
      }
    | { kind: "statement"; node: Statement }
    | undefined {
    for (const statement of this.#module.program.body) {
      if (statement.type === "ImportDeclaration") {
        const dead = statement.specifiers.filter(
          (each) =>
            this.#before.has(each.local.name) && !used.has(each.local.name),
        );

        if (dead.length === 0) {
          continue;
        }

        if (dead.length === statement.specifiers.length) {
          return { kind: "statement", node: statement };
        }

        return this.#deadSpecifier(statement, dead[0]!);
      }

      if (
        statement.type === "VariableDeclaration" &&
        statement.declarations.length === 1
      ) {
        const [only] = statement.declarations;

        if (
          only!.id.type === "Identifier" &&
          this.#before.has(only!.id.name) &&
          !used.has(only!.id.name)
        ) {
          return { kind: "statement", node: statement };
        }
      }
    }

    return undefined;
  }

  #deadSpecifier(
    statement: ImportDeclaration,
    dead: Node,
  ):
    | {
        kind: "specifier";
        siblings: readonly Node[];
        index: number;
        bounds: { open: number; close: number };
      }
    | undefined {
    const named = statement.specifiers.filter(
      (each) => each.type === "ImportSpecifier",
    );

    // SAFETY: `dead` came from this statement's own specifiers, so it is one of `named` when it is an ImportSpecifier.
    const index = named.indexOf(dead as (typeof named)[number]);

    if (index === -1) {
      return undefined;
    }

    const open = this.#module.text.indexOf("{", statement.start);
    const close = this.#module.text.indexOf("}", open);

    return {
      kind: "specifier",
      siblings: named,
      index,
      bounds: { open, close },
    };
  }
}
