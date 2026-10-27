/**
 * The 0.15 config regrouping: top-level keys move into `database`, `auth`,
 * `gen`, `api` and `tooling`; `integrations` becomes `adapters`; block entries
 * take `ownership`, `owner`, `names` and `callbacks`; `claims.tenant` and the
 * tenant plugin's column become `auth.tenant`. The edit is textual, like the
 * rest of `config-edit.ts`, so comments and formatting survive.
 */

import type { ConfigEdit, Property } from "./config-edit.ts";

import {
  CONFIG_GROUPS,
  groupEntries,
  RENAMED_BLOCK_KEYS,
  RENAMED_CONFIG_KEYS,
} from "../../config/index.ts";
import { withRecordTypes } from "../codemod-record-bindings.ts";
import {
  closingIndex,
  configObject,
  indentAt,
  mask,
  properties,
  skipSpace,
} from "./config-edit.ts";

interface Edit {
  readonly start: number;
  readonly end: number;
  readonly text: string;
}

type Pairs = readonly (readonly [grouped: string, flat: string])[];

const GROUP_ORDER = ["database", "auth", "gen", "api", "tooling"] as const;

const GROUP_KEYS: ReadonlySet<string> = new Set(GROUP_ORDER);

const GROUP_OF = new Map<string, string>(
  Object.entries(CONFIG_GROUPS).flatMap(([group, keys]) =>
    keys.map((key): [string, string] => [key, group]),
  ),
);

const ENVIRONMENT_KEY = /^\$(?:development|production|test|ci)$/;

function applyEdits(source: string, edits: readonly Edit[]): string {
  let text = source;

  for (const edit of edits.toSorted((a, b) => b.start - a.start)) {
    text = text.slice(0, edit.start) + edit.text + text.slice(edit.end);
  }

  return text;
}

const isObjectAt = (code: string, index: number): boolean =>
  code[index] === "{";

/** The key token of `prop` renamed, keeping its quotes. */
function renameAt(source: string, prop: Property, to: string): Edit {
  const quote = source[prop.start];
  const quoted = quote === '"' || quote === "'";
  const length = (prop.key?.length ?? 0) + (quoted ? 2 : 0);

  if (prop.valueStart === prop.start) {
    return {
      start: prop.start,
      end: prop.start + length,
      text: `${to}: ${prop.key ?? ""}`,
    };
  }

  return {
    start: prop.start,
    end: prop.start + length,
    text: quoted ? `${quote}${to}${quote}` : to,
  };
}

/** Renames the keys of the object at `open` by `pairs` (flat to grouped). */
function renameIn(
  source: string,
  code: string,
  open: number,
  pairs: Pairs,
): Edit[] {
  const props = properties(source, code, open) ?? [];

  return props.flatMap((prop) => {
    const pair = pairs.find(([, flat]) => flat === prop.key);

    return pair === undefined ? [] : [renameAt(source, prop, pair[0])];
  });
}

/** The same renames in every object value of the object at `open`. */
function renameEach(
  source: string,
  code: string,
  open: number,
  pairs: Pairs,
): Edit[] {
  const props = properties(source, code, open) ?? [];

  return props.flatMap((prop) =>
    isObjectAt(code, prop.valueStart)
      ? renameIn(source, code, prop.valueStart, pairs)
      : [],
  );
}

