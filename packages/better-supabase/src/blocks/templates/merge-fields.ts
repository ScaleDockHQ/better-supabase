import type { ComposedEmail } from "../notifications/email.ts";

/** How a rendered value is escaped: for HTML markup, or left as it is. */
export type MergeEscape = "html" | "text";

/** One merge field a record type offers, as an editor lists it. */
export interface MergeFieldSpec {
  readonly label?: string;
  readonly description?: string;
  /** A value for previews and for the editor's sample render. */
  readonly example?: string;
}

/**
 * Values for `renderMergeFields`, by field name. A dotted name such as
 * `customer.name` reads that key first, then the nested path.
 */
export type MergeValues<K extends string = string> = {
  readonly [P in K]?: unknown;
} & Readonly<Record<string, unknown>>;

export interface RenderMergeFieldsOptions {
  /** Default `text`. `{{{ name }}}` is never escaped. */
  readonly escape?: MergeEscape;
  /** What a field without a value renders as: `empty` (default) or the `{{ name }}` it was. */
  readonly missing?: "empty" | "keep";
  /**
   * Turns a value into text. The default prints strings, numbers and
   * booleans as they are, Temporal values and other objects with their own
   * `toString`, a `Date` as ISO 8601, arrays joined by `, `, and plain
   * objects as JSON.
   */
  readonly format?: (value: unknown, name: string) => string;
}

/** A typed list of the merge fields one record type offers. */
export interface MergeFieldCatalog<K extends string = string> {
  readonly subjectType: string;
  readonly fields: Readonly<Record<K, MergeFieldSpec>>;
  readonly names: readonly K[];
  /** The fields `text` uses that the catalog doesn't define, in order of first use. */
  unknown(text: string): readonly string[];
  /** `renderMergeFields` with values typed by the catalog. */
  render(
    text: string,
    values: MergeValues<K>,
    options?: RenderMergeFieldsOptions,
  ): string;
  /** Each field's `example`, for a preview. */
  examples(): Readonly<Record<string, string>>;
}

const FIELD =
  /\{\{\{\s*([A-Za-z_][\w.-]*)\s*\}\}\}|\{\{\s*([A-Za-z_][\w.-]*)\s*\}\}/g;

const FIELD_NAME = /^[A-Za-z_][\w.-]*$/;

const HTML_ESCAPES: Readonly<Record<string, string>> = {
  "&": "&amp;",
  "<": "&lt;",
  ">": "&gt;",
  '"': "&quot;",
  "'": "&#39;",
};

