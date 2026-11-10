import { posix } from "node:path";

import type { GeneratedFile, ResolvedConfig } from "../../config/index.ts";

import { blockSubjectTypes } from "../../config/index.ts";
import { PRESET_CATALOG } from "../../preset/index.ts";
import { importPath } from "../core/io.ts";
import { hasPermissionConstants } from "./block-names.ts";
import {
  blockConfigEntries,
  blockConfigModulePath,
  blockConfigPath,
  blockPermissionsPath,
  blockModulesOn,
  blockSliceName,
  blockSlicesPath,
  generatorBlocks,
} from "./blocks.ts";
import { GENERATED_HEADER } from "./emit.ts";
import { docComment, importStatement, sortImports } from "./layout.ts";
import { renamedBlockPath } from "./renamed-blocks.ts";
import { prop, q } from "./shared.ts";

type RecordsConfig = Pick<
  ResolvedConfig,
  | "appTables"
  | "blocks"
  | "blockNames"
  | "buckets"
  | "casing"
  | "gen"
  | "records"
  | "instances"
  | "output"
  | "sql"
  | "subjects"
>;

/** `names` and every block they require, from the catalog. */
function withRequired(names: readonly string[]): readonly string[] {
  const requires = new Map(
    PRESET_CATALOG.blocks.map((block) => [block.name, block.requires]),
  );

  const found = new Set<string>();

  const add = (name: string): void => {
    if (!found.has(name)) {
      found.add(name);

      for (const required of requires.get(name) ?? []) {
        add(required);
      }
    }
  };

  for (const name of names) {
    add(name);
  }

  return [...found];
}

/** One installed block with a record binding. */
interface BindingBlock {
  readonly name: string;
  /** Its key on the record type's `blocks`, such as `shareLinks`. */
  readonly key: string;
  /** The block constant, renamed when its entities are. */
  readonly local: string;
  /** Its subpath, or undefined when `blocks.generated.ts` exports it renamed. */
  readonly from: string | undefined;
}

function camel(name: string): string {
  return name.replaceAll(/[-_]([a-z0-9])/g, (_, c: string) => c.toUpperCase());
}

function kebab(name: string): string {
  return name.replaceAll("_", "-");
}

/**
 * The record types a block's SQL serves, which is where its binding loads: the
 * types `blocks.<instance>.on` names, or every tenant-scoped registered subject
 * when it names none. Versions keep only the listed types and the subjects with
 * `versions` set.
 */
function servedSubjects(config: RecordsConfig, block: string): Set<string> {
  const listed = config.blocks[block]?.on;
  const registry = Object.entries(config.subjects);

  const named: readonly string[] | undefined =
    listed === undefined
      ? undefined
      : Array.isArray(listed)
        ? listed
        : Object.keys(listed);

  if (block === "versions") {
    const versioned = registry
      .filter(([, entry]) => entry.versions !== undefined)
      .map(([type]) => type);

    return new Set([...(named ?? []), ...versioned]);
  }

  if (named !== undefined) {
    return new Set(named);
  }

  return new Set(
    registry
      .filter(([, entry]) => entry.tenant !== false)
      .map(([type]) => type),
  );
}

function bindingBlocks(config: RecordsConfig): readonly BindingBlock[] {
  const manifests = new Map(
    PRESET_CATALOG.manifests.map((manifest) => [manifest.name, manifest]),
  );

  return generatorBlocks(config).flatMap((block) => {
    const manifest = manifests.get(block.name);

    if (
      manifest?.record === undefined ||
      manifest.client === null ||
      block.client === undefined
    ) {
      return [];
    }

    const renamed = block.client.export !== manifest.client.export;

    return [
      {
        name: block.name,
        key: camel(block.name),
        local: block.client.export,
        from: renamed ? undefined : block.client.subpath,
      },
    ];
  });
}

