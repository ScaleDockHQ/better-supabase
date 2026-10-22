/**
 * The 0.15 move of the `plugins` config key: each flag becomes the block whose
 * repository extension replaces the plugin (`timestamps` to `updated-at`,
 * `actor` to `created-by`, `softDelete` to `trash`), with its columns as the
 * block's options, and `tenant` becomes `auth.organization.column` when the
 * `memberships` block is not installed. `tenant` also pins
 * `auth.organization.onMissing: "error"`, the 0.14 plugin's default.
 */

import type { ConfigEdit, Property } from "./config-edit.ts";

import { isRecord } from "../guards.ts";
import {
  addBlocksToConfig,
  closingIndex,
  configObject,
  mask,
  properties,
  setPathInConfig,
} from "./config-edit.ts";
import { cutRange } from "./config-group.ts";

/** The block each plugin flag became, and its column keys as block options. */
const PLUGIN_BLOCKS: Readonly<
  Record<
    string,
    {
      readonly block: string;
      readonly options: Readonly<Record<string, string>>;
    }
  >
> = {
  timestamps: {
    block: "updated-at",
    options: { createdAt: "createdAt", updatedAt: "updatedAt" },
  },
  actor: {
    block: "created-by",
    options: {
      createdBy: "createdBy",
      updatedBy: "updatedBy",
      impersonatedBy: "impersonatedBy",
    },
  },
  softDelete: { block: "trash", options: { column: "deletedAt" } },
};

const DEFAULT_ORGANIZATION_COLUMN = "organization_id";

/** One plugin flag, read from the config: off, on, or on with its columns. */
type Flag = false | Readonly<Record<string, string>>;

interface Moves {
  readonly blocks: readonly (readonly [
    block: string,
    options: Readonly<Record<string, string>>,
  ])[];
  readonly tenant: boolean;
}

function movesOf(
  flags: Readonly<Record<string, Flag>>,
): Moves | { readonly reason: string } {
  const blocks: [string, Record<string, string>][] = [];
  let tenant = false;

  for (const [name, flag] of Object.entries(flags)) {
    if (name === "tenant") {
      tenant = flag !== false;
      continue;
    }

    const move = PLUGIN_BLOCKS[name];

    if (move === undefined) {
      return { reason: `plugins.${name} is not a plugin flag 0.14 had` };
    }

    if (flag === false) {
      continue;
    }

    const options: Record<string, string> = {};

    for (const [key, value] of Object.entries(flag)) {
      const option = move.options[key];

      if (option === undefined) {
        return { reason: `plugins.${name}.${key} is not a column it took` };
      }

      options[option] = value;
    }

    blocks.push([move.block, options]);
  }

  return { blocks, tenant };
}

