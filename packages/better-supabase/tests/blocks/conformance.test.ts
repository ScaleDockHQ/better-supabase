import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

import type { AnyBlock } from "../../src/blocks/define-block.ts";

import { BLOCK_OPTION_SCHEMAS } from "../../src/blocks/options-registry.ts";
import { BLOCK_MANIFESTS } from "../../src/blocks/registry.ts";
import { SQL_MODULES } from "../../src/sql/registry.ts";

/**
 * The block contract (ADR 0029), checked over every manifest. Each allowlist
 * holds today's exceptions; shrink them to zero, never grow them.
 */

const BLOCKS_DIR = join(import.meta.dirname, "../../src/blocks");
const SRC_DIR = join(import.meta.dirname, "../../src");
const RECIPES = join(
  import.meta.dirname,
  "../../../../scripts/build-recipes.ts",
);

/** Blocks whose creator is not `create<Name>(options)`. */
const CREATOR_NAME: readonly string[] = ["audit"];
/** Blocks with a TypeScript side but no `create`, or a positional creator. */
const NO_CREATOR: readonly string[] = [
  "onboarding",
  "outbox",
  "settings",
  "webhook-inbox",
];
/** Blocks whose creator doesn't wrap its client with `withBlockHooks`. */
const NO_HOOKS: readonly string[] = [
  "agents",
  "ai-cache",
  "ai-chat",
  "ai-files",
  "ai-providers",
  "ai-tasks",
  "announcements",
  "api-keys",
  "attachments",
  "audit",
  "billing",
  "bookings",
  "bulk",
  "calendar",
  "comments",
  "connectors",
  "custom-fields",
  "number-sequences",
  "push",
  "rank",
  "rate-limit",
  "relations",
  "reminders",
  "saved-views",
  "service-principals",
  "share-links",
  "sso",
  "state-machine",
  "tags",
  "teams",
  "undo",
  "usage",
  "waitlist",
  "webhooks",
  "workflow-builder",
  "workflows",
];
/** Blocks with calls that skip `blockCall`. */
const NO_BLOCK_CALL: readonly string[] = [
  "audit",
  "comments",
  "notifications",
  "usage",
  "webhooks",
];
/** Blocks with managed tables that take no `extraColumns` or `fields`. */
const NO_FIELDS: readonly string[] = [
  "access-requests",
  "agents",
  "ai-cache",
  "ai-chat",
  "ai-files",
  "ai-providers",
  "ai-tasks",
  "announcements",
  "api-keys",
  "approvals",
  "attachments",
  "audit",
  "billing",
  "bookings",
  "bulk",
  "calendar",
  "catalog",
  "collections",
  "comments",
  "connectors",
  "custom-fields",
  "data-lifecycle",
  "documents",
  "identities",
  "imports",
  "inbox",
  "incoming-webhooks",
  "knowledge",
  "memory",
  "metrics",
  "notifications",
  "number-sequences",
  "orders",
  "organizations",
  "parties",
  "pipelines",
  "profiles",
  "promotions",
  "push",
  "quotes",
  "reactions",
  "relations",
  "reminders",
  "saved-views",
  "search",
  "service-principals",
  "share-links",
  "signatures",
  "sla",
  "sso",
  "state-machine",
  "tags",
  "targets",
  "teams",
  "templates",
  "time-tracking",
  "trash",
  "usage",
  "versions",
  "waitlist",
  "webhooks",
  "work-items",
  "workflow-builder",
  "workflows",
];
/** Blocks that build a sibling block's client. */
const SIBLING_CLIENTS: readonly string[] = [];

const pascal = (name: string): string =>
  name
    .split("-")
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join("");

/** Each block's directory, from the manifest that names it. */
const DIRS = new Map(
  readdirSync(BLOCKS_DIR)
    .filter((dir) => existsSync(join(BLOCKS_DIR, dir, "manifest.ts")))
    .flatMap((dir) =>
      [
        ...readFileSync(join(BLOCKS_DIR, dir, "manifest.ts"), "utf8").matchAll(
          /name: "([a-z-]+)"/g,
        ),
      ].map((match) => [match[1] ?? "", join(BLOCKS_DIR, dir)] as const),
    ),
);

