import { rm, writeFile } from "node:fs/promises";
import { basename, dirname, extname, join } from "node:path";

import type { ResolvedConfig } from "../config/index.ts";
import type { Codemod, CodemodProject } from "./codemod.ts";
import type { ImportFollow } from "./config-document/index.ts";
import type { PlannedFile } from "./core/files.ts";
import type { ProjectSymbols } from "./typescript-symbols/index.ts";

import { restatedEntries, suggestSqlApi } from "../config/index.ts";
import { clientNotNull, redundantNulls, SQL_MODULES } from "../sql/index.ts";
import { settleGroups, withoutConfigPaths } from "./codemod-prune.ts";
import {
  changedFiles,
  ConfigDocument,
  followedReview,
  openImports,
  ownerOf,
} from "./config-document/index.ts";
import { getConfig } from "./config.ts";
import { mergeRestated, probeRestated } from "./restated-probe.ts";
import { ownLayout } from "./sql-layout.ts";
import { layoutFor } from "./sql/providers.ts";
import { renderBlocksCached } from "./sql/render-cache.ts";

/**
 * The config options the `config` codemod never edits (ADR 0324): each states a
 * choice the schema can't imply, such as a remap, a reserved slug, a bound or
 * an exemption. The codemod only removes `columns` entries, so a test keeps
 * this list in step with what it leaves alone, in both config shapes.
 */
export const PROTECTED_OPTIONS: readonly string[] = [
  "names",
  "functions",
  "permissions",
  "reservedSlugs",
  "slugPattern",
  "slugMinLength",
  "slugMaxLength",
  "onAccept",
  "previewColumns",
  "roles",
  "restricted",
  "ipHeader",
  "staffClaim",
  "subjectColumns",
  "exempt",
  "attachments",
  "api",
  "ownTablePolicies",
  "tenantColumn",
  "powersync",
  "sources",
];

/** A `blocks.<block>.columns.<table>.<column>` entry the render refuses. */
export interface ColumnEntry {
  readonly block: string;
  readonly table: string;
  readonly column: string;
  readonly why: string;
}

/** The `columns.<table>.tenant` entries that repeat `sql.tenantColumn`. */
export function tenantEntries(
  config: Pick<ResolvedConfig, "blocks" | "sql">,
): ColumnEntry[] {
  const tenant = config.sql.tenantColumn;

  if (tenant === undefined) {
    return [];
  }

  return Object.entries(config.blocks).flatMap(([block, entry]) =>
    Object.entries(entry?.columns ?? {}).flatMap(([table, columns]) =>
      columns?.["tenant"] === tenant
        ? [
            {
              block,
              table,
              column: "tenant",
              why: `repeats sql.tenantColumn "${tenant}"`,
            },
          ]
        : [],
    ),
  );
}

/** The text without the entries, and a line for each the file builds elsewhere. */
export interface ColumnEntryEdit {
  readonly text: string;
  readonly review: readonly string[];
  /** Files that declare a value the config imports, with their edited text. */
  readonly others: readonly { readonly file: string; readonly text: string }[];
}

/**
 * `text` without the `<column>` entry of each `blocks.<block>.columns.<table>`
 * entry, with its comma, its line and its comments. A name in a string or a
 * comment stays. An entry the document cannot find or follow (it comes from an
 * import, a call or a computed key) stays in the file with a review line.
 */
export function withoutColumnEntries(
  text: string,
  entries: readonly ColumnEntry[],
  follow?: ImportFollow,
): ColumnEntryEdit {
  const document = ConfigDocument.parse(text);
  const review: string[] = [];

  const imports = openImports(follow, document);

  for (const entry of entries) {
    const path = ["blocks", entry.block, "columns", entry.table, entry.column];
    const result = document.remove(path);

    if (result.status !== "absent") {
      continue;
    }

    const found = ownerOf(imports, path);

    if (found?.owner.document.remove(found.inner).status === "done") {
      continue;
    }

    review.push(
      `${path.join(".")}: ${entry.why}, but the codemod could not find it in the config file${
        imports === undefined ? " (it may come from another file)" : ""
      }; remove it by hand.`,
    );
  }

  return {
    text: document.text,
    review: [...review, ...document.review, ...followedReview(imports)],
    others: changedFiles(imports),
  };
}

