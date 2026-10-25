import type { GeneratedBlock } from "../../blocks/index.ts";
import type { ResolvedConfig } from "../../config/index.ts";

import { entityNames } from "../../blocks/index.ts";
import { blockEntities } from "../../config/index.ts";
import { PRESET_CATALOG } from "../../preset/index.ts";
import {
  DEFAULT_ROLES,
  modulePermissionKeys,
  resolveBlock,
} from "../../sql/index.ts";
import { applyCasing } from "./model-types.ts";
import { prop, q } from "./shared.ts";

/** The name constants of `blocks.generated.ts` and what they import. */
export interface NameConstantLines {
  /** Specifiers the module imports from `better-supabase/blocks`. */
  readonly specifiers: readonly string[];
  readonly imports: readonly string[];
  readonly lines: readonly string[];
}

type NamesConfig = Pick<
  ResolvedConfig,
  "appTables" | "blocks" | "blockNames" | "buckets" | "casing" | "subjects"
>;

const PLACEHOLDER = /\{(\.\.\.)?([A-Za-z_][\w]*)\}/g;

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function camel(name: string): string {
  return name.replaceAll(/[-_]([a-z0-9])/g, (_, c: string) => c.toUpperCase());
}

function pascal(name: string): string {
  const camelled = camel(name);

  return camelled.charAt(0).toUpperCase() + camelled.slice(1);
}

function union(values: readonly string[]): string {
  return [...new Set(values)]
    .toSorted()
    .map((value) => q(value))
    .join(" | ");
}

/**
 * A template with `{placeholders}` as an arrow function over their values: `(v:
 * { readonly userId: string }) => \`notifications:${v.userId}\``. `rename` maps
 * a placeholder to the property the caller passes.
 */
function templateFunction(
  template: string,
  rename: (name: string) => string = (name) => name,
  value = "string",
): string {
  const names: string[] = [];
  let body = "";
  let last = 0;

  for (const match of template.matchAll(PLACEHOLDER)) {
    const name = rename(match[2] ?? "");

    if (!names.includes(name)) {
      names.push(name);
    }

    body += `${literalPart(template.slice(last, match.index))}\${String(v.${name})}`;
    last = match.index + match[0].length;
  }

  body += literalPart(template.slice(last));

  if (names.length === 0) {
    return `() => ${q(template)}`;
  }

  const fields = names.map((name) => `readonly ${name}: ${value}`).join("; ");

  return `(v: { ${fields} }) => \`${body}\``;
}

