import { posix } from "node:path";

import type { GeneratedFile, ResolvedConfig } from "../../config/index.ts";
import type { Framework } from "../project/detect.ts";

import { blockSubjectTypes } from "../../config/index.ts";
import { PRESET_CATALOG } from "../../preset/index.ts";
import { resolveModule } from "../../sql/index.ts";
import { importPath } from "../core/io.ts";
import { hasPermissionConstants } from "./block-names.ts";
import { blockConfigPath, generatorBlocks } from "./blocks.ts";
import { GENERATED_HEADER } from "./emit.ts";
import { q } from "./shared.ts";

type FeaturesConfig = Pick<
  ResolvedConfig,
  | "appTables"
  | "blocks"
  | "blockNames"
  | "buckets"
  | "casing"
  | "generateFeatures"
  | "output"
  | "sql"
  | "subjects"
>;

/** One installed block that adds record sections. */
interface SectionBlock {
  readonly name: string;
  /** Its key on the feature's `blocks`, such as `shareLinks`. */
  readonly key: string;
  /** The block constant, renamed when its entities are. */
  readonly local: string;
  /** Its subpath, or undefined when `blocks.generated.ts` exports it renamed. */
  readonly from: string | undefined;
  readonly sections: Readonly<Record<string, readonly string[]>>;
}

function camel(name: string): string {
  return name.replaceAll(/[-_]([a-z0-9])/g, (_, c: string) => c.toUpperCase());
}

function pascal(name: string): string {
  const named = camel(name);

  return named.charAt(0).toUpperCase() + named.slice(1);
}

function kebab(name: string): string {
  return name.replaceAll("_", "-");
}

/**
 * The subject types a block's SQL serves, which is where its sections load: the
 * types `blocks.<name>.options.subjects` names, or every tenant-scoped
 * registered subject when it names none. Versions keep only the listed types
 * and the subjects with `versions` set.
 */
function servedSubjects(config: FeaturesConfig, block: string): Set<string> {
  const listed = resolveModule(config.blocks[block]).options["subjects"];
  const registry = Object.entries(config.subjects);

  const named = Array.isArray(listed)
    ? listed.filter((type): type is string => typeof type === "string")
    : typeof listed === "object" && listed !== null
      ? Object.keys(listed)
      : undefined;

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

function sectionBlocks(config: FeaturesConfig): readonly SectionBlock[] {
  const manifests = new Map(
    PRESET_CATALOG.manifests.map((manifest) => [manifest.name, manifest]),
  );

  return generatorBlocks(config).flatMap((block) => {
    const manifest = manifests.get(block.name);

    if (
      manifest?.sections === undefined ||
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
        sections: manifest.sections,
      },
    ];
  });
}

/** Each section name once, from the first block that declares it. */
function ownedSections(
  blocks: readonly SectionBlock[],
): readonly (readonly [string, readonly string[]])[] {
  const seen = new Map<string, readonly string[]>();

  for (const block of blocks) {
    for (const [name, writes] of Object.entries(block.sections)) {
      if (!seen.has(name)) {
        seen.set(name, writes);
      }
    }
  }

  return [...seen];
}

function featureFile(
  config: FeaturesConfig,
  path: string,
  type: string,
  blocks: readonly SectionBlock[],
  extras: {
    readonly access: string | undefined;
    readonly permissions: boolean;
  },
): GeneratedFile {
  const generated = importPath(path, blockConfigPath(config));

  const fromGenerated = [
    "blockConfig",
    ...(extras.permissions ? ["permissions"] : []),
    ...blocks.filter((block) => block.from === undefined).map((b) => b.local),
  ].toSorted((a, b) => a.localeCompare(b));

  const imports = [
    'import { defineRecordFeature } from "better-supabase/records";',
    ...blocks.flatMap((block) =>
      block.from === undefined
        ? []
        : [`import { ${block.local} } from ${q(block.from)};`],
    ),
    ...(extras.access === undefined
      ? []
      : [`import { accessBlock } from ${q(extras.access)};`]),
  ].toSorted((a, b) => a.localeCompare(b));

  return {
    path,
    contents: [
      GENERATED_HEADER,
      "",
      ...imports,
      "",
      `import { ${fromGenerated.join(", ")} } from ${q(generated)};`,
      "",
      "/**",
      ` * The ${type} record page: a section for each installed block that adds one.`,
      " * Pass it to `recordServer`, `recordQueries` or `createRecordProvider`.",
      " */",
      `export const ${camel(type)}Feature = defineRecordFeature({`,
      `  type: ${q(type)},`,
      "  blocks: {",
      ...blocks.map((block) =>
        block.key === block.local
          ? `    ${block.key},`
          : `    ${block.key}: ${block.local},`,
      ),
      "  },",
      "  config: blockConfig,",
      ...(extras.permissions ? ["  permissions,"] : []),
      ...(extras.access === undefined ? [] : ["  access: accessBlock,"]),
      "});",
      "",
    ].join("\n"),
  };
}