/** The range to cut for `props[index]`, with its comma and line. */
export function cutRange(
  source: string,
  code: string,
  open: number,
  props: readonly Property[],
  index: number,
  multiline: boolean,
): { readonly start: number; readonly end: number; readonly text: string } {
  const prop = props[index]!;
  const previous = props[index - 1];
  const after = skipSpace(code, prop.valueEnd);
  const tailFrom = code[after] === "," ? after + 1 : prop.valueEnd;

  if (!multiline) {
    return {
      start: prop.start,
      end: code[after] === "," ? skipSpace(code, tailFrom) : prop.valueEnd,
      text: source.slice(prop.start, prop.valueEnd),
    };
  }

  let before = open + 1;

  if (previous) {
    before = skipSpace(code, previous.valueEnd) + 1;
  }

  const gap = source.slice(before, prop.start);
  const newline = gap.indexOf("\n");
  const start = newline === -1 ? before : before + newline + 1;
  const lineEnd = source.indexOf("\n", tailFrom);

  const restIsBlank =
    lineEnd !== -1 && code.slice(tailFrom, lineEnd).trim() === "";

  const trailing = restIsBlank ? source.slice(tailFrom, lineEnd).trimEnd() : "";

  return {
    start,
    end: restIsBlank ? lineEnd + 1 : tailFrom,
    text: `${source.slice(start, prop.valueEnd)},${trailing}`,
  };
}

interface Organization {
  claim?: string;
  column?: string;
}

/**
 * Pulls `claims.tenant` and `plugins.tenant.column` out of the root object at
 * `open`: the edits that remove them and the values for `auth.tenant`.
 */
function organizationEdits(
  source: string,
  code: string,
  open: number,
  props: readonly Property[],
): { readonly edits: Edit[]; readonly organization: Organization } {
  const edits: Edit[] = [];
  const organization: Organization = {};
  const claims = props.find((prop) => prop.key === "claims");

  if (claims !== undefined && isObjectAt(code, claims.valueStart)) {
    const inner = properties(source, code, claims.valueStart) ?? [];
    const index = inner.findIndex((prop) => prop.key === "tenant");
    const tenant = inner[index];

    if (tenant !== undefined) {
      organization.claim = source.slice(tenant.valueStart, tenant.valueEnd);

      const [from, list, at] =
        inner.length === 1
          ? [open, props, props.indexOf(claims)]
          : [claims.valueStart, inner, index];

      const multiline = code
        .slice(from, closingIndex(code, from))
        .includes("\n");

      const cut = cutRange(source, code, from, list, at, multiline);

      edits.push({ start: cut.start, end: cut.end, text: "" });
    }
  }

  const plugins = props.find((prop) => prop.key === "plugins");

  if (plugins !== undefined && isObjectAt(code, plugins.valueStart)) {
    const inner = properties(source, code, plugins.valueStart) ?? [];
    const tenant = inner.find((prop) => prop.key === "tenant");

    if (tenant !== undefined && isObjectAt(code, tenant.valueStart)) {
      const column = (properties(source, code, tenant.valueStart) ?? []).find(
        (prop) => prop.key === "column",
      );

      if (column !== undefined) {
        organization.column = source.slice(column.valueStart, column.valueEnd);
      }

      edits.push({
        start: tenant.valueStart,
        end: tenant.valueEnd,
        text: "true",
      });
    }
  }

  return { edits, organization };
}

/**
 * `text` with its first line at `first` and each later line indented by `by`,
 * except lines inside a string literal, whose text is part of the value.
 */
function reindent(text: string, first: string, by: string): string {
  const code = mask(text);
  const lines = text.split("\n");
  let offset = 0;
  // mask() blanks string contents, so every quote it leaves opens or closes one.
  let open = false;

  return lines
    .map((line, index) => {
      const inString = open;

      for (const char of code.slice(offset, offset + line.length)) {
        if (char === '"' || char === "'" || char === "`") {
          open = !open;
        }
      }

      offset += line.length + 1;

      if (index === 0) {
        return first + line.trimStart();
      }

      return inString || line.trim() === "" ? line : by + line;
    })
    .join("\n");
}

/**
 * The object literal at `open` with the 0.15 grouping applied, or a reason it
 * can't be: a spread or computed key at the top level.
 */