/** The files that drop the config entries the render refuses. */
export function configFiles(
  entries: readonly ColumnEntry[],
  config: { readonly path: string; readonly text: string },
  symbols?: ProjectSymbols,
): {
  readonly files: readonly PlannedFile[];
  readonly review: readonly { readonly message: string }[];
} {
  const edit = withoutColumnEntries(config.text, entries, {
    symbols,
    configFile: config.path,
  });

  const review = edit.review.map((message) => ({ message }));

  const files: PlannedFile[] = [
    ...(edit.text === config.text
      ? []
      : [{ path: config.path, contents: edit.text, policy: "edit" as const }]),
    ...edit.others.map(({ file, text }) => ({
      path: file,
      contents: text,
      policy: "edit" as const,
    })),
  ];

  return { files, review };
}

/** The rendered files of `config`, by path. */
async function renderedFiles(
  config: ResolvedConfig,
): Promise<ReadonlyMap<string, string>> {
  const layout = await layoutFor(config, {}, config.blockNames);

  const files = await renderBlocksCached(config, config.blockNames, layout, {
    cache: false,
  });

  return new Map(files.map((file) => [file.path, file.contents]));
}

/** The first path whose text differs between two renders. */
function firstDifference(
  before: ReadonlyMap<string, string>,
  after: ReadonlyMap<string, string>,
): string | undefined {
  for (const path of new Set([...before.keys(), ...after.keys()])) {
    if (before.get(path) !== after.get(path)) {
      return path;
    }
  }

  return undefined;
}

/**
 * `sql.api` for a project that has none when most blocks name the same schema:
 * the new default goes in, the matching `api` entries go out, and each block
 * with no entry gets `api: false`, since it would write wrappers otherwise. The
 * edit is kept only when the render stays the same.
 */
async function withSqlApi(
  project: CodemodProject,
  before: ReadonlyMap<string, string>,
): Promise<{ text: string; review: readonly string[] }> {
  const { config, configFile, configText } = project;

  if (configFile === undefined || configText === undefined) {
    return { text: configText ?? "", review: [] };
  }

  const found = suggestSqlApi(config.blockApis, config.sql.blockDefaults?.api);

  if (found === undefined) {
    return { text: configText, review: [] };
  }

  const document = ConfigDocument.parse(configText);

  const edits = [
    document.ensure(["database", "sql", "api"], JSON.stringify(found.schema)),
    ...found.drop.map((name) => document.remove(["blocks", name, "api"])),
    ...found.disable.map((name) =>
      document.ensure(["blocks", name, "api"], "false"),
    ),
  ];

  const where = `${configFile}: database.sql.api "${found.schema}" covers the api entries of ${found.drop.join(", ")}`;

  if (
    edits.some((edit) => edit.status !== "done") ||
    document.review.length > 0
  ) {
    return {
      text: configText,
      review: [
        `${where}, but the codemod could not edit every block in place; set it by hand.`,
        ...document.review,
      ],
    };
  }

  const copy = join(
    dirname(configFile),
    `.${basename(configFile, extname(configFile))}.api-${String(process.pid)}${extname(configFile)}`,
  );

  try {
    await writeFile(copy, document.text);

    const after = await getConfig(dirname(configFile), copy);

    if (firstDifference(before, await renderedFiles(after)) === undefined) {
      return { text: document.text, review: [] };
    }
  } catch {
    // A config that no longer renders counts as a difference.
  } finally {
    await rm(copy, { force: true });
  }

  return {
    text: configText,
    review: [
      `${where}, but setting it changes the render, so the entries stay.`,
    ],
  };
}

/**
 * `config --prune`: removes every entry `restatedEntries` reports, then renders
 * with the old and the new config and refuses to write when a file differs.
 */
