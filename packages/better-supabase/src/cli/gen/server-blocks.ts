import { posix } from "node:path";

import type { GeneratedFile, ResolvedConfig } from "../../config/index.ts";
import type { PresetCatalog } from "../../preset/index.ts";
import type { AppColumns, emitBlockConfig } from "./blocks.ts";

import { PRESET_CATALOG } from "../../preset/index.ts";
import {
  blockConfigEntries,
  camelOf,
  instanceMapLines,
  renamedBlockLines,
} from "./blocks.ts";
import { GENERATED_HEADER } from "./emit.ts";
import { q, runtimeSubpath } from "./shared.ts";

/** `blocks.<name>.ts`, next to `blocks.config.ts`. */
export function serverBlocksPath(
  config: Pick<ResolvedConfig, "output">,
  name: string,
): string {
  return posix.join(posix.dirname(config.output), `blocks.${name}.ts`);
}

/** The export of a server set: `core` is `coreBlocks`. */
export function serverBlocksName(name: string): string {
  return `${camelOf(name)}Blocks`;
}

/** The export of a server set's instance map: `coreInstances`. */
function instancesName(name: string): string {
  return `${camelOf(name)}Instances`;
}

/**
 * One `blocks.<name>.ts` per entry of `gen.serverBlocks`: a `defineBlocks` set
 * over only the instances it lists, each imported from its own subpath, so a
 * route that builds its server from the set bundles those blocks and no other.
 * Every port a listed block requires needs a listed provider, or `gen` fails
 * and names the pair.
 */
export function emitServerBlocks(
  config: Parameters<typeof emitBlockConfig>[0],
  options: {
    readonly runtimeImport?: string;
    readonly appColumns?: AppColumns;
    readonly catalog?: PresetCatalog;
  } = {},
): GeneratedFile[] {
  const sets = Object.entries(config.gen.serverBlocks ?? {});

  if (sets.length === 0 || config.blockNames.length === 0) {
    return [];
  }

  const entries = blockConfigEntries(config, undefined, options.appColumns);
  const renamed = renamedBlockLines(entries).constants;
  const runtime = options.runtimeImport ?? "better-supabase";

  const manifestOf = new Map(
    (options.catalog ?? PRESET_CATALOG).manifests.map((manifest) => [
      manifest.name,
      manifest,
    ]),
  );

  return sets.map(([name, listed]) => {
    const where = `gen.serverBlocks.${name}`;

    for (const instance of listed) {
      if (entries[instance] === undefined) {
        throw new Error(
          `${where} lists "${instance}", which \`blocks\` doesn't install.`,
        );
      }

      if (renamed.has(instance)) {
        throw new Error(
          `${where} lists "${instance}", which renames its entities. Import its block from blocks.generated.ts in your own module instead.`,
        );
      }
    }

    const manifests = listed.flatMap((instance) => {
      const manifest = manifestOf.get(entries[instance]?.block ?? instance);

      return manifest === undefined ? [] : [{ instance, manifest }];
    });

    for (const { instance, manifest } of manifests) {
      for (const [port, need] of Object.entries(manifest.consumes)) {
        const provided = manifests.some(({ manifest: other }) =>
          // SAFETY: `port` is a key of `consumes`, which is keyed by `PortName`.
          other.provides.includes(port as never),
        );

        if (need === "required" && !provided) {
          throw new Error(
            `${where} lists "${instance}", which needs a block that provides the ${port} port. List one that does.`,
          );
        }
      }
    }

    const picked = Object.fromEntries(
      Object.entries(entries).filter(([instance]) => listed.includes(instance)),
    );

    const map = instanceMapLines(picked, renamed, undefined);

    if (map.lines.length === 0) {
      throw new Error(
        `${where} lists ${listed.map((each) => `"${each}"`).join(", ")}, which have no client.`,
      );
    }

    return {
      path: serverBlocksPath(config, name),
      contents: [
        GENERATED_HEADER,
        "",
        `import { defineBlocks } from ${q(runtimeSubpath(runtime, "blocks"))};`,
        ...map.imports,
        `import { blockConfig } from "./blocks.config.ts";`,
        "",
        ...map.lines
          .slice(map.lines.indexOf("export const blocks = {"))
          .join("\n")
          .replace(
            "export const blocks = {",
            `export const ${instancesName(name)} = {`,
          )
          .split("\n"),
        "",
        "/**",
        ` * The instances in \`gen.serverBlocks.${name}\`. Build the server from them:`,
        ` * \`app.blocks(${serverBlocksName(name)})\`. A route that imports this module`,
        " * bundles these blocks and not the rest of `blocks.generated.ts`. Spread",
        ` * \`${instancesName(name)}\` into your own \`defineBlocks\` to give a block its ports.`,
        " * @public",
        " */",
        `export const ${serverBlocksName(name)} = defineBlocks(blockConfig, ${instancesName(name)});`,
        "",
      ].join("\n"),
    };
  });
}
