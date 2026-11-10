import { posix } from "node:path";

import type { GeneratedBlock } from "../../blocks/index.ts";
import type { ResolvedConfig } from "../../config/index.ts";

import { entityNames } from "../../blocks/index.ts";
import { PRESET_CATALOG } from "../../preset/index.ts";
import { q } from "./shared.ts";

export interface RenamedLines {
  /** Specifiers the module imports from `better-supabase/blocks`. */
  readonly specifiers: readonly string[];
  readonly imports: readonly string[];
  readonly lines: readonly string[];
  /** The constant each renamed instance's block is exported under. */
  readonly constants: ReadonlyMap<string, string>;
  /**
   * What one renamed instance writes, for its own module (`gen.blockModules`):
   * the import of its block, the specifiers it takes from the blocks runtime
   * and its lines.
   */
  readonly byInstance: ReadonlyMap<
    string,
    {
      readonly import: string;
      /** The lines inside the import, one specifier each, and its subpath. */
      readonly importSpecifiers: readonly string[];
      readonly subpath: string;
      readonly specifiers: readonly string[];
      readonly lines: readonly string[];
    }
  >;
}

/**
 * For each installed block whose entities `blocks.<name>.entities` renames: the
 * block under its renamed constant (`tasksBlock`) and an alias for each type
 * named after one of its entities (`Task<F>`, `TasksEvents`).
 */
export function renamedBlockLines(
  entries: Readonly<Record<string, GeneratedBlock>>,
): RenamedLines {
  const imports: string[] = [];
  const lines: string[] = [];
  const exported = new Set<string>();
  const constants = new Map<string, string>();

  const byInstance = new Map<
    string,
    {
      import: string;
      importSpecifiers: readonly string[];
      subpath: string;
      specifiers: readonly string[];
      lines: readonly string[];
    }
  >();

  let eventRenames = false;

  for (const manifest of PRESET_CATALOG.manifests) {
    const instances = Object.entries(entries).filter(
      ([key, entry]) =>
        (entry.block ?? key) === manifest.name &&
        (entry.names?.entities ?? []).length > 0,
    );

    if (manifest.client === null || instances.length === 0) {
      continue;
    }

    // A block renamed by more than one instance is imported once, under
    // `default*` names, so no instance's renamed name clashes with an import.
    const aliasAll = instances.length > 1;
    const block = manifest.client.export;

    const entityTypes = (manifest.entityTypes ?? []).filter(
      (type) =>
        !(
          type.name.endsWith("Options") &&
          manifest.entityTypes?.some(
            (other) => `${other.name}Options` === type.name,
          )
        ),
    );

    // A block-named events type (`TasksEvents`) carries no entity noun, but
    // its event types do, so it gets a renamed alias under the same name.
    const eventsType = manifest.events?.type;

    const types =
      eventsType === undefined ||
      entityTypes.some((type) => type.name === eventsType)
        ? entityTypes
        : [...entityTypes, { name: eventsType }];

    const [first] = instances;
    const firstNames = entityNames(first?.[1].names?.entities ?? []);

    const localOf = (name: string): string =>
      aliasAll || firstNames.rename(name) === name ? `Default${name}` : name;

    const local =
      aliasAll || firstNames.rename(block) === block
        ? `default${pascal(block)}`
        : block;

    const specifiers = [
      ...types.map((type) =>
        localOf(type.name) === type.name
          ? `  type ${type.name},`
          : `  type ${type.name} as ${localOf(type.name)},`,
      ),
      `  ${local === block ? block : `${block} as ${local}`},`,
    ];

    const manifestImport = [
      "import {",
      ...specifiers,
      `} from ${q(manifest.client.subpath)};`,
    ].join("\n");

    imports.push(manifestImport);

    for (const [instance, entry] of instances) {
      const names = entityNames(entry.names?.entities ?? []);
      const alias = `${pascal(camelOf(instance))}Renames`;
      const key = q(instance);

      const wanted =
        instance === manifest.name
          ? names.rename(block)
          : `${camelOf(instance)}Block`;

      const renamed = exported.has(wanted)
        ? `${camelOf(instance)}Block`
        : wanted;

      exported.add(renamed);
      constants.set(instance, renamed);

      const eventAlias =
        (entry.names?.events?.length ?? 0) === 0 ? alias : `${alias}Events`;

      eventRenames ||= eventAlias !== alias;

      const instanceLines = [
        "",
        `type ${alias} = (typeof blockConfig)[${key}]["names"]["entities"];`,
        ...(eventAlias === alias
          ? []
          : [
              `type ${eventAlias} = EventRenamesOf<(typeof blockConfig)[${key}]["names"]>;`,
            ]),
        "",
        "/**",
        ` * The \`${manifest.name}\` block under the names \`blocks.${instance}.entities\` gives it.`,
        " * @public",
        " */",
        `export const ${renamed} = renameBlock(${local}, blockConfig[${key}].names);`,
        ...renamedTypeLines(
          types,
          names,
          localOf,
          alias,
          eventAlias,
          exported,
          {
            block: eventsType,
            instance:
              instance === manifest.name
                ? undefined
                : `${pascal(camelOf(instance))}Events`,
          },
        ),
      ];

      lines.push(...instanceLines);

      byInstance.set(instance, {
        import: manifestImport,
        importSpecifiers: specifiers,
        subpath: manifest.client.subpath,
        specifiers: [
          "renameBlock",
          ...(eventAlias === alias ? [] : ["type EventRenamesOf"]),
          "type RenamedEvents",
          "type RenamedType",
        ],
        lines: instanceLines,
      });
    }
  }

  return {
    specifiers:
      imports.length === 0
        ? []
        : [
            "renameBlock",
            ...(eventRenames ? ["type EventRenamesOf"] : []),
            "type RenamedEvents",
            "type RenamedType",
          ],
    imports,
    lines,
    constants,
    byInstance,
  };
}

