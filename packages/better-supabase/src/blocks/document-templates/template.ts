import type { Result } from "../../core/result.ts";
import type {
  DocumentFilter,
  DocumentTemplateIssueCode,
  DocumentType,
  DocumentVariableType,
} from "../../sql/modules/document-templates-values.ts";
import type { DocumentVariables } from "./variables.ts";

import { dbError } from "../../core/errors.ts";
import { err, ok } from "../../core/result.ts";
import {
  DOCUMENT_FILTERS,
  DOCUMENT_TYPES,
  DOCUMENT_VARIABLES,
} from "../../sql/modules/document-templates-values.ts";

/**
 * One problem of a template, in the order the template reads. `code` is the
 * hint code `save_document_template` raises with for the first one.
 */
export interface DocumentTemplateIssue {
  readonly code: DocumentTemplateIssueCode;
  readonly message: string;
  /** The text between the braces, trimmed. */
  readonly tag: string;
}

type Node =
  | { readonly kind: "text"; readonly text: string }
  | {
      readonly kind: "value";
      readonly path: string;
      readonly filter: DocumentFilter | undefined;
    }
  | {
      readonly kind: "each";
      readonly list: string;
      readonly alias: string;
      readonly children: readonly Node[];
    }
  | {
      readonly kind: "if";
      readonly path: string;
      readonly whenSet: readonly Node[];
      readonly otherwise: readonly Node[];
    };

const TAG = /\{\{([\s\S]*?)\}\}/g;
const PATH = "[A-Za-z_][A-Za-z0-9_]*(?:\\.[A-Za-z_][A-Za-z0-9_]*)*";
const EACH = new RegExp(`^#each\\s+(${PATH})\\s+as\\s+([a-z][A-Za-z0-9_]*)$`);
const IF = new RegExp(`^#if\\s+(${PATH})$`);
const VALUE = new RegExp(`^(${PATH})(?:\\s*\\|\\s*([A-Za-z_]+))?$`);
const TEXT_KEY = /^texts\.[a-z][a-z0-9_]{0,63}$/;
const FILTERS: ReadonlySet<string> = new Set(DOCUMENT_FILTERS);

interface Parsed {
  readonly nodes: readonly Node[];
  readonly issues: readonly DocumentTemplateIssue[];
}

interface Frame {
  readonly node:
    | { readonly kind: "root" }
    | { readonly kind: "each"; readonly list: string; readonly alias: string }
    | { readonly kind: "if"; readonly path: string };
  nodes: Node[];
  whenSet?: Node[];
}

function parse(body: string): Parsed {
  const issues: DocumentTemplateIssue[] = [];
  const root: Frame = { node: { kind: "root" }, nodes: [] };
  const stack: Frame[] = [root];

  const top = (): Frame => stack.at(-1) ?? root;

  const syntax = (tag: string, message: string): void => {
    issues.push({ code: "DOCUMENT_TEMPLATE_SYNTAX", message, tag });
  };

  const text = (value: string): void => {
    if (/\{\{|\}\}/.test(value)) {
      syntax(value.trim(), "a brace pair is not closed or not opened");
    }

    if (value !== "") {
      top().nodes.push({ kind: "text", text: value });
    }
  };

  let last = 0;

  for (const match of body.matchAll(TAG)) {
    text(body.slice(last, match.index));
    last = match.index + match[0].length;

    const tag = (match[1] ?? "").trim();
    const frame = top();

    if (tag === "/each" || tag === "/if") {
      const want = tag === "/each" ? "each" : "if";

      if (frame.node.kind !== want) {
        syntax(tag, `${tag} closes nothing`);
        continue;
      }

      stack.pop();

      const parent = top();

      if (frame.node.kind === "each") {
        parent.nodes.push({
          kind: "each",
          list: frame.node.list,
          alias: frame.node.alias,
          children: frame.nodes,
        });
      } else {
        parent.nodes.push({
          kind: "if",
          path: frame.node.path,
          whenSet: frame.whenSet ?? frame.nodes,
          otherwise: frame.whenSet === undefined ? [] : frame.nodes,
        });
      }

      continue;
    }

    if (tag === "else") {
      if (frame.node.kind !== "if" || frame.whenSet !== undefined) {
        syntax(tag, "else belongs inside one #if");
        continue;
      }

      frame.whenSet = frame.nodes;
      frame.nodes = [];
      continue;
    }

    const each = EACH.exec(tag);

    if (each !== null) {
      stack.push({
        node: { kind: "each", list: each[1] ?? "", alias: each[2] ?? "" },
        nodes: [],
      });
      continue;
    }

    const cond = IF.exec(tag);

    if (cond !== null) {
      stack.push({ node: { kind: "if", path: cond[1] ?? "" }, nodes: [] });
      continue;
    }

    if (tag.startsWith("#") || tag.startsWith("/")) {
      syntax(tag, "unknown block tag");
      continue;
    }

    const value = VALUE.exec(tag);

    if (value === null) {
      syntax(tag, "a placeholder is a path with an optional filter");
      continue;
    }

    const filter = value[2];

    if (filter !== undefined && !FILTERS.has(filter)) {
      issues.push({
        code: "DOCUMENT_TEMPLATE_UNKNOWN_FILTER",
        message: `unknown filter ${filter}; use ${DOCUMENT_FILTERS.join(" or ")}`,
        tag,
      });
      continue;
    }

    top().nodes.push({
      kind: "value",
      path: value[1] ?? "",
      // SAFETY: checked against the filter names above.
      filter: filter as DocumentFilter | undefined,
    });
  }

  text(body.slice(last));

  for (const frame of stack.slice(1)) {
    syntax(
      frame.node.kind === "each" ? "#each" : "#if",
      `${frame.node.kind === "each" ? "#each" : "#if"} is not closed`,
    );
  }

  return { nodes: root.nodes, issues };
}

