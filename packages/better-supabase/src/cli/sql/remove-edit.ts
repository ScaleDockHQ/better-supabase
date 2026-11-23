/**
 * The edits `better-supabase remove` makes: blocks out of the config's
 * `blocks`, and their clients out of `lib/blocks.ts`. Through a
 * `ConfigDocument`, like `config-edit.ts`, so comments and formatting survive.
 */

import type { ConfigEdit, WiredBlock } from "./config-edit.ts";

import { ConfigDocument } from "../config-document/index.ts";
import { finish, openConfig, openWiring } from "./config-edit.ts";

/** `source` with `names` taken out of `blocks`, keeping the form it has. */
export function removeBlocksFromConfig(
  source: string,
  names: readonly string[],
): ConfigEdit {
  const document = openConfig(source);

  if (!(document instanceof ConfigDocument)) {
    return document;
  }

  const blocks = document.locate(["blocks"]);

  if (blocks === undefined) {
    return { ok: true, text: source };
  }

  if (
    blocks.value.type !== "ObjectExpression" &&
    blocks.value.type !== "ArrayExpression"
  ) {
    return {
      ok: false,
      reason: "its blocks key isn't a literal object or list",
    };
  }

  for (const name of names) {
    document.remove(["blocks", name]);
  }

  return finish(document);
}

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/** `removeBlocksFromConfig` for `better-supabase.config.json`. */
export function removeBlocksFromJson(
  source: string,
  names: readonly string[],
): ConfigEdit {
  let config: unknown;

  try {
    config = JSON.parse(source);
  } catch {
    return { ok: false, reason: "it isn't valid JSON" };
  }

  if (!isRecord(config)) {
    return { ok: false, reason: "it isn't a JSON object" };
  }

  const blocks: unknown = config["blocks"];
  let next: unknown;

  if (blocks === undefined) {
    return { ok: true, text: source };
  }

  if (Array.isArray(blocks)) {
    const listed: readonly unknown[] = blocks;
    next = listed.filter((item) => {
      const name = isRecord(item) ? (item["name"] ?? item["block"]) : item;

      return typeof name !== "string" || !names.includes(name);
    });
  } else if (isRecord(blocks)) {
    next = Object.fromEntries(
      Object.entries(blocks).filter(([name]) => !names.includes(name)),
    );
  } else {
    return { ok: false, reason: "its blocks key isn't an object or a list" };
  }

  if (JSON.stringify(next) === JSON.stringify(blocks)) {
    return { ok: true, text: source };
  }

  const indent = /^[ \t]+/m.exec(source)?.[0] ?? "  ";

  return {
    ok: true,
    text: `${JSON.stringify({ ...config, blocks: next }, null, indent)}\n`,
  };
}

/**
 * `lib/blocks.ts` with `blocks` taken out of the blocks object, and the import
 * of each one's export dropped once nothing else names it.
 */
export function removeBlocksFromWiring(
  source: string,
  blocks: readonly WiredBlock[],
): ConfigEdit {
  const document = openWiring(source);

  if (!(document instanceof ConfigDocument)) {
    return document;
  }

  for (const block of blocks) {
    document.remove([block.key]);
  }

  return finish(document);
}