/** A string literal's value, or undefined for any other expression. */
function stringValue(text: string): string | undefined {
  const match = /^(["'])((?:(?!\1)[^\\])*)\1$/.exec(text.trim());

  return match?.[2];
}

function flagsInSource(
  source: string,
  code: string,
  open: number,
): Record<string, Flag> | { readonly reason: string } {
  const flags: Record<string, Flag> = {};

  for (const prop of properties(source, code, open) ?? []) {
    const value = source.slice(prop.valueStart, prop.valueEnd).trim();

    if (prop.key === undefined) {
      return { reason: "plugins has a spread or a computed key" };
    }

    if (value === "true" || value === "false") {
      flags[prop.key] = value === "true" ? {} : false;
      continue;
    }

    if (code[prop.valueStart] !== "{") {
      return { reason: `plugins.${prop.key} isn't true, false or an object` };
    }

    const columns: Record<string, string> = {};

    for (const inner of properties(source, code, prop.valueStart) ?? []) {
      const column = stringValue(
        source.slice(inner.valueStart, inner.valueEnd),
      );

      if (inner.key === undefined || column === undefined) {
        return { reason: `plugins.${prop.key} has a key that isn't a string` };
      }

      columns[inner.key] = column;
    }

    flags[prop.key] = columns;
  }

  return flags;
}

/** Whether the `blocks` value names `memberships`, as a key or a list item. */
const MEMBERSHIPS = /["']memberships["']|\bmemberships\s*:/;

/** `better-supabase.config.ts` with `plugins` moved into blocks. */
export function movePluginsInSource(source: string): ConfigEdit {
  const code = mask(source);
  const root = configObject(code);

  if (root === undefined) {
    return { ok: true, text: source };
  }

  const props = properties(source, code, root) ?? [];
  const index = props.findIndex((prop) => prop.key === "plugins");
  const plugins = props[index];

  if (plugins === undefined) {
    return { ok: true, text: source };
  }

  if (code[plugins.valueStart] !== "{") {
    return { ok: false, reason: "its plugins key isn't a literal object" };
  }

  const flags = flagsInSource(source, code, plugins.valueStart);

  if ("reason" in flags) {
    return { ok: false, reason: String(flags.reason) };
  }

  const moves = movesOf(flags);

  if ("reason" in moves) {
    return { ok: false, reason: moves.reason };
  }

  const multiline = code.slice(root, closingIndex(code, root)).includes("\n");
  const cut = cutRange(source, code, root, props, index, multiline);

  let edit: ConfigEdit = {
    ok: true,
    text: source.slice(0, cut.start) + source.slice(cut.end),
  };

  const blocks = props.find((prop) => prop.key === "blocks");

  const memberships =
    blocks !== undefined &&
    MEMBERSHIPS.test(source.slice(blocks.valueStart, blocks.valueEnd));

  const organization = organizationText(source, code, props);
  const organizationColumn = /\bcolumn\s*:/.test(organization);
  const onMissing = /\bonMissing\s*:/.test(organization);

  const steps: ((text: string) => ConfigEdit)[] = [
    ...moves.blocks.flatMap(([block, options]) => [
      (text: string) => addBlocksToConfig(text, [block]),
      ...Object.entries(options).map(
        ([key, value]) =>
          (text: string) =>
            setPathInConfig(text, ["blocks", block, "options", key], value),
      ),
    ]),
    ...(moves.tenant && !memberships && !organizationColumn
      ? [
          (text: string) =>
            setPathInConfig(
              text,
              ["auth", "organization", "column"],
              DEFAULT_ORGANIZATION_COLUMN,
            ),
        ]
      : []),
    ...(moves.tenant && !onMissing
      ? [
          (text: string) =>
            setPathInConfig(
              text,
              ["auth", "organization", "onMissing"],
              "error",
            ),
        ]
      : []),
  ];

  for (const step of steps) {
    if (!edit.ok) {
      return edit;
    }

    edit = step(edit.text);
  }

  return edit;
}

/** The source of `auth.organization`, or `""` without one. */
function organizationText(
  source: string,
  code: string,
  props: readonly Property[],
): string {
  const auth = props.find((prop) => prop.key === "auth");

  if (auth === undefined || code[auth.valueStart] !== "{") {
    return "";
  }

  const organization = (properties(source, code, auth.valueStart) ?? []).find(
    (prop) => prop.key === "organization",
  );

  return organization === undefined
    ? ""
    : source.slice(organization.valueStart, organization.valueEnd);
}

const isColumns = (value: unknown): value is Readonly<Record<string, string>> =>
  isRecord(value) &&
  Object.values(value).every((column) => typeof column === "string");

function flagsInJson(
  plugins: unknown,
): Record<string, Flag> | { readonly reason: string } {
  if (!isRecord(plugins)) {
    return { reason: "its plugins key isn't an object" };
  }

  const flags: Record<string, Flag> = {};

  for (const [name, value] of Object.entries(plugins)) {
    if (typeof value === "boolean") {
      flags[name] = value ? {} : false;
    } else if (isColumns(value)) {
      flags[name] = value;
    } else {
      return { reason: `plugins.${name} isn't true, false or columns` };
    }
  }

  return flags;
}

const objectAt = (value: unknown): Record<string, unknown> =>
  isRecord(value) ? value : {};

/** `movePluginsInSource` for `better-supabase.config.json`. */
export function movePluginsInJson(source: string): ConfigEdit {
  let config: unknown;

  try {
    config = JSON.parse(source);
  } catch {
    return { ok: true, text: source };
  }

  if (!isRecord(config) || !("plugins" in config)) {
    return { ok: true, text: source };
  }

  const { plugins, ...rest } = config;
  const flags = flagsInJson(plugins);

  if ("reason" in flags) {
    return { ok: false, reason: String(flags.reason) };
  }

  const moves = movesOf(flags);

  if ("reason" in moves) {
    return { ok: false, reason: moves.reason };
  }

  const listed: unknown = rest["blocks"] ?? {};

  const blocks: Record<string, unknown> = Array.isArray(listed)
    ? Object.fromEntries(listed.map((name: unknown) => [String(name), {}]))
    : { ...objectAt(listed) };

  const memberships = "memberships" in blocks;

  for (const [block, options] of moves.blocks) {
    const entry = objectAt(blocks[block]);

    blocks[block] = {
      ...entry,
      ...(Object.keys(options).length === 0
        ? {}
        : { options: { ...objectAt(entry["options"]), ...options } }),
    };
  }

  const next: Record<string, unknown> = {
    ...rest,
    ...(moves.blocks.length === 0 && rest["blocks"] === undefined
      ? {}
      : { blocks: moves.blocks.length === 0 ? rest["blocks"] : blocks }),
  };

  if (moves.tenant) {
    const auth = objectAt(next["auth"]);
    const organization = objectAt(auth["organization"]);

    next["auth"] = {
      ...auth,
      organization: {
        ...(memberships ? {} : { column: DEFAULT_ORGANIZATION_COLUMN }),
        onMissing: "error",
        ...organization,
      },
    };
  }

  const indent = /^[ \t]+/m.exec(source)?.[0] ?? "  ";

  return { ok: true, text: `${JSON.stringify(next, null, indent)}\n` };
}

/** `edit` with `plugins` moved into blocks, after the regrouping. */
export function withoutPlugins(edit: ConfigEdit, json: boolean): ConfigEdit {
  if (!edit.ok) {
    return edit;
  }

  return json ? movePluginsInJson(edit.text) : movePluginsInSource(edit.text);
}