type Scope = ReadonlyMap<string, string>;

function typesOf(
  types: readonly DocumentType[],
): ReadonlyMap<string, DocumentVariableType> {
  const found = new Map<string, DocumentVariableType>();

  for (const type of types) {
    for (const variable of DOCUMENT_VARIABLES[type]) {
      found.set(variable.path, variable.type);
    }
  }

  return found;
}

function kindOf(
  path: string,
  scope: Scope,
  known: ReadonlyMap<string, DocumentVariableType>,
  texts: boolean,
): DocumentVariableType | undefined {
  const [head, ...rest] = path.split(".");
  const list = scope.get(head ?? "");

  if (list !== undefined) {
    return rest.length === 0
      ? undefined
      : known.get(`${list}[].${rest.join(".")}`);
  }

  if (TEXT_KEY.test(path)) {
    return texts ? "string" : undefined;
  }

  return known.get(path);
}

function check(
  nodes: readonly Node[],
  scope: Scope,
  known: ReadonlyMap<string, DocumentVariableType>,
  texts: boolean,
  issues: DocumentTemplateIssue[],
): void {
  const unknown = (path: string, why: string): void => {
    issues.push({
      code: "DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE",
      message: `${path} ${why}`,
      tag: path,
    });
  };

  for (const node of nodes) {
    switch (node.kind) {
      case "text": {
        break;
      }

      case "value": {
        const kind = kindOf(node.path, scope, known, texts);

        if (kind === undefined) {
          unknown(node.path, "is not a variable of this document");
        } else if (kind === "object" || kind === "list") {
          unknown(node.path, "is not a single value");
        }

        break;
      }

      case "if": {
        if (kindOf(node.path, scope, known, texts) === undefined) {
          unknown(node.path, "is not a variable of this document");
        }

        check(node.whenSet, scope, known, texts, issues);
        check(node.otherwise, scope, known, texts, issues);
        break;
      }

      case "each": {
        if (known.get(node.list) !== "list" || scope.has(node.list)) {
          unknown(node.list, "is not a list of this document");
        }

        if (known.has(node.alias) || scope.has(node.alias)) {
          issues.push({
            code: "DOCUMENT_TEMPLATE_SYNTAX",
            message: `${node.alias} is already a variable`,
            tag: node.alias,
          });
        }

        check(
          node.children,
          new Map([...scope, [node.alias, node.list]]),
          known,
          texts,
          issues,
        );
        break;
      }

      default: {
        const never: never = node;

        throw new TypeError(`unhandled node ${JSON.stringify(never)}`);
      }
    }
  }
}

/**
 * The problems of `body` as a template of `type`, empty when it is valid. An
 * unknown variable, a block that is not closed and an unknown filter each name
 * their hint code. The SQL function `validate_document_template` finds the same
 * problems.
 */
