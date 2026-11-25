import type { Node } from "oxc-parser";

import { walk } from "oxc-walker";

import type { CatalogTable } from "../introspect/types.ts";
import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import { lineColumn, parseSource } from "../config-document/parse.ts";
import { appliesTo } from "./rls.ts";
import { catalogOf, qualified } from "./shared.ts";

interface PublicEntry {
  readonly name: string;
  readonly tables: readonly string[];
  readonly file: string;
  readonly line: number;
}

const keyOf = (node: Node): string | undefined =>
  node.type === "Identifier"
    ? node.name
    : node.type === "Literal" && typeof node.value === "string"
      ? node.value
      : undefined;

const stringsOf = (node: Node): readonly string[] =>
  node.type === "ArrayExpression"
    ? node.elements.flatMap((element) =>
        element?.type === "Literal" && typeof element.value === "string"
          ? [element.value]
          : [],
      )
    : [];

/** The `bsb.kept(fn, { share: "public", tables })` calls in the app's sources. */
function publicEntries(context: DoctorContext): PublicEntry[] {
  const found: PublicEntry[] = [];

  for (const source of context.sources) {
    // A call to `.kept` names it in the text, so the rest need no parse.
    if (!source.text.includes("kept")) {
      continue;
    }

    walk(parseSource(source.text).program, {
      enter(node) {
        if (
          node.type !== "CallExpression" ||
          node.callee.type !== "MemberExpression" ||
          node.callee.computed ||
          node.callee.property.type !== "Identifier" ||
          node.callee.property.name !== "kept"
        ) {
          return;
        }

        const options = node.arguments[1];

        if (options?.type !== "ObjectExpression") {
          return;
        }

        const fields = new Map<string, Node>();

        for (const property of options.properties) {
          const key =
            property.type === "Property" && !property.computed
              ? keyOf(property.key)
              : undefined;

          if (key !== undefined && property.type === "Property") {
            fields.set(key, property.value);
          }
        }

        const share = fields.get("share");

        if (share?.type !== "Literal" || share.value !== "public") {
          return;
        }

        const name = fields.get("name");

        found.push({
          name:
            name?.type === "Literal" && typeof name.value === "string"
              ? name.value
              : "kept",
          tables: stringsOf(fields.get("tables") ?? options),
          file: source.path,
          line: lineColumn(source.text, node.start).line,
        });
      },
    });
  }

  return found;
}

const snakeOf = (key: string): string =>
  key.replaceAll(/[A-Z]/g, (letter) => `_${letter.toLowerCase()}`);

/** Why `anon` can't select rows of `table`, or `undefined` when it can. */
function anonBlock(table: CatalogTable): string | undefined {
  const granted = table.grants.some(
    (grant) =>
      (grant.role === "anon" || grant.role === "PUBLIC") &&
      grant.privileges.some(
        (privilege) => privilege.toLowerCase() === "select",
      ),
  );

  if (!granted) {
    return "no select grant";
  }

  const policed =
    !table.rls ||
    table.policies.some(
      (policy) =>
        policy.permissive &&
        (policy.command === "select" || policy.command === "all") &&
        appliesTo(policy, "anon"),
    );

  return policed ? undefined : "no select policy applies to anon";
}

/**
 * A `share: "public"` kept entry that reads a table `anon` can't select
 * (BS645): the fill runs as `anon`, so it keeps an empty or failed read for
 * every visitor until the entry expires.
 */
function publicKeptTables(context: DoctorContext): FindingInput[] {
  const tables = catalogOf(context).tables;

  return publicEntries(context).flatMap((entry) =>
    entry.tables.flatMap((key) => {
      const table = tables.find(
        (candidate) =>
          candidate.name === key ||
          candidate.name === snakeOf(key) ||
          qualified(candidate) === key,
      );

      const blocked = table === undefined ? undefined : anonBlock(table);

      if (table === undefined || blocked === undefined) {
        return [];
      }

      return [
        {
          message: `bsb.kept("${entry.name}") shares its entry with every visitor and reads ${qualified(table)}, which \`anon\` can't select (${blocked}). The fill runs as \`anon\`, so it would keep an empty read. Add an anon select policy for the public rows, or read the table per user.`,
          target: `${entry.file}:${entry.name}:${qualified(table)}`,
          location: { file: entry.file, line: entry.line },
          object: { kind: "table", schema: table.schema, name: table.name },
        },
      ];
    }),
  );
}

// `kept: { store: ... }` in the options of createNext.
const KEPT_STORE_OPTION = /\bkept\s*:\s*\{[^}]*\bstore\b/s;
const MEMORY_STORE_OPTION = /\bstore\s*:\s*memoryKeptStore\s*\(/;

/**
 * `bsb.kept` calls whose entries live in the memory store (BS647): the app
 * names no `kept.store`, or names `memoryKeptStore()`. Each instance then fills
 * and expires its own copy, so a second instance misses what the first kept and
 * a write on one never expires the others.
 */
function keptOnMemoryStore(context: DoctorContext): FindingInput[] {
  const configured = context.sources.some((source) =>
    KEPT_STORE_OPTION.test(source.text),
  );

  const memory = context.sources.find((source) =>
    MEMORY_STORE_OPTION.test(source.text),
  );

  if (configured && !memory) {
    return [];
  }

  for (const source of context.sources) {
    if (!source.text.includes(".kept(")) {
      continue;
    }

    let line: number | undefined;

    walk(parseSource(source.text).program, {
      enter(node) {
        if (
          line === undefined &&
          node.type === "CallExpression" &&
          node.callee.type === "MemberExpression" &&
          !node.callee.computed &&
          node.callee.property.type === "Identifier" &&
          node.callee.property.name === "kept"
        ) {
          line = lineColumn(source.text, node.start).line;
        }
      },
    });

    if (line !== undefined) {
      return [
        {
          message: `${source.path} calls \`bsb.kept()\`, and ${memory ? `${memory.path} sets` : "no source sets"} \`kept.store\` ${memory ? "to `memoryKeptStore()`" : "in createNext"}. The entries then live in each instance's memory: a second instance fills its own copy, and a write on one instance never expires the others. Pass \`kept: { store: postgresKeptStore({ client }) }\` or \`vercelRuntimeCacheAdapter(getCache, { lease })\` to createNext when the app runs more than one instance.`,
          target: `${source.path}:kept`,
          location: { file: source.path, line },
        },
      ];
    }
  }

  return [];
}

export const PUBLIC_KEPT_RULES: readonly Rule[] = [
  {
    code: "BS647",
    severity: "warning",
    title: "bsb.kept runs on the memory store",
    description:
      "`bsb.kept()` keeps entries in `memoryKeptStore()` unless createNext gets `kept: { store }`. With more than one instance, each one fills and expires its own copy: a second instance misses what the first kept, and a write on one never expires the others. Doctor reports a source that calls `bsb.kept()` while no source sets `kept.store`, or one sets it to `memoryKeptStore()`.",
    check: keptOnMemoryStore,
  },
  {
    code: "BS645",
    severity: "warning",
    title: "A public kept entry reads a table anon can't select",
    description:
      '`bsb.kept(fn, { share: "public" })` fills as the `anon` role and keeps one entry for every visitor. Doctor reads the `tables` of each such call in the app\'s sources and reports a table without an `anon` select grant, or with RLS and no select policy that applies to `anon`: the entry would hold an empty read.',
    check: publicKeptTables,
  },
];
