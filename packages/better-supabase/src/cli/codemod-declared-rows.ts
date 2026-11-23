import { resolve } from "node:path";

import type { Codemod, CodemodProject } from "./codemod.ts";
import type { PlannedFile } from "./core/files.ts";

import { policyOf, policySnapshot } from "../sql/index.ts";
import { ConfigDocument } from "./config-document/index.ts";
import { rowsDir } from "./rows/dir.ts";

type Fields = Readonly<Record<string, unknown>>;

const isFields = (value: unknown): value is Fields =>
  typeof value === "object" && value !== null && !Array.isArray(value);

interface Row {
  readonly kind: string;
  readonly subject: string;
  readonly key: string;
  readonly position: number;
  readonly value: Fields;
}

const sqlText = (value: string): string => `'${value.replaceAll("'", "''")}'`;

/** One upsert for `rows`, the way `db rows` reads it back. */
function upsert(rows: readonly Row[]): string {
  const values = rows.map(
    (row) =>
      `  (${sqlText(row.kind)}, ${sqlText(row.subject)}, ${sqlText(row.key)}, ${String(row.position)}, ${sqlText(JSON.stringify(row.value))}::jsonb)`,
  );

  return `insert into better_supabase.declared_defaults (kind, subject, key, position, value)
values
${values.join(",\n")}
on conflict (kind, subject, key) do update
  set position = excluded.position, value = excluded.value;
`;
}

const own = <T extends Fields>(value: T, keys: readonly string[]): Fields =>
  Object.fromEntries(
    keys.flatMap((key) =>
      value[key] === undefined ? [] : [[key, value[key]]],
    ),
  );

/** The rows of a list of items or stages. */
function listRows(
  kind: string,
  subject: string,
  list: unknown,
  fields: readonly string[],
): readonly Row[] {
  return Array.isArray(list)
    ? list.flatMap((item: unknown, position) =>
        isFields(item) && typeof item["key"] === "string"
          ? [
              {
                kind,
                subject,
                key: item["key"],
                position,
                value: own(item, fields),
              },
            ]
          : [],
      )
    : [];
}

const ITEM_FIELDS = ["key", "label", "level", "color", "icon"] as const;

const STAGE_FIELDS = [
  "key",
  "name",
  "category",
  "probability",
  "color",
  "icon",
] as const;

/** What the codemod moves, and the config paths it removes afterwards. */
export interface DeclaredRowsMove {
  readonly files: Readonly<Record<string, readonly Row[]>>;
  readonly remove: readonly (readonly string[])[];
  readonly review: readonly string[];
}

/**
 * The rows and the config paths for the blocks of a resolved config: option set
 * `items` and `brands`, pipeline `stages` and approval `policies`.
 */