export function validateDocumentTemplate(
  type: DocumentType,
  body: string,
): readonly DocumentTemplateIssue[] {
  const parsed = parse(body);
  const issues = [...parsed.issues];

  check(parsed.nodes, new Map(), typesOf([type]), true, issues);

  return issues;
}

/**
 * The problems of `body` as a text block. A block is shared by every document
 * type, so it may read a variable of any type, reads nothing from `texts`, and
 * renders an empty string for a variable its document lacks.
 */
export function validateDocumentTextBlock(
  body: string,
): readonly DocumentTemplateIssue[] {
  const parsed = parse(body);
  const issues = [...parsed.issues];

  check(parsed.nodes, new Map(), typesOf(DOCUMENT_TYPES), false, issues);

  return issues;
}

const AMPERSAND = /&/g;
const LESS = /</g;
const GREATER = />/g;
const QUOTE = /"/g;
const APOSTROPHE = /'/g;

/** Escapes text for an HTML body or a quoted attribute. */
export function escapeHtml(value: string): string {
  return value
    .replaceAll(AMPERSAND, "&amp;")
    .replaceAll(LESS, "&lt;")
    .replaceAll(GREATER, "&gt;")
    .replaceAll(QUOTE, "&quot;")
    .replaceAll(APOSTROPHE, "&#39;");
}

function digitsOf(currency: string | undefined): number {
  if (currency === undefined) {
    return 2;
  }

  try {
    return (
      new Intl.NumberFormat("en", {
        style: "currency",
        currency,
      }).resolvedOptions().maximumFractionDigits ?? 2
    );
  } catch {
    return 2;
  }
}

/**
 * Formats an amount in minor units (a bigint as text) for a locale and a
 * currency, counting in digits so no amount passes through a float.
 */
export function formatDocumentMoney(
  minor: string,
  currency: string | undefined,
  locale: string,
): string {
  if (!/^-?\d+$/.test(minor)) {
    return minor;
  }

  const digits = digitsOf(currency);
  const negative = minor.startsWith("-");
  const padded = (negative ? minor.slice(1) : minor).padStart(digits + 1, "0");
  const whole = padded.slice(0, padded.length - digits);
  const fraction = padded.slice(padded.length - digits);
  const sign = negative ? "-" : "";
  const decimal = digits === 0 ? whole : `${whole}.${fraction}`;

  // SAFETY: a signed decimal built from digits, the string form Intl accepts.
  const exact = `${sign}${decimal}` as `${number}`;

  try {
    return new Intl.NumberFormat(
      locale,
      currency === undefined
        ? { minimumFractionDigits: digits, maximumFractionDigits: digits }
        : { style: "currency", currency },
    ).format(exact);
  } catch {
    return `${sign}${decimal}`;
  }
}

/** Formats an ISO date (`2026-10-31`) for a locale, in UTC so no zone shifts it. */
export function formatDocumentDate(iso: string, locale: string): string {
  const day = /^\d{4}-\d{2}-\d{2}/.exec(iso);

  if (day === null) {
    return iso;
  }

  try {
    return new Intl.DateTimeFormat(locale, {
      dateStyle: "medium",
      timeZone: "UTC",
    }).format(new Date(`${day[0]}T00:00:00Z`));
  } catch {
    return day[0];
  }
}

function lookup(
  path: string,
  scope: ReadonlyMap<string, unknown>,
  variables: unknown,
): unknown {
  const [head, ...rest] = path.split(".");

  let current: unknown = scope.has(head ?? "")
    ? scope.get(head ?? "")
    : lookupKey(variables, head ?? "");

  for (const key of rest) {
    current = lookupKey(current, key);
  }

  return current;
}

function lookupKey(value: unknown, key: string): unknown {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? Object.getOwnPropertyDescriptor(value, key)?.value
    : undefined;
}

interface RenderState {
  readonly variables: unknown;
  readonly blocks: Readonly<Record<string, string>>;
  readonly known: ReadonlyMap<string, DocumentVariableType>;
  readonly locale: string;
  readonly currency: string | undefined;
  readonly depth: number;
}