function literalPart(text: string): string {
  return text.replaceAll(/[`\\]|\$\{/g, (match) => `\\${match}`);
}

/** Permission keys by owner (block, subject or app table), then action. */
function permissionGroups(
  config: NamesConfig,
): Readonly<Record<string, Readonly<Record<string, string>>>> {
  const groups: Record<string, Record<string, string>> = {};

  for (const entry of modulePermissionKeys(config.blocks, config.blockNames)) {
    groups[entry.module] = {
      ...groups[entry.module],
      [entry.action]: entry.key,
    };
  }

  for (const [name, subject] of Object.entries(config.subjects)) {
    if (subject.permissions) {
      groups[name] = {
        ...groups[name],
        ...Object.fromEntries(
          Object.entries(subject.permissions).flatMap(([action, value]) => {
            const key = typeof value === "string" ? value : value.key;

            return key === undefined ? [] : [[action, key]];
          }),
        ),
      };
    }
  }

  for (const table of Object.values(config.appTables)) {
    const subject = table.subject;

    if (subject?.permissions) {
      groups[subject.type] = {
        ...groups[subject.type],
        ...subject.permissions,
      };
    }
  }

  return groups;
}

/** Whether `blocks.generated.ts` exports `permissions`. */
export function hasPermissionConstants(config: NamesConfig): boolean {
  return Object.values(permissionGroups(config)).some(
    (group) => Object.keys(group).length > 0,
  );
}

function permissionLines(config: NamesConfig): string[] {
  const groups = permissionGroups(config);
  const keys = Object.values(groups).flatMap((group) => Object.values(group));

  if (keys.length === 0) {
    return [];
  }

  return [
    "",
    "/**",
    " * The permission keys the installed blocks, subjects and app tables check,",
    " * by owner and action.",
    " * @public",
    " */",
    "export const permissions = {",
    ...Object.entries(groups)
      .toSorted(([a], [b]) => a.localeCompare(b))
      .flatMap(([owner, actions]) => [
        `  ${prop(owner)}: {`,
        ...Object.entries(actions).map(
          ([action, key]) => `    ${prop(action)}: ${q(key)},`,
        ),
        "  },",
      ]),
    "} as const;",
    "",
    "/**",
    " * Every permission key, for `defineAuthorizer<PermissionKey>()` and",
    " * the `permission` of actions and routes.",
    " * @public",
    " */",
    `export type PermissionKey = ${union(keys)};`,
  ];
}

function roleLines(
  config: NamesConfig,
  entries: Readonly<Record<string, GeneratedBlock>>,
): string[] {
  if (entries["permissions"] === undefined) {
    return [];
  }

  const access = config.blocks.permissions;
  const settings = typeof access === "object" ? access : undefined;

  if ((settings?.model ?? "roles") !== "roles") {
    return [];
  }

  const roles = settings?.roles ?? DEFAULT_ROLES;

  return [
    "",
    "/** The roles `blocks.permissions.roles` defines. @public */",
    `export type RoleName = ${union(Object.keys(roles))};`,
  ];
}

interface BlockEventList {
  readonly specifier: string;
  readonly type: string;
  readonly types: readonly string[];
}

function blockEventLists(
  entries: Readonly<Record<string, GeneratedBlock>>,
): BlockEventList[] {
  return PRESET_CATALOG.manifests.flatMap((manifest) => {
    const events = manifest.events;
    const client = manifest.client;

    if (events === undefined || !client) {
      return [];
    }

    const lists = Object.entries(entries)
      .filter(([key, entry]) => (entry.block ?? key) === manifest.name)
      .map(([key, entry]): BlockEventList => {
        const renames = entry.names?.entities ?? [];
        const names = entityNames(renames);

        // With renames, blocks.generated.ts declares the renamed events type,
        // under the instance's name for a renamed instance.
        const type =
          renames.length === 0
            ? events.type
            : key === manifest.name
              ? names.rename(events.type)
              : `${pascalOf(key)}Events`;

        return {
          specifier:
            renames.length === 0
              ? `import type { ${events.type} } from ${q(client.subpath)};`
              : "",
          type,
          types: events.types.map((each) => names.rename(each)),
        };
      });

    return lists.filter(
      (list, index) =>
        lists.findIndex((other) => other.type === list.type) === index,
    );
  });
}

function pascalOf(instance: string): string {
  const camel = instance.replaceAll(/-([a-z0-9])/g, (_, c: string) =>
    c.toUpperCase(),
  );

  return camel.charAt(0).toUpperCase() + camel.slice(1);
}

function eventLines(
  entries: Readonly<Record<string, GeneratedBlock>>,
): NameConstantLines {
  const lists = blockEventLists(entries);

  if (lists.length === 0) {
    return { specifiers: [], imports: [], lines: [] };
  }

  // Blocks share some events, such as `organization.member_added`.
  const types = [...new Set(lists.flatMap((list) => list.types))].toSorted();

  return {
    specifiers: ["type Events"],
    imports: lists.flatMap((list) =>
      list.specifier === "" ? [] : [list.specifier],
    ),
    lines: [
      "",
      "/** Every installed block's events: type to data. @public */",
      `export type BlockEvents = ${lists.map((list) => list.type).join(" & ")};`,
      "",
      "/**",
      " * The installed blocks' event types under the configured names, for",
      " * `onBlockEvent` and the sinks.",
      " * @public",
      " */",
      "export const blockEvents: Events<BlockEvents> = {",
      "  types: [",
      ...types.map((type) => `    ${q(type)},`),
      "  ],",
      "};",
      "",
      "/**",
      " * The block events with an open payload, for AsyncAPI's `cloudEvents.blocks`.",
      " * @public",
      " */",
      "export const blockEventSchemas = {",
      ...types.map((type) => `  ${q(type)}: true,`),
      "} as const;",
    ],
  };
}

function urlLines(
  config: NamesConfig,
  entries: Readonly<Record<string, GeneratedBlock>>,
): string[] {
  const templates = new Map<string, string>();

  for (const name of Object.keys(entries)) {
    for (const entity of blockEntities(name, config.blocks)) {
      if (entity.url !== undefined) {
        templates.set(camel(entity.to.singular), entity.url);
      }
    }
  }

  // `config.records` holds the app's types, the app tables' and the blocks'.
  for (const [type, subject] of Object.entries(config.subjects)) {
    const key = camel(type);

    if (subject.url !== undefined && !templates.has(key)) {
      templates.set(key, subject.url);
    }
  }

  const urls = [...templates].map(
    ([key, template]) =>
      `  ${prop(key)}: ${templateFunction(
        template,
        (column) => applyCasing(column, config.casing),
        "string | number",
      )},`,
  );

  return urls.length === 0
    ? []
    : [
        "",
        "/**",
        " * The path of each subject type with a `url`: block entities, `records`",
        " * and `tables` subjects.",
        " * @public",
        " */",
        "export const urls = {",
        ...urls,
        "} as const;",
      ];
}

function topicLines(
  entries: Readonly<Record<string, GeneratedBlock>>,
): string[] {
  const topics = Object.entries(entries).flatMap(([name, entry]) =>
    Object.entries(entry.options).flatMap(([option, value]) => {
      if (
        !/^(?:topic|[a-z]+Topic)$/.test(option) ||
        typeof value !== "string"
      ) {
        return [];
      }

      const key =
        option === "topic"
          ? camel(name)
          : `${camel(name)}${pascal(option.replace(/Topic$/, ""))}`;

      return [`  ${prop(key)}: ${templateFunction(value)},`];
    }),
  );

  return topics.length === 0
    ? []
    : [
        "",
        "/** The realtime topics the blocks broadcast on, with their placeholders filled. @public */",
        "export const topics = {",
        ...topics,
        "} as const;",
      ];
}

function pathLines(config: NamesConfig): string[] {
  const paths = Object.entries(config.buckets).map(([name, bucket]) => {
    const key = prop(camel(name));

    return typeof bucket.path === "string"
      ? `  ${key}: ${templateFunction(bucket.path)},`
      : `  ${key}: [${bucket.path.map((path) => templateFunction(path)).join(", ")}],`;
  });

  return paths.length === 0
    ? []
    : [
        "",
        "/** Object paths in each bucket, from `buckets.<name>.path`. @public */",
        "export const paths = {",
        ...paths,
        "} as const;",
      ];
}

function optionOf(
  config: NamesConfig,
  module: string,
  option: string,
): unknown {
  return config.blockNames.includes(module) ||
    config.blocks[module] !== undefined
    ? resolveBlock(config.blocks[module]).options[option]
    : undefined;
}

function settingKeys(config: NamesConfig): string[] {
  const option = optionOf(config, "settings", "schemas");

  const schemas =
    isRecord(option) && isRecord(option["schemas"])
      ? option["schemas"]
      : option;

  if (!isRecord(schemas)) {
    return [];
  }

  return ["user", "organization", "platform"].flatMap((scope) => {
    const keys = schemas[scope];

    return isRecord(keys) ? Object.keys(keys) : [];
  });
}

function meterNames(config: NamesConfig): string[] {
  const option = optionOf(config, "usage", "meters");

  return isRecord(option) && typeof option["table"] !== "string"
    ? Object.keys(option)
    : [];
}

function keyUnionLines(config: NamesConfig): string[] {
  const unions: [string, string, readonly string[]][] = [
    ["SettingKey", "`blocks.settings.options.schemas`", settingKeys(config)],
    ["MeterName", "`blocks.usage.options.meters`", meterNames(config)],
  ];

  return unions.flatMap(([name, source, keys]) =>
    keys.length === 0
      ? []
      : [
          "",
          `/** The keys ${source} names. @public */`,
          `export type ${name} = ${union(keys)};`,
        ],
  );
}

/**
 * The constants app code references by name, from the config: permission keys,
 * role names, block events, entity URLs, realtime topics, bucket paths, and the
 * settings and meter keys.
 */
export function nameConstantLines(
  config: NamesConfig,
  entries: Readonly<Record<string, GeneratedBlock>>,
): NameConstantLines {
  const events = eventLines(entries);

  return {
    specifiers: events.specifiers,
    imports: events.imports,
    lines: [
      ...permissionLines(config),
      ...roleLines(config, entries),
      ...events.lines,
      ...urlLines(config, entries),
      ...topicLines(entries),
      ...pathLines(config),
      ...keyUnionLines(config),
    ],
  };
}
