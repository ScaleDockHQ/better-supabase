import type { BlockSqlLayout } from "../sql/index.ts";
import type { CodemodProject } from "./codemod.ts";
import type { PlannedFile } from "./core/files.ts";

import {
  renderBlocks,
  sameTenantLayout,
  sameTenantTagsOf,
  sameTenantTrigger,
} from "../sql/index.ts";
import { withoutConfigPaths } from "./codemod-prune.ts";
import { declarationsOfText } from "./sql-facts.ts";
import { layoutFor } from "./sql/providers.ts";

const isRecord = (item: unknown): item is Record<string, unknown> =>
  typeof item === "object" && item !== null && !Array.isArray(item);

const SAME_TENANT = "blocks.memberships.options.sameTenant";

const WORD = /^[\w.=-]+$/u;

const value = (text: string): string =>
  WORD.test(text) ? text : `"${text.replaceAll('"', String.raw`\"`)}"`;

const quoted = (name: string): string => name.replaceAll('"', '""');

/**
 * The trigger statements of the memberships module, by the table and trigger
 * they create. Moving an entry into a tag is made only when the statement of
 * its column is the same string afterwards.
 */
function statementsOf(
  names: readonly string[],
  layout: BlockSqlLayout,
): ReadonlyMap<string, string> {
  const contents = renderBlocks(names, layout)
    .map((file) => file.contents)
    .join("\n");

  const found = new Map<string, string>();

  for (const match of contents.matchAll(
    /create (?:constraint )?trigger ("bsb_same_tenant_\w+") [^;\n]*? on ("[^"]+"\."[^"]+")\n[^;]*;/gu,
  )) {
    found.set(`${match[2] ?? ""}.${match[1] ?? ""}`, match[0]);
  }

  return found;
}

/** `text` with `@bsb same-tenant` tags on `table.column`'s comment. */
export function withColumnTag(
  text: string,
  table: string,
  column: string,
  line: string,
): string {
  const [schema = "public", name = ""] = table.split(".");
  const escaped = line.replaceAll("'", "''");

  const comment = new RegExp(
    String.raw`(comment\s+on\s+column\s+(?:"?${schema}"?\s*\.\s*)?"?${name}"?\s*\.\s*"?${column}"?\s+is\s+')((?:[^']|'')*)(')`,
    "i",
  );

  if (comment.test(text)) {
    return text.replace(
      comment,
      (_all, head: string, body: string, tail: string) =>
        /(^|\s)@bsb(?:\s|$)/u.test(body)
          ? `${head}${body.trimEnd().replace(/;$/u, "")}; ${escaped.replace(/^@bsb\s+/u, "")}${tail}`
          : `${head}${body === "" ? "" : `${body}\n`}${escaped}${tail}`,
    );
  }

  return `${text.replace(/\n*$/u, "\n")}\ncomment on column "${quoted(schema)}"."${quoted(name)}"."${quoted(column)}" is '${escaped}';\n`;
}

interface Entry {
  readonly path: string;
  readonly index: number;
  readonly value: Record<string, unknown>;
}

/** The `sameTenant` entries of the config, with the path each one has. */
function entriesOf(config: CodemodProject["config"]): readonly Entry[] {
  const option: unknown = config.blocks["memberships"]?.options?.["sameTenant"];

  const list: { path: string; items: unknown[] } | undefined = Array.isArray(
    option,
  )
    ? { path: SAME_TENANT, items: option }
    : isRecord(option) && Array.isArray(option["entries"])
      ? { path: `${SAME_TENANT}.entries`, items: option["entries"] }
      : undefined;

  return (list?.items ?? []).flatMap((item, index) =>
    isRecord(item) ? [{ path: list?.path ?? "", index, value: item }] : [],
  );
}