function groupObjectAt(source: string, open: number): ConfigEdit {
  const code = mask(source);
  const props = properties(source, code, open);

  if (props === undefined) {
    return { ok: false, reason: "the config object could not be read" };
  }

  const edits: Edit[] = [];

  for (const prop of props) {
    const objectValue = isObjectAt(code, prop.valueStart);

    if (prop.key === "sql" && objectValue) {
      edits.push(
        ...renameIn(source, code, prop.valueStart, [["owner", "scope"]]),
      );
    } else if (prop.key === "blocks" && objectValue) {
      edits.push(
        ...renameEach(source, code, prop.valueStart, RENAMED_BLOCK_KEYS),
      );
    } else if (prop.key === "appTables" && objectValue) {
      edits.push(
        ...renameEach(source, code, prop.valueStart, [["owner", "scope"]]),
      );
    } else if (prop.key === "$env" && objectValue) {
      for (const env of properties(source, code, prop.valueStart) ?? []) {
        if (isObjectAt(code, env.valueStart)) {
          edits.push(...nestedEdit(source, env));
        }
      }
    } else if (
      prop.key !== undefined &&
      ENVIRONMENT_KEY.test(prop.key) &&
      objectValue
    ) {
      edits.push(...nestedEdit(source, prop));
    }
  }

  const { edits: orgEdits, organization } = organizationEdits(
    source,
    code,
    open,
    props,
  );

  const renamed = applyEdits(source, [...edits, ...orgEdits]);

  return regroup(renamed, open, organization);
}

/** An environment block's object, grouped, as one edit. */
function nestedEdit(source: string, prop: Property): Edit[] {
  const code = mask(source);
  const close = closingIndex(code, prop.valueStart);
  const inner = source.slice(prop.valueStart, close + 1);
  const grouped = groupObjectAt(inner, 0);

  return grouped.ok && grouped.text !== inner
    ? [{ start: prop.valueStart, end: close + 1, text: grouped.text }]
    : [];
}