async function prune(
  project: CodemodProject,
): Promise<{
  files: readonly PlannedFile[];
  review: readonly { message: string }[];
}> {
  const { config, configFile, configText } = project;

  const provider =
    config.authorization && config.blocks.permissions?.model === "provider"
      ? config.authorization
      : undefined;

  const probed = await probeRestated(config).catch(() => []);

  const entries = mergeRestated(
    restatedEntries({
      blocks: config.blocks,
      sqlTenantColumn: config.sql.tenantColumn,
      subjects: config.subjects,
      restatedDefaults: config.restatedDefaults,
      genFunctions: config.functions,
      blockNotNull: (name) =>
        Object.entries(config.blocks).flatMap(([key, entry]) => {
          const declared = clientNotNull(entry?.block ?? key, name);

          return declared === undefined ? [] : [declared];
        })[0],
      provider,
      defaultColumns: (module) => SQL_MODULES[module]?.names?.tables,
      nulls: redundantNulls({
        modules: config.blocks,
        ...(await ownLayout(config).catch(() => undefined)),
      }),
    }),
    probed,
  );

  if (configFile === undefined || configText === undefined) {
    return {
      files: [],
      review: entries.map((entry) => ({
        message: `${entry.path} ${entry.reason}; remove it from the config.`,
      })),
    };
  }

  const before = await renderedFiles(config);

  const api = await withSqlApi(project, before);
  const baseText = api.text;
  const allPaths = entries.map((entry) => entry.path);
  const follow: ImportFollow = { symbols: project.symbols, configFile };
  const first = withoutConfigPaths(baseText, allPaths, follow);

  const review: { message: string }[] = first.missed
    .filter(
      (path) => entries.find((entry) => entry.path === path)?.kind !== "empty",
    )
    .map((path) => ({
      message: `${path} repeats its default, but the codemod could not find it in ${configFile}; remove it by hand.`,
    }));

  review.push(
    ...[...api.review, ...first.review].map((message) => ({ message })),
  );

  if (
    first.text === baseText &&
    baseText === configText &&
    first.others.length === 0
  ) {
    return { files: [], review };
  }

  const copy = join(
    dirname(configFile),
    `.${basename(configFile, extname(configFile))}.prune-${String(process.pid)}${extname(configFile)}`,
  );

  // Whether the config without these paths renders the same files. A config that no longer
  // renders at all counts as a difference, because an option may need the entry it restates.
  const renderUnchanged = async (
    paths: readonly string[],
  ): Promise<boolean> => {
    try {
      await writeFile(copy, withoutConfigPaths(baseText, paths).text);

      const after = await getConfig(dirname(configFile), copy);

      return firstDifference(before, await renderedFiles(after)) === undefined;
    } catch {
      return false;
    }
  };

  const groups = new Map<string, string[]>();

  for (const path of allPaths) {
    const key = path.split(".").slice(0, 2).join(".");
    groups.set(key, [...(groups.get(key) ?? []), path]);
  }

  let settled: Awaited<ReturnType<typeof settleGroups>>;

  try {
    settled = await settleGroups([...groups], renderUnchanged);
  } finally {
    await rm(copy, { force: true });
  }

  const { kept, refused } = settled;

  for (const key of refused) {
    review.push({
      message: `Pruning the entries of ${key} changes the render or leaves a config that does not render, so they stay: ${(groups.get(key) ?? []).join(", ")}.`,
    });
  }

  const pruned = withoutConfigPaths(baseText, kept, follow);

  for (const other of pruned.others) {
    review.push({
      message: `${other.file}: removed entries the config imports from here. The render check only covers ${configFile}, so run \`better-supabase gen --check\` to confirm this file.`,
    });
  }

  const files: PlannedFile[] = [
    ...(pruned.text === configText
      ? []
      : [{ path: configFile, contents: pruned.text, policy: "edit" as const }]),
    ...pruned.others.map(({ file, text }) => ({
      path: file,
      contents: text,
      policy: "edit" as const,
    })),
  ];

  return { files, review };
}

/** The `config` codemod: drop the entries the catalog already implies. */
export function configCodemod(): Codemod {
  return {
    name: "config",
    description:
      "Remove the columns entries the render refuses: a null for a column the view lacks and a tenant that repeats sql.tenantColumn",
    project: async (project: CodemodProject) => {
      if (project.prune === true) {
        return prune(project);
      }

      const { config } = project;

      let own: Awaited<ReturnType<typeof ownLayout>> | undefined;

      try {
        own = await ownLayout(config);
      } catch {
        // Without the project's tables only the static entries are found.
      }

      const nulls: ColumnEntry[] = [];

      for (const entry of redundantNulls({ modules: config.blocks, ...own })) {
        nulls.push({
          block: entry.block,
          table: entry.logical,
          column: entry.column,
          why: `${entry.view} has no "${entry.name}" column`,
        });
      }

      const entries = [...tenantEntries(config), ...nulls];

      if (project.configFile === undefined || entries.length === 0) {
        return {
          files: [],
          review: entries.map((entry) => ({
            message: `blocks.${entry.block}.columns.${entry.table}.${entry.column}: ${entry.why}; remove it from the config.`,
          })),
        };
      }

      return configFiles(
        entries,
        { path: project.configFile, text: project.configText ?? "" },
        project.symbols,
      );
    },
  };
}
