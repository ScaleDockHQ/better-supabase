/** A noun in its singular and plural snake_case forms, e.g. `work_item`. */
export interface EntityNoun {
  readonly singular: string;
  readonly plural: string;
}

/** The case forms a rename covers. */
export type EntityCase = "snake" | "kebab" | "camel" | "pascal";

/** One noun renamed: every case form of `from` becomes the same form of `to`. */
export interface EntityRename {
  readonly from: EntityNoun;
  readonly to: EntityNoun;
  /** Defaults to every case. */
  readonly cases?: readonly EntityCase[];
  /**
   * Match only whole identifier segments, so `deal` leaves `ideal` and `dealer`
   * alone. Defaults to true. The tenant rename sets false: it has renamed
   * `organization` inside any identifier since `sql.naming.tenant`.
   */
  readonly bounded?: boolean;
}

/** Renames for a set of nouns, applied in one pass so no rename feeds another. */
export interface EntityNames {
  readonly renames: readonly EntityRename[];
  /** Whether any noun gets a new name. */
  readonly renamed: boolean;
  /** An identifier with every default noun renamed. */
  rename(identifier: string): string;
  /** An identifier with every new noun renamed back to its default. */
  reverse(identifier: string): string;
}

export const DEFAULT_TENANT: EntityNoun = {
  singular: "organization",
  plural: "organizations",
};

const ENTITY_NAME = /^[a-z][a-z0-9_]{0,40}$/;
const ALL_CASES: readonly EntityCase[] = ["snake", "kebab", "camel", "pascal"];
const LOWER_CASES: readonly EntityCase[] = ["snake", "kebab", "camel"];

/** The English plural of a snake_case noun: `company` to `companies`. */
export function pluralOf(word: string): string {
  if (/[^aeiou]y$/.test(word)) {
    return `${word.slice(0, -1)}ies`;
  }

  if (/(s|x|z|ch|sh)$/.test(word)) {
    return `${word}es`;
  }

  return `${word}s`;
}

/** Throws unless `name` is a lowercase identifier a noun can be. */
export function checkEntityName(where: string, name: string): string {
  if (!ENTITY_NAME.test(name)) {
    throw new TypeError(
      `${where}: "${name}" is not a lowercase identifier (letters, digits and underscores)`,
    );
  }

  return name;
}

/** A noun with its plural, derived unless given. */
export function entityNoun(singular: string, plural?: string): EntityNoun {
  return { singular, plural: plural ?? pluralOf(singular) };
}

function camel(snake: string): string {
  return snake.replaceAll(/_([a-z0-9])/g, (_, c: string) => c.toUpperCase());
}

function form(snake: string, kind: EntityCase): string {
  switch (kind) {
    case "snake": {
      return snake;
    }

    case "kebab": {
      return snake.replaceAll("_", "-");
    }

    case "camel": {
      return camel(snake);
    }

    case "pascal": {
      const value = camel(snake);

      return value.charAt(0).toUpperCase() + value.slice(1);
    }

    default: {
      const exhaustive: never = kind;

      return exhaustive;
    }
  }
}

interface Alternative {
  readonly match: string;
  readonly replace: Partial<Record<EntityCase, string>>;
  readonly pattern: string;
}

/** The case a matched form is used in, read from the character after it. */
function caseAt(next: string | undefined): EntityCase {
  if (next !== undefined && /[A-Z]/.test(next)) {
    return "camel";
  }

  return next === "-" ? "kebab" : "snake";
}

function escape(value: string): string {
  return value.replaceAll(/[.*+?^${}()|[\]\\-]/g, String.raw`\$&`);
}

function alternatives(
  rename: EntityRename,
  direction: "forward" | "back",
): Alternative[] {
  const [source, target] =
    direction === "forward"
      ? [rename.from, rename.to]
      : [rename.to, rename.from];

  const bounded = rename.bounded ?? true;
  const found = new Map<string, Alternative>();

  for (const kind of rename.cases ?? ALL_CASES) {
    for (const number of ["plural", "singular"] as const) {
      const match = form(source[number], kind);
      const replace = form(target[number], kind);
      const known = found.get(match);

      if (known !== undefined) {
        found.set(match, {
          ...known,
          replace: { ...known.replace, [kind]: replace },
        });
        continue;
      }

      const lower = kind !== "pascal";
      const before = bounded && lower ? "(?<![A-Za-z0-9])" : "";
      const after = bounded ? "(?![a-z0-9])" : "";
      found.set(match, {
        match,
        replace: { [kind]: replace },
        pattern: `${before}${escape(match)}${after}`,
      });
    }
  }

  return [...found.values()];
}

function compile(
  renames: readonly EntityRename[],
  direction: "forward" | "back",
): (identifier: string) => string {
  const active = renames.filter(
    (rename) =>
      rename.from.singular !== rename.to.singular ||
      rename.from.plural !== rename.to.plural,
  );

  if (active.length === 0) {
    return (identifier) => identifier;
  }

  const all = active
    .flatMap((rename) => alternatives(rename, direction))
    .toSorted((a, b) => b.match.length - a.match.length);

  const replacements = new Map(all.map((each) => [each.match, each.replace]));
  const pattern = new RegExp(all.map((each) => each.pattern).join("|"), "g");

  return (identifier) =>
    identifier.replaceAll(pattern, (matched: string, offset: number) => {
      const options = replacements.get(matched) ?? {};

      return (
        options[caseAt(identifier[offset + matched.length])] ??
        Object.values(options)[0] ??
        matched
      );
    });
}

/** Renames for `renames`, longest form first, in one pass. */
export function entityNames(
  renames: readonly EntityRename[] = [],
): EntityNames {
  const forward = compile(renames, "forward");
  const back = compile(renames, "back");

  return {
    renames,
    renamed: renames.some(
      (rename) =>
        rename.from.singular !== rename.to.singular ||
        rename.from.plural !== rename.to.plural,
    ),
    rename: forward,
    reverse: back,
  };
}

/** Several rename sets as one, applied in the same pass. */
export function composeNames(...names: readonly EntityNames[]): EntityNames {
  return entityNames(names.flatMap((each) => each.renames));
}

/**
 * The tenant rename (`blocks.tenant.entities.organization`): lowercase forms,
 * anywhere in an identifier, as the tenant rename has always worked.
 */
export function tenantRename(
  to: EntityNoun | string = DEFAULT_TENANT,
): EntityRename {
  const noun =
    typeof to === "string"
      ? entityNoun(checkEntityName("blocks.tenant.entities.organization", to))
      : to;

  return { from: DEFAULT_TENANT, to: noun, cases: LOWER_CASES, bounded: false };
}

/** The renames for the tenant concept alone. */
export function tenantNames(to?: EntityNoun | string): EntityNames {
  return entityNames(to === undefined ? [] : [tenantRename(to)]);
}