function truthy(
  value: unknown,
  kind: DocumentVariableType | undefined,
): boolean {
  if (kind === "money") {
    return typeof value === "string" && !/^-?0+$/.test(value) && value !== "";
  }

  if (Array.isArray(value)) {
    return value.length > 0;
  }

  return (
    value !== null &&
    value !== undefined &&
    value !== false &&
    value !== "" &&
    value !== 0
  );
}

function show(
  value: unknown,
  filter: DocumentFilter | undefined,
  state: RenderState,
): string {
  if (value === null || value === undefined) {
    return "";
  }

  const raw =
    typeof value === "string" ||
    typeof value === "number" ||
    typeof value === "boolean"
      ? String(value)
      : "";

  switch (filter) {
    case "money": {
      return escapeHtml(formatDocumentMoney(raw, state.currency, state.locale));
    }

    case "date": {
      return escapeHtml(formatDocumentDate(raw, state.locale));
    }

    case undefined: {
      return escapeHtml(raw);
    }

    default: {
      const never: never = filter;

      throw new TypeError(`unhandled filter ${String(never)}`);
    }
  }
}

function emit(
  nodes: readonly Node[],
  scope: ReadonlyMap<string, unknown>,
  aliases: Scope,
  state: RenderState,
): string {
  let out = "";

  for (const node of nodes) {
    switch (node.kind) {
      case "text": {
        out += node.text;
        break;
      }

      case "value": {
        if (TEXT_KEY.test(node.path) && !aliases.has("texts")) {
          out += block(node.path.slice("texts.".length), state);
          break;
        }

        out += show(
          lookup(node.path, scope, state.variables),
          node.filter,
          state,
        );
        break;
      }

      case "if": {
        const kind = kindOf(node.path, aliases, state.known, true);

        const holds = TEXT_KEY.test(node.path)
          ? state.blocks[node.path.slice("texts.".length)] !== undefined
          : truthy(lookup(node.path, scope, state.variables), kind);

        out += emit(
          holds ? node.whenSet : node.otherwise,
          scope,
          aliases,
          state,
        );
        break;
      }

      case "each": {
        const items = lookup(node.list, scope, state.variables);

        if (!Array.isArray(items)) {
          break;
        }

        const inner = new Map([...aliases, [node.alias, node.list]]);

        for (const item of items) {
          out += emit(
            node.children,
            new Map([...scope, [node.alias, item]]),
            inner,
            state,
          );
        }

        break;
      }

      default: {
        const never: never = node;

        throw new TypeError(`unhandled node ${JSON.stringify(never)}`);
      }
    }
  }

  return out;
}

function block(key: string, state: RenderState): string {
  const body = state.blocks[key];

  if (body === undefined || state.depth > 0) {
    return "";
  }

  const parsed = parse(body);

  return parsed.issues.length > 0
    ? ""
    : emit(parsed.nodes, new Map(), new Map(), { ...state, depth: 1 });
}

/** What {@link renderDocumentHtml} takes. */
export interface RenderDocumentInput {
  readonly documentType: DocumentType;
  /** The template body, HTML you wrote with placeholders. */
  readonly template: string;
  /** The `variables` of `render_document`. */
  readonly variables: DocumentVariables;
  /** The `blocks` of `render_document`: text block key to body. */
  readonly blocks?: Readonly<Record<string, string>>;
  /**
   * The locale for amounts and dates. Default the document's language, then
   * `en`.
   */
  readonly locale?: string;
}

/**
 * Renders a template to HTML. Every value is escaped, so a buyer called
 * `<script>` prints as text; only the template's own markup is HTML. An unknown
 * variable, filter or an unclosed block returns an error before anything
 * renders, so a template the database accepted always renders.
 */
export function renderDocumentHtml(input: RenderDocumentInput): Result<string> {
  const invalid = validateDocumentTemplate(input.documentType, input.template);
  const first = invalid[0];

  if (first !== undefined) {
    return err(dbError("invalid_request", first.message, { hint: first.code }));
  }

  const known = typesOf([input.documentType]);
  const document = lookupKey(input.variables, "document");
  const language = lookupKey(document, "language");
  const currency = lookupKey(document, "currency");

  return ok(
    emit(parse(input.template).nodes, new Map(), new Map(), {
      variables: input.variables,
      blocks: input.blocks ?? {},
      known,
      locale: input.locale ?? (typeof language === "string" ? language : "en"),
      currency: typeof currency === "string" ? currency : undefined,
      depth: 0,
    }),
  );
}
