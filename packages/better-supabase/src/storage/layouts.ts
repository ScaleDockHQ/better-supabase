import { dbError, DbException } from "../core/errors.ts";
import { parseTemplate, type Template } from "../core/template.ts";

type Values = Readonly<Record<string, string | number | undefined>>;

/** A bucket's path templates, used together. */
export interface Layouts {
  readonly sources: readonly string[];
  /** Every placeholder name, in template order. */
  readonly params: readonly string[];
  /** Builds a path with the template whose placeholders are exactly the keys of `values`. */
  build(values: Values): string;
  /** The values of the first template that matches `path`, or `null`. */
  match(path: string): Record<string, string> | null;
  /** The folder that every template holding the keys of `values` shares. */
  prefix(values: Values): string;
  /** The 1-based segment of `param` in every template; throws when it differs or is missing. */
  segmentOf(param: string, kind: string): number;
  /** Throws when a template lacks `param`. */
  requireParam(param: string, label: string): void;
  /** `name ~ ...` for SQL, true when any template matches. */
  readonly sqlMatch: string;
}

// Characters Supabase Storage accepts in object keys, minus the separator.
const SAFE_SEGMENT = /^[\w!\-.*'() &$@=;:+,?]+$/;

function validateSegment(_name: string, value: string): string | undefined {
  if (value === "." || value === "..") return "is a relative path";
  if (!SAFE_SEGMENT.test(value))
    return "contains characters Storage does not allow";
  return undefined;
}

const keysOf = (values: Values): string[] =>
  Object.keys(values).filter((key) => values[key] !== undefined);

/** The longest folder, segment by segment, that holds every one of `folders`. */
function commonFolder(folders: readonly string[]): string {
  const split = folders.map((folder) => (folder ? folder.split("/") : []));
  const shared: string[] = [];
  for (const [index, segment] of (split[0] ?? []).entries()) {
    if (split.some((parts) => parts[index] !== segment)) break;
    shared.push(segment);
  }
  return shared.join("/");
}

export function pathLayouts(
  id: string,
  path: string | readonly string[],
  sqlString: (value: string) => string,
): Layouts {
  const sources: readonly string[] = typeof path === "string" ? [path] : path;
  if (sources.length === 0)
    throw new TypeError(`defineBucket(${id}): path needs a template`);
  const layouts: readonly Template[] = sources.map((source) =>
    parseTemplate(source, "/", validateSegment, { rest: true }),
  );
  const layoutFor = (values: Values): Template => {
    if (layouts.length === 1) return layouts[0]!;
    const keys = keysOf(values);
    const layout = layouts.find(
      (candidate) =>
        candidate.params.length === keys.length &&
        candidate.params.every((name) => keys.includes(name)),
    );
    if (layout) return layout;
    throw new DbException(
      dbError(
        "invalid_input",
        `No path template of bucket "${id}" takes exactly {${keys.join(", ")}}`,
      ),
    );
  };
  const patterns = layouts.map(
    (layout) => `name ~ ${sqlString(layout.sqlPattern)}`,
  );
  return {
    sources,
    params: [...new Set(layouts.flatMap((layout) => layout.params))],
    build(values) {
      // SAFETY: Template.build checks every value it reads and throws an
      // invalid_input DbException for a missing one.
      const filled = values as Readonly<Record<string, string | number>>;
      return layoutFor(values).build(filled);
    },
    match(value) {
      for (const layout of layouts) {
        const values = layout.match(value);
        if (values) return values;
      }
      return null;
    },
    prefix(values) {
      const given = keysOf(values);
      const fitting = layouts.filter((layout) =>
        given.every((key) => layout.params.includes(key)),
      );
      return commonFolder(
        (fitting.length > 0 ? fitting : layouts).map((layout) =>
          layout.prefix(
            values,
            layout.rest === undefined ? layout.segments - 1 : layout.segments,
          ),
        ),
      );
    },
    segmentOf(param, kind) {
      const indexes = layouts.map((layout) => {
        const index = layout.segmentOf(param);
        if (index === undefined) {
          throw new TypeError(
            `defineBucket: a ${kind} policy needs {${param}} as a whole path segment in "${layout.source}"`,
          );
        }
        return index;
      });
      if (new Set(indexes).size > 1) {
        throw new TypeError(
          `defineBucket: a ${kind} policy needs {${param}} at the same segment in every path of "${id}"`,
        );
      }
      return indexes[0]!;
    },
    requireParam(param, label) {
      for (const layout of layouts) {
        if (!layout.params.includes(param))
          throw new TypeError(
            `defineBucket: ${label} {${param}} is not in "${layout.source}"`,
          );
      }
    },
    sqlMatch:
      patterns.length === 1 ? patterns[0]! : `(${patterns.join(" or ")})`,
  };
}

/** Whether matched path values hold every value of `within`; a rest value may sit under it. */
export function inScope(
  values: Readonly<Record<string, string | number>> | null,
  within: Readonly<Record<string, string | number | undefined>>,
): boolean {
  if (!values) return false;
  return Object.entries(within).every(([key, expected]) => {
    if (expected === undefined) return true;
    const actual = String(values[key]);
    return (
      actual === String(expected) || actual.startsWith(`${String(expected)}/`)
    );
  });
}