/** The directory a manifest lives in. */
const dirOf = (block: AnyBlock): string => {
  const dir = DIRS.get(block.name);
  if (dir === undefined)
    throw new Error(`No manifest.ts names "${block.name}"`);
  return dir;
};

const OWN_FILES = new Set([
  "index.ts",
  "manifest.ts",
  "events.ts",
  "client.ts",
]);

/** Code without its comments, so a doc comment naming a creator doesn't count. */
const withoutComments = (source: string): string =>
  source.replaceAll(/\/\*[\s\S]*?\*\//g, "").replaceAll(/^\s*\/\/.*$/gm, "");

/** The block's own code: its creator's file, or every file of a one-block directory. */
const sourcesOf = (block: AnyBlock): string => {
  const dir = dirOf(block);
  const files = readdirSync(dir).filter(
    (file) => file.endsWith(".ts") && !OWN_FILES.has(file),
  );
  const shared =
    BLOCK_MANIFESTS.filter((other) => dirOf(other) === dir).length > 1;
  const creator = block.create?.name;
  const picked =
    shared && creator !== undefined
      ? files.filter((file) =>
          new RegExp(`export (async )?function ${creator}\\b`).test(
            readFileSync(join(dir, file), "utf8"),
          ),
        )
      : files;
  return picked
    .map((file) => withoutComments(readFileSync(join(dir, file), "utf8")))
    .join("\n");
};

/** A block with a TypeScript side: a directory with an `index.ts` entry. */
const hasClient = (block: AnyBlock): boolean =>
  existsSync(join(dirOf(block), "index.ts"));

const withCreator = BLOCK_MANIFESTS.filter(
  (block) => block.create !== undefined,
);

const failing = (
  blocks: readonly AnyBlock[],
  check: (block: AnyBlock) => boolean,
): string[] =>
  blocks
    .filter((block) => !check(block))
    .map((block) => block.name)
    .sort();

const moduleNames = (name: string) => SQL_MODULES[name]?.names;

describe("block manifests", () => {
  it("installs every SQL module through exactly one block", () => {
    const owners = new Map<string, string[]>();
    for (const block of BLOCK_MANIFESTS)
      for (const module of block.sql)
        owners.set(module, [...(owners.get(module) ?? []), block.name]);
    expect(
      Object.keys(SQL_MODULES).filter(
        (module) => owners.get(module)?.length !== 1,
      ),
    ).toEqual([]);
    expect(
      [...owners.keys()].filter((module) => !(module in SQL_MODULES)),
    ).toEqual([]);
  });

  it("names every block once", () => {
    const names = BLOCK_MANIFESTS.map((block) => block.name);
    expect(names.filter((name, i) => names.indexOf(name) !== i)).toEqual([]);
  });

  it("takes the options each SQL module reads", () => {
    const mismatched = BLOCK_MANIFESTS.flatMap((block) =>
      block.sql.flatMap((module) => {
        const keys = [...(moduleNames(module)?.options ?? [])].sort();
        const schema = block.options[module];
        if (keys.length === 0)
          return schema === undefined ? [] : [`${module}: has no options`];
        if (schema === undefined) return [`${module}: no options schema`];
        const unknown = schema["~standard"].validate({ notAnOption: 1 });
        const declared = Object.keys(schema.specs).sort();
        if (JSON.stringify(declared) !== JSON.stringify(keys))
          return [`${module}: declares ${declared.join(", ")}`];
        return "issues" in unknown && unknown.issues !== undefined
          ? []
          : [`${module}: accepts unknown options`];
      }),
    );
    expect(mismatched).toEqual([]);
  });

  it("lists every SQL module's options schema in the registry", () => {
    expect(Object.keys(BLOCK_OPTION_SCHEMAS).sort()).toEqual(
      Object.keys(SQL_MODULES).sort(),
    );
    const differing = BLOCK_MANIFESTS.flatMap((block) =>
      Object.entries(block.options).flatMap(([module, schema]) =>
        Object.entries(BLOCK_OPTION_SCHEMAS).some(
          ([name, listed]) => name === module && listed === schema,
        )
          ? []
          : [module],
      ),
    );
    expect(differing).toEqual([]);
  });

  it("lists the recipes that name the block", () => {
    const source = readFileSync(RECIPES, "utf8");
    const named = [
      ...source.matchAll(
        /slug: "([a-z-]+)",\s*title: "[^"]*",\s*block: "([a-z-]+)"/g,
      ),
      ...source.matchAll(
        /\[\s*"([a-z-]+)",\s*"[^"]+",\s*"([a-z-]+)",\s*"[^"]* [^"]*",\s*\]/g,
      ),
    ].map((match) => `${match[2]}: ${match[1]}`);
    const owner = (module: string) =>
      BLOCK_MANIFESTS.find((block) => block.sql.includes(module))?.name ??
      module;
    const listed = BLOCK_MANIFESTS.flatMap((block) =>
      block.recipes.map((slug) => `${block.name}: ${slug}`),
    );
    expect(
      named
        .map((entry) => {
          const [module = "", slug = ""] = entry.split(": ");
          return `${owner(module)}: ${slug}`;
        })
        .sort(),
    ).toEqual(listed.sort());
  });
});