function actionName(type: string, section: string, write: string): string {
  return `${write}${pascal(type)}${pascal(section)}`;
}

function serverFile(
  config: FeaturesConfig,
  path: string,
  type: string,
  feature: string,
): GeneratedFile {
  const server = posix.join(posix.dirname(config.output), "server.ts");
  const name = camel(type);

  return {
    path,
    contents: [
      GENERATED_HEADER,
      "",
      'import "server-only";',
      "",
      'import { recordServer } from "better-supabase/next";',
      "",
      `import { bs } from ${q(importPath(path, server))};`,
      `import { ${name}Feature } from ${q(importPath(path, feature))};`,
      "",
      "/**",
      ` * Loads a ${type}'s sections in a Server Component, outside \`"use cache"\`,`,
      " * and runs its section writes as Server Actions.",
      " */",
      `export const ${name}Record = recordServer(bs, ${name}Feature);`,
      "",
    ].join("\n"),
  };
}

function actionsFile(
  path: string,
  type: string,
  server: string,
  sections: readonly (readonly [string, readonly string[]])[],
): GeneratedFile {
  const name = camel(type);

  return {
    path,
    contents: [
      GENERATED_HEADER,
      "",
      '"use server";',
      "",
      `import { ${name}Record } from ${q(importPath(path, server))};`,
      ...sections.flatMap(([section, writes]) =>
        writes.map(
          (write) =>
            `\nexport const ${actionName(type, section, write)} = ${name}Record.actions.${section}.${write};`,
        ),
      ),
      "",
    ].join("\n"),
  };
}

function providerFile(
  path: string,
  type: string,
  feature: string,
  actions:
    | {
        readonly path: string;
        readonly sections: readonly (readonly [string, readonly string[]])[];
      }
    | undefined,
): GeneratedFile {
  const name = camel(type);
  const Name = pascal(type);

  const names =
    actions?.sections.flatMap(([section, writes]) =>
      writes.map((write) => actionName(type, section, write)),
    ) ?? [];

  const withActions =
    actions === undefined || names.length === 0
      ? undefined
      : { path: actions.path, sections: actions.sections };

  return {
    path,
    contents: [
      GENERATED_HEADER,
      "",
      '"use client";',
      "",
      'import { createElement, type ReactNode } from "react";',
      "",
      'import { createRecordProvider } from "better-supabase/react";',
      "",
      ...(withActions === undefined
        ? []
        : [
            "import {",
            ...names.map((action) => `  ${action},`),
            `} from ${q(importPath(path, withActions.path))};`,
          ]),
      `import { ${name}Feature } from ${q(importPath(path, feature))};`,
      "",
      `const kit = createRecordProvider(${name}Feature);`,
      "",
      ...(withActions === undefined
        ? []
        : [
            "const writes = {",
            ...withActions.sections.flatMap(([section, writes]) =>
              writes.length === 0
                ? []
                : [
                    `  ${section}: {`,
                    ...writes.map(
                      (write) =>
                        `    ${write}: ${actionName(type, section, write)},`,
                    ),
                    "  },",
                  ],
            ),
            "};",
            "",
          ]),
      `export type ${Name}RecordProviderProps = Omit<`,
      "  Parameters<typeof kit.RecordProvider>[0],",
      '  "writes"',
      ">;",
      "",
      "/**",
      ` * Holds a ${type}'s sections for its children and follows \`topic\`.`,
      withActions === undefined
        ? " * Writes run on the client, under RLS."
        : " * Writes run as the generated Server Actions.",
      " */",
      `export function ${Name}RecordProvider(`,
      `  props: ${Name}RecordProviderProps,`,
      "): ReactNode {",
      withActions === undefined
        ? "  return createElement(kit.RecordProvider, props);"
        : "  return createElement(kit.RecordProvider, { ...props, writes });",
      "}",
      "",
      `/** The ${type} record context: \`{ state, actions, meta }\`. */`,
      `export const use${Name}Record = kit.useRecord;`,
      "",
    ].join("\n"),
  };
}