function recordFile(
  config: RecordsConfig,
  path: string,
  type: string,
  blocks: readonly BindingBlock[],
  extras: {
    readonly access: string | undefined;
    readonly permissions: boolean;
    /** The instances with a slice, with `gen.blockModules`. */
    readonly slices?: ReadonlySet<string>;
  },
): GeneratedFile {
  const generated = importPath(path, blockConfigPath(config));
  const configModule = importPath(path, blockConfigModulePath(config));

  // `permissions` comes from the config module, which holds plain data: the
  // generated one imports every installed block, and a record file loads in
  // the browser.
  const split = blockModulesOn(config.gen);

  const instances = split
    ? blocks.filter((block) => extras.slices?.has(block.name))
    : [];

  const fromConfig = split
    ? []
    : ["blockConfig", ...(extras.permissions ? ["permissions"] : [])];

  // With `gen.blockModules` a renamed block is its own module: a record
  // imports its blocks and never `blocks.generated.ts`, which pulls in every
  // block (ADR 0605).
  const renamedBlocks = blocks.filter((block) => block.from === undefined);

  const fromGenerated = split
    ? []
    : renamedBlocks.map((b) => b.local).toSorted((a, b) => a.localeCompare(b));

  const imports = sortImports([
    'import { defineRecordType } from "better-supabase/records";',
    ...blocks.flatMap((block) =>
      block.from === undefined
        ? split
          ? [
              `import { ${block.local} } from ${q(importPath(path, renamedBlockPath(config, block.name)))};`,
            ]
          : []
        : [`import { ${block.local} } from ${q(block.from)};`],
    ),
    ...(extras.access === undefined
      ? []
      : [`import { permissionsBlock } from ${q(extras.access)};`]),
  ]);

  return {
    path,
    contents: [
      GENERATED_HEADER,
      "",
      ...imports,
      "",
      ...(split
        ? [
            ...(instances.length === 0
              ? []
              : importStatement(
                  instances
                    .map((block) => blockSliceName(block.name))
                    .toSorted((a, b) => a.localeCompare(b)),
                  importPath(path, blockSlicesPath(config)),
                )),
            ...(extras.permissions
              ? [
                  `import { permissions } from ${q(importPath(path, blockPermissionsPath(config)))};`,
                ]
              : []),
          ]
        : importStatement(fromConfig, configModule)),
      ...(fromGenerated.length === 0
        ? []
        : importStatement(fromGenerated, generated)),
      "",
      ...docComment(
        `The ${type} record type: each installed block that binds to it. Pass it to \`bsb.record\`, \`recordQueries\` or \`createRecordProvider\`.`,
      ),
      `export const ${camel(type)}Record = defineRecordType({`,
      `  type: ${q(type)},`,
      "  blocks: {",
      ...blocks.map((block) =>
        block.key === block.local
          ? `    ${block.key},`
          : `    ${block.key}: ${block.local},`,
      ),
      "  },",
      ...(split
        ? [
            "  config: {",
            ...instances.map(
              (block) =>
                `    ${prop(block.name)}: ${blockSliceName(block.name)},`,
            ),
            "  },",
          ]
        : ["  config: blockConfig,"]),
      ...(extras.permissions ? ["  permissions,"] : []),
      ...(extras.access === undefined ? [] : ["  access: permissionsBlock,"]),
      "});",
      "",
    ].join("\n"),
  };
}

/**
 * `records/` next to the main module: one `records/<type>.ts` per record type
 * that an installed block binds to, and an index. Record types the binding
 * blocks and the blocks they require register themselves (a comment's message,
 * an attachment) get none. Empty with `records: false`.
 */
export function emitRecords(config: RecordsConfig): GeneratedFile[] {
  if (!config.records || config.blockNames.length === 0) {
    return [];
  }

  const blocks = bindingBlocks(config);

  if (blocks.length === 0) {
    return [];
  }

  const served = new Map(
    blocks.map((block) => [block.name, servedSubjects(config, block.name)]),
  );

  const access = PRESET_CATALOG.manifests.find(
    (manifest) => manifest.name === "permissions",
  )?.client;

  const installed = new Set(generatorBlocks(config).map((block) => block.name));

  const extras = {
    access: installed.has("permissions") ? access?.subpath : undefined,
    permissions: hasPermissionConstants(config),
    ...(blockModulesOn(config.gen)
      ? { slices: new Set(Object.keys(blockConfigEntries(config))) }
      : {}),
  };

  const dir = posix.join(posix.dirname(config.output), "records");
  const files: GeneratedFile[] = [];
  const types: [string, string][] = [];

  const inner = new Set(
    withRequired(blocks.map((block) => block.name)).flatMap((name) =>
      blockSubjectTypes(name, config.blocks),
    ),
  );

  for (const type of Object.keys(config.subjects).toSorted()) {
    if (inner.has(type)) {
      continue;
    }

    const own = blocks.filter((block) => served.get(block.name)?.has(type));

    if (own.length === 0) {
      continue;
    }

    const path = posix.join(dir, `${kebab(type)}.ts`);

    files.push(recordFile(config, path, type, own, extras));
    types.push([type, path]);
  }

  if (types.length === 0) {
    return [];
  }

  const index = posix.join(dir, "index.ts");

  files.push({
    path: index,
    contents: [
      GENERATED_HEADER,
      "",
      ...types.map(
        ([type, path]) =>
          `export { ${camel(type)}Record } from ${q(importPath(index, path))};`,
      ),
      "",
    ].join("\n"),
  });

  return files;
}