/** Replaces the entry list of the memberships `sameTenant` option. */
function withEntries(
  layout: BlockSqlLayout,
  keep: (entry: Record<string, unknown>) => boolean,
): BlockSqlLayout {
  const block = layout.modules?.["memberships"];
  const option: unknown = block?.options?.["sameTenant"];

  const next = Array.isArray(option)
    ? option.filter((each: unknown) => !isRecord(each) || keep(each))
    : isRecord(option) && Array.isArray(option["entries"])
      ? {
          ...option,
          entries: option["entries"].filter(
            (each: unknown) => !isRecord(each) || keep(each),
          ),
        }
      : option;

  return {
    ...layout,
    modules: {
      ...layout.modules,
      memberships: {
        ...block,
        options: { ...block?.options, sameTenant: next },
      },
    },
  };
}

/**
 * The tag that says what `entry` says beyond its foreign key. The proof, not
 * the builder, decides whether it is enough.
 */
function tagFor(
  entry: Record<string, unknown>,
  companions: ReadonlySet<string>,
): string | undefined {
  const references = isRecord(entry["references"])
    ? entry["references"]
    : undefined;

  const parts: string[] = [];

  const text = (name: string, found: unknown): void => {
    if (typeof found === "string") {
      parts.push(`${name}=${value(found)}`);
    }
  };

  text("where", references?.["where"]);
  text("tenant", entry["tenant"]);
  text("parent-tenant", references?.["tenant"]);

  const shared = entry["shared"] ?? references?.["shared"];

  if (typeof shared === "boolean") {
    parts.push(`shared=${String(shared)}`);
  }

  if (isRecord(entry["match"])) {
    const pairs = Object.entries(entry["match"]).filter(
      ([own, other]) =>
        typeof other === "string" && !companions.has(`${own}=${other}`),
    );

    if (pairs.length > 0) {
      parts.push(
        `match=${value(pairs.map(([own, other]) => `${own}=${String(other)}`).join(","))}`,
      );
    }
  }

  if (isRecord(entry["through"])) {
    const hops = Object.entries(entry["through"]);

    // A hop with its own key column does not fit the one-line tag.
    if (hops.some(([, hop]) => typeof hop !== "string")) {
      return undefined;
    }

    parts.push(
      `through=${value(hops.map(([via, hop]) => `${via}=${String(hop)}`).join(","))}`,
    );
  }

  return `@bsb same-tenant${parts.length === 0 ? "" : ` ${parts.join(" ")}`}`;
}

/** What the codemod moved and what it left, with the files it changed. */
export interface SameTenantMoves {
  readonly files: readonly PlannedFile[];
  readonly review: readonly { readonly message: string }[];
  readonly moved: number;
}

const statementKey = (table: string, column: string): string =>
  `${table
    .split(".")
    .map((part) => `"${quoted(part)}"`)
    .join(".")}."${sameTenantTrigger(column)}"`;

/**
 * Moves each `sameTenant` entry of the config into a `@bsb same-tenant` tag on
 * its column when the tag renders the same trigger statement. `base` is the
 * layout of the project as it renders now; the schema files are read from
 * `project.sql`, and the entries that moved leave `project.configText`. An
 * entry the tag cannot say, or whose statement would change, stays with a line
 * that names the reason.
 */