/**
 * An alias for each of `types` under the name an instance's entity renames give
 * it, skipping a name another instance already exports. A renamed instance's
 * block-named events type takes the instance's name (`MaintenanceEvents`).
 */
function renamedTypeLines(
  types: readonly { readonly name: string; readonly fields?: boolean }[],
  names: ReturnType<typeof entityNames>,
  localOf: (name: string) => string,
  alias: string,
  eventAlias: string,
  exported: Set<string>,
  events: {
    readonly block: string | undefined;
    readonly instance: string | undefined;
  },
): string[] {
  return types.flatMap((type) => {
    const name =
      type.name === events.block && events.instance !== undefined
        ? events.instance
        : names.rename(type.name);

    const source = localOf(type.name);

    if (exported.has(name)) {
      return [];
    }

    exported.add(name);

    if (type.name.endsWith("Events")) {
      return [
        "",
        "/** @public */",
        `export type ${name} = RenamedEvents<${source}, ${eventAlias}>;`,
      ];
    }

    return type.fields === true
      ? [
          "",
          "/** @public */",
          `export type ${name}<F extends object = Record<never, never>> = RenamedType<${source}<F>, ${alias}>;`,
        ]
      : [
          "",
          "/** @public */",
          `export type ${name} = RenamedType<${source}, ${alias}>;`,
        ];
  });
}

/**
 * `blocks/<instance>-block.ts` (`gen.blockModules`): one renamed instance's
 * block and its renamed types, so a record imports its own block and no other.
 */
export function renamedBlockPath(
  config: Pick<ResolvedConfig, "output">,
  instance: string,
): string {
  return posix.join(
    posix.dirname(config.output),
    "blocks",
    `${instance}-block.ts`,
  );
}

/**
 * The import of a renamed instance's block without the `Default*` names its
 * lines never use: with several instances of one block each module imports only
 * what its own renames reach.
 */
export function usedImport(chunk: {
  readonly importSpecifiers: readonly string[];
  readonly subpath: string;
  readonly lines: readonly string[];
}): string {
  const body = chunk.lines.join("\n");

  const kept = chunk.importSpecifiers.filter((line) => {
    const local = /(?:as\s+)?(\w+),?\s*$/.exec(line)?.[1];

    return local !== undefined && new RegExp(`\\b${local}\\b`).test(body);
  });

  return ["import {", ...kept, `} from ${q(chunk.subpath)};`].join("\n");
}

/** The names a renamed instance's module exports. */
export function exportedNames(lines: readonly string[]): readonly string[] {
  return lines
    .join("\n")
    .split("\n")
    .flatMap((line) => {
      const name = /^export (?:declare )?(?:type|const|interface) (\w+)/.exec(
        line,
      )?.[1];

      return name === undefined ? [] : [name];
    });
}

export function camelOf(name: string): string {
  return name.replaceAll(/-([a-z0-9])/g, (_, c: string) => c.toUpperCase());
}

function pascal(name: string): string {
  return name.charAt(0).toUpperCase() + name.slice(1);
}