function queriesFile(
  path: string,
  type: string,
  feature: string,
): GeneratedFile {
  const name = camel(type);

  return {
    path,
    contents: [
      GENERATED_HEADER,
      "",
      "import {",
      "  recordQueries,",
      "  type RecordQueriesOptions,",
      '} from "better-supabase/query";',
      "",
      `import { ${name}Feature } from ${q(importPath(path, feature))};`,
      "",
      "/**",
      ` * TanStack Query options for a ${type}'s sections and writes, over the`,
      " * block clients `createBlocks` builds.",
      " */",
      `export const ${name}Queries = (`,
      "  clients: Parameters<typeof recordQueries>[1],",
      "  options?: RecordQueriesOptions,",
      `) => recordQueries(${name}Feature, clients, options);`,
      "",
    ].join("\n"),
  };
}

/**
 * `features/` next to the main module: one record feature per subject with a
 * section for each installed block that serves it, and the bindings for the
 * project's frameworks. Subjects the section blocks register themselves (a
 * comment, an attachment) get none. Empty with `generateFeatures: false`.
 */
export function emitFeatures(
  config: FeaturesConfig,
  frameworks: readonly Framework[] = [],
): GeneratedFile[] {
  if (!config.generateFeatures || config.blockNames.length === 0) {
    return [];
  }

  const blocks = sectionBlocks(config);

  if (blocks.length === 0) {
    return [];
  }

  const served = new Map(
    blocks.map((block) => [block.name, servedSubjects(config, block.name)]),
  );

  const access = PRESET_CATALOG.manifests.find(
    (manifest) => manifest.name === "access",
  )?.client;

  const installed = new Set(generatorBlocks(config).map((block) => block.name));

  const extras = {
    access: installed.has("access") ? access?.subpath : undefined,
    permissions: hasPermissionConstants(config),
  };

  const next = frameworks.includes("next");

  const react =
    next || frameworks.includes("vite") || frameworks.includes("expo");

  const query = frameworks.includes("tanstack-query");
  const dir = posix.join(posix.dirname(config.output), "features");
  const files: GeneratedFile[] = [];
  const features: [string, string][] = [];

  const inner = new Set(
    blocks.flatMap((block) => blockSubjectTypes(block.name, config.blocks)),
  );

  for (const type of Object.keys(config.subjects).toSorted()) {
    if (inner.has(type)) {
      continue;
    }

    const own = blocks.filter((block) => served.get(block.name)?.has(type));

    if (own.length === 0) {
      continue;
    }

    const base = posix.join(dir, kebab(type), kebab(type));
    const feature = `${base}-feature.ts`;
    const sections = ownedSections(own);

    files.push(featureFile(config, feature, type, own, extras));
    features.push([type, feature]);

    if (next) {
      const server = `${base}-server.ts`;
      const actions = `${base}-actions.ts`;

      files.push(
        serverFile(config, server, type, feature),
        actionsFile(actions, type, server, sections),
        providerFile(`${base}-provider.ts`, type, feature, {
          path: actions,
          sections,
        }),
      );
    } else if (react) {
      files.push(providerFile(`${base}-provider.ts`, type, feature, undefined));
    }

    if (query) {
      files.push(queriesFile(`${base}-queries.ts`, type, feature));
    }
  }

  if (features.length === 0) {
    return [];
  }

  const index = posix.join(dir, "index.ts");

  files.push({
    path: index,
    contents: [
      GENERATED_HEADER,
      "",
      ...features.map(
        ([type, path]) =>
          `export { ${camel(type)}Feature } from ${q(importPath(index, path))};`,
      ),
      "",
    ].join("\n"),
  });

  return files;
}
