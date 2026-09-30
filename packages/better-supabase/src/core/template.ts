import { DbException, dbError } from "./errors.ts";

/** Placeholder names in a `{name}` template. */
export type TemplateParams<P extends string> =
  P extends `${string}{${infer K}}${infer R}` ? K | TemplateParams<R> : never;

export type TemplateValues<P extends string> = {
  readonly [K in TemplateParams<P>]: string | number;
};

type Part =
  | { readonly kind: "literal"; readonly text: string }
  | { readonly kind: "param"; readonly name: string };

export interface Template {
  readonly source: string;
  readonly separator: string;
  readonly params: readonly string[];
  readonly segments: number;
  build(values: Readonly<Record<string, string | number>>): string;
  match(value: string): Record<string, string> | null;
  /** The leading segments that can be filled from `values`. */
  prefix(
    values: Readonly<Record<string, string | number | undefined>>,
    maxSegments?: number,
  ): string;
  /** 1-based segment index of a placeholder that fills a whole segment. */
  segmentOf(name: string): number | undefined;
  /** Anchored POSIX regex for SQL (`~`). */
  readonly sqlPattern: string;
}

const PLACEHOLDER = /\{([A-Za-z_][A-Za-z0-9_]*)\}/g;

function parseSegment(segment: string): Part[] {
  const parts: Part[] = [];
  let last = 0;
  for (const match of segment.matchAll(PLACEHOLDER)) {
    if (match.index > last)
      parts.push({ kind: "literal", text: segment.slice(last, match.index) });
    parts.push({ kind: "param", name: match[1]! });
    last = match.index + match[0].length;
  }
  if (last < segment.length)
    parts.push({ kind: "literal", text: segment.slice(last) });
  return parts;
}

const escapeRegex = (text: string): string =>
  text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

export function parseTemplate(
  source: string,
  separator: string,
  validate: (name: string, value: string) => string | undefined,
): Template {
  const segments = source.split(separator).map(parseSegment);
  const params: string[] = [];
  for (const segment of segments) {
    if (segment.length === 0)
      throw new TypeError(`Template "${source}" has an empty segment`);
    for (let index = 1; index < segment.length; index++) {
      if (
        segment[index]!.kind === "param" &&
        segment[index - 1]!.kind === "param"
      ) {
        throw new TypeError(`Template "${source}" has adjacent placeholders`);
      }
    }
    for (const part of segment) {
      if (part.kind !== "param") continue;
      if (params.includes(part.name))
        throw new TypeError(`Template "${source}" repeats {${part.name}}`);
      params.push(part.name);
    }
  }
  if (
    /[{}]/.test(
      segments
        .flat()
        .map((part) => (part.kind === "literal" ? part.text : ""))
        .join(""),
    )
  ) {
    throw new TypeError(`Template "${source}" has an unbalanced brace`);
  }

  const sep = escapeRegex(separator);
  const valueClass = `[^${separator === "/" ? "/" : sep}]+`;
  const regexFor = (named: boolean): string =>
    segments
      .map((segment) =>
        segment
          .map((part) =>
            part.kind === "literal"
              ? escapeRegex(part.text)
              : named
                ? `(?<${part.name}>${valueClass})`
                : valueClass,
          )
          .join(""),
      )
      .join(sep);
  const matcher = new RegExp(`^${regexFor(true)}$`);

  const render = (name: string, raw: string | number | undefined): string => {
    if (
      raw === undefined ||
      (typeof raw !== "string" && typeof raw !== "number")
    ) {
      throw new DbException(
        dbError("invalid_input", `Missing value for {${name}}`),
      );
    }
    const value = String(raw);
    const problem =
      value === ""
        ? "is empty"
        : value.includes(separator)
          ? `contains "${separator}"`
          : validate(name, value);
    if (problem)
      throw new DbException(
        dbError("invalid_input", `Value for {${name}} ${problem}`),
      );
    return value;
  };
  const renderSegment = (
    segment: readonly Part[],
    values: Readonly<Record<string, string | number | undefined>>,
  ) =>
    segment
      .map((part) =>
        part.kind === "literal"
          ? part.text
          : render(part.name, values[part.name]),
      )
      .join("");

  return {
    source,
    separator,
    params,
    segments: segments.length,
    build: (values) =>
      segments.map((segment) => renderSegment(segment, values)).join(separator),
    match(value) {
      const found = matcher.exec(value);
      if (!found?.groups) return found ? {} : null;
      const out: Record<string, string> = {};
      for (const name of params) {
        const part = found.groups[name]!;
        if (validate(name, part)) return null;
        out[name] = part;
      }
      return out;
    },
    prefix(values, maxSegments = segments.length) {
      const out: string[] = [];
      for (const segment of segments.slice(0, maxSegments)) {
        if (
          segment.some(
            (part) => part.kind === "param" && values[part.name] === undefined,
          )
        )
          break;
        out.push(renderSegment(segment, values));
      }
      return out.join(separator);
    },
    segmentOf(name) {
      const index = segments.findIndex(
        (segment) =>
          segment.length === 1 &&
          segment[0]!.kind === "param" &&
          segment[0]!.name === name,
      );
      return index === -1 ? undefined : index + 1;
    },
    sqlPattern: `^${regexFor(false)}$`,
  };
}

export function sqlString(value: string): string {
  return `'${value.replaceAll("'", "''")}'`;
}

export function sqlIdent(value: string): string {
  return `"${value.replaceAll('"', '""')}"`;
}

/** Postgres identifier-safe name part: `customer-logos` → `customer_logos`. */
export function slug(value: string): string {
  return value
    .replace(/[^A-Za-z0-9]+/g, "_")
    .replace(/^_|_$/g, "")
    .toLowerCase();
}