function regroup(
  source: string,
  open: number,
  organization: Organization,
): ConfigEdit {
  const code = mask(source);
  const props = properties(source, code, open);

  if (props === undefined) {
    return { ok: false, reason: "the config object could not be read" };
  }

  if (props.some((prop) => prop.key === undefined)) {
    return {
      ok: false,
      reason:
        "the config object has a spread or a computed key; move its keys into the groups by hand",
    };
  }

  const close = closingIndex(code, open);
  const multiline = code.slice(open, close).includes("\n");
  const indent = multiline ? indentAt(source, props[0]?.start ?? open) : "";
  const unit = multiline ? "  " : "";
  const members = new Map<string, string[]>();
  const firstAt = new Map<string, number>();
  const edits: Edit[] = [];

  let moved =
    organization.claim !== undefined || organization.column !== undefined;

  const addMember = (group: string, text: string, at: number): void => {
    members.set(group, [...(members.get(group) ?? []), text]);

    if (!firstAt.has(group)) {
      firstAt.set(group, at);
    }
  };

  for (const [index, prop] of props.entries()) {
    const key = prop.key!;

    const group = GROUP_OF.get(key);

    const rename = RENAMED_CONFIG_KEYS.find(([, flat]) => flat === key);
    const isGroup = GROUP_KEYS.has(key);

    if (group === undefined && !isGroup) {
      if (rename !== undefined) {
        edits.push(renameAt(source, prop, rename[0]));
        moved = true;
      }

      continue;
    }

    const cut = cutRange(source, code, open, props, index, multiline);

    if (isGroup) {
      if (!isObjectAt(code, prop.valueStart)) {
        continue;
      }

      const inner = source.slice(
        prop.valueStart + 1,
        closingIndex(code, prop.valueStart),
      );

      const trimmed = inner.trim().replace(/,$/, "");
      const first = (properties(source, code, prop.valueStart) ?? [])[0];
      const own = first === undefined ? "" : indentAt(source, first.start);

      if (trimmed !== "") {
        addMember(
          key,
          multiline
            ? `${own}${trimmed},`
                .split("\n")
                .map((line) =>
                  line.startsWith(own)
                    ? indent + unit + line.slice(own.length)
                    : line,
                )
                .join("\n")
            : `${trimmed},`,
          cut.start,
        );
      } else if (!firstAt.has(key)) {
        firstAt.set(key, cut.start);
      }

      edits.push({ start: cut.start, end: cut.end, text: "" });
      continue;
    }

    moved = true;
    addMember(
      group!,
      multiline
        ? reindent(cut.text.replace(/\n$/, ""), indent + unit, unit)
        : cut.text,
      cut.start,
    );
    edits.push({ start: cut.start, end: cut.end, text: "" });
  }

  const org = [
    organization.claim === undefined ? "" : `claim: ${organization.claim}`,
    organization.column === undefined ? "" : `column: ${organization.column}`,
  ].filter((part) => part !== "");

  if (org.length > 0) {
    const text = `tenant: { ${org.join(", ")} },`;
    members.set("auth", [
      multiline ? `${indent}${unit}${text}` : text,
      ...(members.get("auth") ?? []),
    ]);

    if (!firstAt.has("auth")) {
      const last = props.at(-1);
      const comma = last && code[skipSpace(code, last.valueEnd)] === ",";

      if (last !== undefined && !comma) {
        edits.push({ start: last.valueEnd, end: last.valueEnd, text: "," });
      }

      firstAt.set(
        "auth",
        multiline ? source.lastIndexOf("\n", close - 1) + 1 : close,
      );

      if (!multiline && last !== undefined) {
        members.set("auth", [` ${members.get("auth")![0]!}`]);
      }
    }
  }

  for (const group of GROUP_ORDER) {
    const list = members.get(group);
    const at = firstAt.get(group);

    if (list === undefined || at === undefined) {
      continue;
    }

    const body = multiline
      ? list
          .map((text) => text.replace(/,+(\s*(?:\/\/[^\n]*)?)$/, ",$1"))
          .join("\n")
      : list.map((text) => text.trim().replace(/,$/, "")).join(", ");

    edits.push({
      start: at,
      end: at,
      text: multiline
        ? `${indent}${group}: {\n${body}\n${indent}},\n`
        : `${group}: { ${body} }, `,
    });
  }

  if (!moved) {
    return { ok: true, text: source };
  }

  const text = applyEdits(source, edits);

  return { ok: true, text: multiline ? text : tidyInline(text, open) };
}

/** Removes the `, }` an inline regroup leaves before the object's brace. */
export function tidyInline(text: string, open: number): string {
  const close = closingIndex(mask(text), open);

  if (text.slice(open + 1, close).trim() === "") {
    return `${text.slice(0, open + 1)}${text.slice(close)}`;
  }

  const head = text.slice(0, close).replace(/,\s*$/, " ");

  return head + text.slice(close);
}

/** `better-supabase.config.ts` with the 0.15 grouping applied. */
export function groupConfigSource(original: string): ConfigEdit {
  const source = withRecordTypes(original);
  const open = configObject(mask(source));

  if (open === undefined) {
    return {
      ok: false,
      reason: "no defineConfig({...}) or default export object found",
    };
  }

  return groupObjectAt(source, open);
}

/** {@link groupConfigSource} for a `better-supabase.config.json`. */
export function groupConfigJson(original: string): ConfigEdit {
  const source = withRecordTypes(original);
  let config: unknown;

  try {
    config = JSON.parse(source);
  } catch {
    return { ok: false, reason: "it isn't valid JSON" };
  }

  if (typeof config !== "object" || config === null || Array.isArray(config)) {
    return { ok: false, reason: "it isn't a JSON object" };
  }

  const text = `${JSON.stringify(groupEntries(config), null, 2)}\n`;

  return {
    ok: true,
    text:
      JSON.stringify(JSON.parse(text)) === JSON.stringify(config)
        ? source
        : text,
  };
}