function escapeHtml(value: string): string {
  return value.replaceAll(/[&<>"']/g, (char) => HTML_ESCAPES[char] ?? char);
}

function isPlainObject(value: object): boolean {
  const proto: unknown = Object.getPrototypeOf(value);

  return proto === null || proto === Object.prototype;
}

function defaultFormat(value: unknown): string {
  const kind = typeof value;

  switch (kind) {
    case "string":
    case "number":
    case "bigint":
    case "boolean": {
      return String(value);
    }

    case "object": {
      if (typeof value !== "object" || value === null) {
        return "";
      }

      if (value instanceof Date) {
        return value.toISOString();
      }

      if (Array.isArray(value)) {
        return value.map((item: unknown) => defaultFormat(item)).join(", ");
      }

      return isPlainObject(value) ? JSON.stringify(value) : String(value);
    }

    case "undefined":
    case "symbol":
    case "function": {
      return "";
    }

    default: {
      const unreachable: never = kind;

      return String(unreachable);
    }
  }
}

function isKeyed(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null;
}

function lookup(
  values: Readonly<Record<string, unknown>>,
  name: string,
): unknown {
  if (Object.hasOwn(values, name)) {
    return values[name];
  }

  let current: unknown = values;

  for (const part of name.split(".")) {
    if (!isKeyed(current) || !Object.hasOwn(current, part)) {
      return undefined;
    }

    current = current[part];
  }

  return current;
}

/** The merge field names `text` uses, in order of first use. */
export function mergeFieldsIn(text: string): readonly string[] {
  const names = new Set<string>();

  for (const match of text.matchAll(FIELD)) {
    names.add(match[1] ?? match[2] ?? "");
  }

  return [...names];
}

/**
 * Replaces each `{{ name }}` in `text` with its value, escaped for HTML with
 * `escape: "html"`, and each `{{{ name }}}` with its value unescaped. It
 * has no dependencies and runs on every WinterTC runtime.
 */
export function renderMergeFields(
  text: string,
  values: Readonly<Record<string, unknown>>,
  options: RenderMergeFieldsOptions = {},
): string {
  const html = options.escape === "html";
  const format = options.format ?? defaultFormat;

  return text.replaceAll(
    FIELD,
    (whole, raw: string | undefined, escaped: string | undefined) => {
      const name = raw ?? escaped ?? "";
      const value = lookup(values, name);

      if (value === undefined || value === null) {
        return options.missing === "keep" ? whole : "";
      }

      const rendered = format(value, name);

      return html && raw === undefined ? escapeHtml(rendered) : rendered;
    },
  );
}

/**
 * The merge fields a record type offers, such as an invoice's
 * `customer.name` and `total`. The catalog types `render` and lists the
 * fields a template uses that it doesn't define.
 */
export function defineMergeFields<const K extends string>(
  subjectType: string,
  fields: Readonly<Record<K, MergeFieldSpec>>,
): MergeFieldCatalog<K> {
  // SAFETY: Object.keys returns the keys of `fields`, which are typed as K.
  const names = Object.keys(fields) as K[];
  const bad = names.find((name) => !FIELD_NAME.test(name));

  if (bad !== undefined) {
    throw new TypeError(
      `"${bad}" is not a merge field name: use letters, digits, ".", "-" and "_"`,
    );
  }

  const known = new Set<string>(names);

  return {
    subjectType,
    fields,
    names,
    unknown: (text) => mergeFieldsIn(text).filter((name) => !known.has(name)),
    render: (text, values, options) => renderMergeFields(text, values, options),
    examples: () => {
      const examples: Record<string, string> = {};

      for (const name of names) {
        const example = fields[name].example;

        if (example !== undefined) {
          examples[name] = example;
        }
      }

      return examples;
    },
  };
}

/** An email body with merge fields, as an email template stores it. */
export interface EmailTemplateBody {
  readonly subject: string;
  readonly text?: string;
  readonly html?: string;
}

export interface TemplateEmailOptions
  extends
    Pick<RenderMergeFieldsOptions, "missing" | "format">,
    Pick<ComposedEmail, "replyTo" | "category"> {
  /** Stored on the delivery, e.g. `invoice-sent-v3`. */
  readonly templateKey?: string;
}

/**
 * Renders an email template for the notifications email channel's
 * `compose`: the subject and text as text, the HTML escaped for HTML.
 */
export function composeTemplateEmail(
  body: EmailTemplateBody,
  values: Readonly<Record<string, unknown>>,
  options: TemplateEmailOptions = {},
): ComposedEmail {
  const shared = {
    ...(options.missing === undefined ? {} : { missing: options.missing }),
    ...(options.format === undefined ? {} : { format: options.format }),
  };

  return {
    subject: renderMergeFields(body.subject, values, shared),
    ...(body.text === undefined
      ? {}
      : { text: renderMergeFields(body.text, values, shared) }),
    ...(body.html === undefined
      ? {}
      : {
          html: renderMergeFields(body.html, values, {
            ...shared,
            escape: "html",
          }),
        }),
    ...(options.replyTo === undefined ? {} : { replyTo: options.replyTo }),
    ...(options.category === undefined ? {} : { category: options.category }),
    ...(options.templateKey === undefined
      ? {}
      : { templateKey: options.templateKey }),
  };
}