export function declaredRowsMove(
  blocks: Readonly<Record<string, unknown>>,
): DeclaredRowsMove {
  const files: Record<string, Row[]> = {};
  const remove: string[][] = [];
  const review: string[] = [];

  const add = (file: string, rows: readonly Row[]): void => {
    files[file] = [...(files[file] ?? []), ...rows];
  };

  const settings = (name: string): Fields =>
    isFields(blocks[name]) ? blocks[name] : {};

  const on = (name: string): Fields => {
    const value = settings(name)["on"];

    return isFields(value) ? value : {};
  };

  for (const [type, fields] of Object.entries(on("option-sets"))) {
    if (!isFields(fields)) {
      continue;
    }

    for (const [field, binding] of Object.entries(fields)) {
      if (!isFields(binding)) {
        continue;
      }

      const subject = `${type}.${field}`;
      const base = ["blocks", "option-sets", "on", type, field];

      const items = listRows(
        "option_set_item",
        subject,
        binding["items"],
        ITEM_FIELDS,
      );

      if (items.length > 0) {
        add("option-sets", items);
        remove.push([...base, "items"]);
      }

      const brands = isFields(binding["brands"]) ? binding["brands"] : {};

      const branded = Object.entries(brands).flatMap(([brand, list]) =>
        listRows("option_set_item", `${subject}@${brand}`, list, ITEM_FIELDS),
      );

      if (branded.length > 0) {
        add("option-sets", branded);
        remove.push([...base, "brands"]);
      }
    }
  }

  for (const [type, binding] of Object.entries(on("pipelines"))) {
    if (!isFields(binding)) {
      continue;
    }

    const base = ["blocks", "pipelines", "on", type];

    const stages = listRows(
      "pipeline_stage",
      type,
      binding["stages"],
      STAGE_FIELDS,
    );

    if (stages.length > 0) {
      add("pipelines", stages);
      remove.push([...base, "stages"]);
    }

    const brands = isFields(binding["brands"]) ? binding["brands"] : {};

    const branded = Object.entries(brands).flatMap(([brand, entry]) =>
      listRows(
        "pipeline_stage",
        `${type}@${brand}`,
        isFields(entry) ? entry["stages"] : undefined,
        STAGE_FIELDS,
      ),
    );

    if (branded.length > 0) {
      add("pipelines", branded);
      remove.push([...base, "brands"]);
    }
  }

  const policies = settings("approvals")["options"];

  if (isFields(policies) && isFields(policies["policies"])) {
    const floors = Object.entries(policies["policies"]).flatMap(
      ([subjectType, actions]) =>
        isFields(actions)
          ? Object.entries(actions).map(([action, value], position): Row => {
              const policy = policyOf(
                subjectType,
                action,
                value,
                undefined,
                true,
              );

              const subject = `${subjectType}:${action}`;

              return {
                kind: "approval_floor",
                subject,
                key: subject,
                position,
                // SAFETY: policySnapshot returns the JSON of a plain object.
                value: JSON.parse(policySnapshot(policy)) as Fields,
              };
            })
          : [],
    );

    if (floors.length > 0) {
      add("approvals", floors);
      remove.push(["blocks", "approvals", "options", "policies"]);
    }
  }

  return { files, remove, review };
}

/** The text of one rows file. */
function rowsFileText(name: string, rows: readonly Row[]): string {
  const kinds = [...new Set(rows.map((row) => row.kind))].join(", ");

  return `-- Declared rows for ${name} (${kinds}), moved out of the config by \`better-supabase codemod declared-rows\`.
-- Run \`better-supabase db rows\` to turn changes into a data migration.

${upsert(rows)}`;
}

/**
 * The `declared-rows` codemod: move option set items, stages and floors to
 * rows.
 */
export function declaredRowsCodemod(): Codemod {
  return {
    name: "declared-rows",
    description:
      "Move option set items, pipeline stages and approval floors out of the config into supabase/rows",
    project: (project: CodemodProject) => {
      const move = declaredRowsMove(
        Object.fromEntries(
          Object.entries(project.config.blocks).map(([name, block]) => [
            name,
            block,
          ]),
        ),
      );

      const review: { message: string }[] = move.review.map((message) => ({
        message,
      }));

      if (Object.keys(move.files).length === 0) {
        return Promise.resolve({ files: [], review });
      }

      const folder = resolve(project.config.root, rowsDir(project.config));

      const files: PlannedFile[] = Object.entries(move.files).map(
        ([name, rows]): PlannedFile => ({
          path: `${folder}/${name}.sql`,
          contents: rowsFileText(name, rows),
          policy: "create",
        }),
      );

      if (
        project.configFile !== undefined &&
        project.configText !== undefined
      ) {
        const document = ConfigDocument.parse(project.configText);

        for (const path of move.remove) {
          document.remove(path);
        }

        review.push(...document.review.map((message) => ({ message })));

        if (document.text !== project.configText) {
          files.push({
            path: project.configFile,
            contents: document.text,
            policy: "edit",
          });
        }
      } else {
        review.push({
          message:
            "The config file was not found, so the items stay in it. Remove the moved items, stages and policies by hand.",
        });
      }

      review.push({
        message:
          "Run `better-supabase db rows` to write the data migration, and remove an import the config no longer uses (for example a stage helper).",
      });

      return Promise.resolve({ files, review });
    },
  };
}