describe("the block contract", () => {
  it("names the creator create<Name>", () => {
    expect(
      failing(
        withCreator,
        (block) => block.create?.name === `create${pascal(block.name)}`,
      ),
    ).toEqual(CREATOR_NAME);
  });

  it("gives every block with a client a creator", () => {
    expect(
      failing(
        BLOCK_MANIFESTS.filter(hasClient),
        (block) => block.create !== undefined,
      ),
    ).toEqual(NO_CREATOR);
  });

  it("accepts hooks", () => {
    expect(
      failing(withCreator, (block) =>
        sourcesOf(block).includes("withBlockHooks("),
      ),
    ).toEqual(NO_HOOKS);
  });

  it("calls the database through blockCall", () => {
    expect(
      failing(withCreator, (block) => {
        const source = sourcesOf(block);
        return (
          block.sql.length === 0 ||
          (source.includes("blockCall(") && !source.includes("transport.call("))
        );
      }),
    ).toEqual(NO_BLOCK_CALL);
  });

  it("takes fields and extraColumns on managed tables", () => {
    expect(
      failing(withCreator, (block) =>
        block.sql.every((module) => {
          const names = moduleNames(module);
          if (Object.keys(names?.tables ?? {}).length === 0) return true;
          return (
            (names?.options ?? []).includes("extraColumns") &&
            sourcesOf(block).includes("blockFields(")
          );
        }),
      ),
    ).toEqual(NO_FIELDS);
  });

  it("has its own event map with every event its SQL records", () => {
    const missing = BLOCK_MANIFESTS.flatMap((block) => {
      const own = new Set(block.events.types);
      return block.sql.flatMap((module) =>
        Object.keys(moduleNames(module)?.events ?? {})
          .filter((type) => !own.has(type))
          .map((type) => `${block.name}: ${type}`),
      );
    });
    expect(missing).toEqual([]);
  });

  it("declares only events its SQL records or its code emits", () => {
    const code = readdirSync(SRC_DIR, { recursive: true, encoding: "utf8" })
      .filter((file) => file.endsWith(".ts") && !file.endsWith("events.ts"))
      .map((file) => readFileSync(join(SRC_DIR, file), "utf8"))
      .join("\n");
    const unused = BLOCK_MANIFESTS.flatMap((block) => {
      const recorded = new Set(
        block.sql.flatMap((module) =>
          Object.keys(moduleNames(module)?.events ?? {}),
        ),
      );
      return block.events.types
        .filter((type) => !recorded.has(type) && !code.includes(`"${type}"`))
        .map((type) => `${block.name}: ${type}`);
    });
    expect(unused).toEqual([]);
  });

  it("creates no sibling block's client", () => {
    const creators = withCreator.map((block) => block.create?.name ?? "");
    expect(
      failing(withCreator, (block) => {
        const source = sourcesOf(block);
        return creators.every(
          (creator) =>
            creator === block.create?.name ||
            !new RegExp(`\\b${creator}\\(`).test(source),
        );
      }),
    ).toEqual(SIBLING_CLIENTS);
  });
});
