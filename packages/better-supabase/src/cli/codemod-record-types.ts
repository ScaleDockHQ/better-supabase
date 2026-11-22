import type { Codemod, ReviewLine } from "./codemod.ts";

import { topLevelValue } from "./codemod-prune.ts";
import { KEY, LEADING_COMMENTS, segments } from "./codemod-sort-keys.ts";

const ALIAS = /\balias\s*:\s*(?:"([^"]*)"|'([^']*)')/;
const ON_START = /(?<![\w$.])on\s*:\s*(?=[[{])/g;
const STRING = /"([^"\\]*)"|'([^'\\]*)'/g;
const BARE_KEY = /([A-Za-z_$][\w$]*)(?=\s*:(?!:))/g;

const same = (name: string): string => name.replaceAll("-", "_");

/** The registered type names, and the alias each one writes. */
function registered(text: string): ReadonlyMap<string, string | undefined> {
  const located = topLevelValue(text, "recordTypes");
  const names = new Map<string, string | undefined>();

  if (located === undefined) {
    return names;
  }

  const value = text.slice(located.start, located.end).trim();

  if (!value.startsWith("{") || !value.endsWith("}")) {
    return names;
  }

  for (const part of segments(value.slice(1, -1))) {
    const core = part.trim();
    const entry = core.slice(LEADING_COMMENTS.exec(core)![0].length);
    const key = KEY.exec(entry);
    const name = key === null ? undefined : (key[1] ?? key[2] ?? key[3]);

    if (name !== undefined) {
      const alias = ALIAS.exec(entry);

      names.set(name, alias === null ? undefined : (alias[1] ?? alias[2]));
    }
  }

  return names;
}

/** The index after the bracket that closes the one at `from`. */
function closing(text: string, from: number): number {
  let depth = 0;

  for (let index = from; index < text.length; index += 1) {
    const char = text.charAt(index);

    if (char === '"' || char === "'") {
      index += 1;

      while (index < text.length && text.charAt(index) !== char) {
        index += text.charAt(index) === "\\" ? 2 : 1;
      }
    } else if (char === "[" || char === "{") {
      depth += 1;
    } else if (char === "]" || char === "}") {
      depth -= 1;

      if (depth === 0) {
        return index + 1;
      }
    }
  }

  return text.length;
}

/**
 * The names in `blocks.<block>.on` that differ from a registered record type
 * only by `-` and `_`, or that are its alias, written as the registered name.
 */
export function recordTypes(text: string): {
  readonly text: string;
  readonly review: readonly ReviewLine[];
} {
  const types = registered(text);
  const blocks = topLevelValue(text, "blocks");

  if (types.size === 0 || blocks === undefined) {
    return { text, review: [] };
  }

  const target = new Map<string, string>();

  for (const [name, alias] of types) {
    target.set(same(name), name);

    if (alias !== undefined) {
      target.set(alias, name);
    }
  }

  const fix = (name: string): string => {
    if (types.has(name)) {
      return name;
    }

    return target.get(name) ?? target.get(same(name)) ?? name;
  };

  const head = text.slice(0, blocks.start);
  const tail = text.slice(blocks.end);
  const body = text.slice(blocks.start, blocks.end);
  let out = "";
  let last = 0;

  for (const start of body.matchAll(ON_START)) {
    const from = start.index + start[0].length;

    if (from < last) {
      continue;
    }

    const to = closing(body, from);

    const inner = body
      .slice(from, to)
      .replaceAll(STRING, (match, double?: string, single?: string) => {
        const name = double ?? single ?? "";
        const quote = match.charAt(0);

        return `${quote}${fix(name)}${quote}`;
      })
      .replaceAll(BARE_KEY, (name: string) => fix(name));

    out += body.slice(last, from) + inner;
    last = to;
  }

  out += body.slice(last);

  return { text: head + out + tail, review: [] };
}

export function recordTypesCodemod(): Codemod {
  return {
    name: "record-types",
    description:
      "Write the names in blocks.<name>.on as the record types in recordTypes, where they differ by - and _ or are an alias",
    source: recordTypes,
  };
}