export function sameTenantMoves(
  project: CodemodProject,
  base: BlockSqlLayout,
): SameTenantMoves {
  const schemas = project.config.schemas;
  const names = ["memberships"];
  const review: { message: string }[] = [];
  const entries = entriesOf(project.config);

  const original = new Map(
    project.sql
      .filter((file) => !/[\\/]migrations[\\/]/u.test(file.path))
      .map((file) => [file.path, file.text] as const),
  );

  let texts = original;
  const removed = new Set<string>();

  const idOf = (each: Record<string, unknown>): string =>
    `${String(each["table"])}.${String(each["column"])}`;

  const render = (
    drop: ReadonlySet<string>,
    schema: ReadonlyMap<string, string>,
  ): ReadonlyMap<string, string> => {
    const sources = [...schema.values()];

    const scanned = sameTenantLayout(
      sources.map((text) => ({ text })),
      schemas,
    );

    return statementsOf(names, {
      ...withEntries(base, (each) => !drop.has(idOf(each))),
      ...scanned,
      sameTenantTags: sameTenantTagsOf(sources, schemas, scanned.foreignKeys),
    });
  };

  let before = render(removed, texts);

  for (const entry of entries) {
    const { table, column } = entry.value;
    const at = `${entry.path}[${String(entry.index)}] (${String(table)}.${String(column)})`;

    const stay = (reason: string): void => {
      review.push({ message: `${at} stays in the config: ${reason}.` });
    };

    if (typeof table !== "string" || typeof column !== "string") {
      stay("it has no table and column");
      continue;
    }

    // Only the original texts are read as facts; a comment added to one does
    // not change what it creates.
    const creatorPath = [...original].find(([, text]) =>
      declarationsOfText(text).creates.some((each) => each.table === table),
    )?.[0];

    const creator =
      creatorPath === undefined
        ? undefined
        : ([creatorPath, texts.get(creatorPath) ?? ""] as const);

    if (creator === undefined) {
      stay("no schema file creates the table");
      continue;
    }

    const scanned = sameTenantLayout(
      [...texts.values()].map((text) => ({ text })),
      schemas,
    );

    const key = scanned.foreignKeys.find(
      (each) => each.table === table && each.columns.includes(column),
    );

    if (key === undefined) {
      stay("no foreign key holds the column, and a tag needs one");
      continue;
    }

    const companions = new Set(
      key.columns.flatMap((own, index) => {
        const other = key.referencedColumns[index];

        return own === column || other === undefined ? [] : [`${own}=${other}`];
      }),
    );

    const line = tagFor(entry.value, companions);

    if (line === undefined) {
      stay("a through hop with its own key column does not fit a tag");
      continue;
    }

    if (line === "@bsb same-tenant") {
      stay(
        "it equals the entry the block derives, so `codemod config --prune` removes it",
      );
      continue;
    }

    const [path, text] = creator;

    const candidate = new Map(texts).set(
      path,
      withColumnTag(text, table, column, line),
    );

    const after = render(new Set([...removed, idOf(entry.value)]), candidate);
    const wanted = before.get(statementKey(table, column));

    if (
      wanted === undefined ||
      after.get(statementKey(table, column)) !== wanted
    ) {
      stay(`the tag \`${line}\` would not render the same trigger statement`);
      continue;
    }

    texts = candidate;
    removed.add(idOf(entry.value));
    before = after;
  }

  const files: PlannedFile[] = [...texts]
    .filter(([path, text]) => original.get(path) !== text)
    .map(([path, contents]) => ({ path, contents, policy: "edit" }));

  if (removed.size > 0) {
    if (project.configFile === undefined || project.configText === undefined) {
      review.push({
        message: "No config file was found; remove the moved entries by hand.",
      });
    } else {
      const gone = entries
        .filter((entry) => removed.has(idOf(entry.value)))
        .toSorted((a, b) => b.index - a.index)
        .map((entry) => `${entry.path}[${String(entry.index)}]`);

      const cut = withoutConfigPaths(project.configText, gone);

      for (const path of cut.missed) {
        review.push({
          message: `${path} moved to a tag, but the codemod could not find it in ${project.configFile}; remove it by hand.`,
        });
      }

      if (cut.text !== project.configText) {
        files.push({
          path: project.configFile,
          contents: cut.text,
          policy: "edit",
        });
      }
    }
  }

  return { files, review, moved: removed.size };
}

/**
 * `sameTenantMoves` for a project: it reads the layout the project renders
 * with, and does nothing when the config lists no entry.
 */
export async function projectSameTenantMoves(
  project: CodemodProject,
): Promise<SameTenantMoves> {
  if (
    !project.config.blockNames.includes("memberships") ||
    entriesOf(project.config).length === 0
  ) {
    return { files: [], review: [], moved: 0 };
  }

  return sameTenantMoves(
    project,
    await layoutFor(project.config, {}, project.config.blockNames),
  );
}
