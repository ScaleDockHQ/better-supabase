import type { SubjectConfig } from "../../config/index.ts";
import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import { blockTables, parseBsbComment } from "../../sql/index.ts";
import { projectionsOf } from "../powersync/projection.ts";
import { subjectFromTag } from "../subject-tag.ts";
import { catalogOf } from "./shared.ts";

/** The helpers that take a table name and read or sync its rows. */
const HELPERS = [
  "createNativeClient",
  "powersyncEngine",
  "attachmentQueueRoute",
  "queryEngine",
];

const HELPER_CALL = new RegExp(String.raw`\b(${HELPERS.join("|")})\s*\(`, "g");

const lineAt = (text: string, index: number): number =>
  text.slice(0, index).split("\n").length;

/** The text of the call whose `(` is at `open`, up to its match. */
function argumentsOf(text: string, open: number): string {
  let depth = 0;

  for (let at = open; at < text.length; at += 1) {
    const char = text[at];

    if (char === "(") {
      depth += 1;
    } else if (char === ")") {
      depth -= 1;

      if (depth === 0) {
        return text.slice(open + 1, at);
      }
    }
  }

  return text.slice(open + 1);
}

/**
 * The app's views over block tables, as the block table and the view name:
 * `better_supabase.attachments` is read through `public.job_attachments`.
 */
function projectedBlockTables(
  context: DoctorContext,
): readonly { readonly base: string; readonly view: string }[] {
  const files = (context.sqlFiles ?? []).filter(
    (file) =>
      !file.path.includes("migrations/") &&
      !file.path.includes("better-supabase-data/") &&
      !/(^|\/)900_better_supabase_/.test(file.path),
  );

  const projections = projectionsOf(files);

  const owned = new Set(
    Object.values(blockTables(context.config).byBlock).flatMap((tables) =>
      Object.values(tables).map((table) => table.table),
    ),
  );

  return [...projections].flatMap(([base, projection]) =>
    owned.has(base) ? [{ base, view: projection.view }] : [],
  );
}

const escape = (text: string): string =>
  text.replaceAll(/[.*+?^${}()|[\]\\]/g, String.raw`\$&`);

/**
 * Fields a tag and a config entry can both give. A tag that sets one the config
 * sets differently has no single answer.
 */
const COMPARED = [
  "id",
  "idType",
  "tenant",
  "title",
  "url",
  "scope",
  "deletedAt",
  "cascade",
] as const;

const shortName = (table: string): string =>
  table.startsWith("public.") ? table.slice("public.".length) : table;

function disagreements(
  type: string,
  fromTag: SubjectConfig,
  fromConfig: SubjectConfig,
): string[] {
  const say = (key: string, tag: unknown, config: unknown): string =>
    `${type}.${key}: the comment says ${JSON.stringify(tag)}, the config says ${JSON.stringify(config)}`;

  return [
    ...(shortName(fromTag.table) === shortName(fromConfig.table)
      ? []
      : [say("table", fromTag.table, fromConfig.table)]),
    ...COMPARED.filter(
      (key) =>
        fromTag[key] !== undefined &&
        fromConfig[key] !== undefined &&
        fromTag[key] !== fromConfig[key],
    ).map((key) => say(key, fromTag[key], fromConfig[key])),
  ];
}

export const PROJECTION_RULES: readonly Rule[] = [
  {
    code: "BS381",
    severity: "warning",
    title: "A call names a block table that the app projects through a view",
    description:
      "The app's view over a block table (`public.job_attachments` over `better_supabase.attachments`) is what clients read: it names the columns they may see, and PowerSync streams the same columns. `createNativeClient`, `powersyncEngine`, `attachmentQueueRoute` or `queryEngine` given the block table's name skips the view, so the client reads columns and rows the app hid. Name the view instead. Reads the app's schema files and the source files in `doctor.sources`.",
    check(context) {
      const projections = projectedBlockTables(context);

      if (projections.length === 0) {
        return [];
      }

      return context.sources.flatMap((file) =>
        [...file.text.matchAll(HELPER_CALL)].flatMap((call): FindingInput[] => {
          const args = argumentsOf(file.text, call.index + call[0].length - 1);

          return projections.flatMap(({ base, view }): FindingInput[] => {
            const name = base.slice(base.indexOf(".") + 1);
            const viewName = view.slice(view.indexOf(".") + 1);

            // The qualified name always names the block's table. The bare
            // name does too when the view is called something else.
            const pattern = new RegExp(
              `${escape(base)}\\b${name === viewName ? "" : `|(?<!\\w)${escape(name)}\\b`}`,
            );

            if (!pattern.test(args)) {
              return [];
            }

            const line = lineAt(file.text, call.index);

            return [
              {
                message: `${file.path}:${String(line)}: ${call[1]!}() names ${base}, which the app projects through ${view}. Name ${view}.`,
                target: `${file.path}:${String(line)}`,
                location: { file: file.path, line },
              },
            ];
          });
        }),
      );
    },
  },
  {
    code: "BS382",
    severity: "error",
    title: "A subject's config entry and its table comment disagree",
    description:
      "The `@bsb subject` tag on a table is the registry of the app's subjects, and a `subjects.<type>` entry in the config can set the same options. When both give an option and the values differ, `gen` keeps the config's and the comment says something else. Remove one of them, or make them agree.",
    check: (context) =>
      catalogOf(context).tables.flatMap((table): FindingInput[] => {
        const tag = parseBsbComment(table.comment ?? null).tags.find(
          (each) => each.name === "subject",
        );

        if (tag === undefined) {
          return [];
        }

        const type =
          typeof tag.args["type"] === "string" ? tag.args["type"] : table.name;

        const configured = context.config.subjects[type];

        if (configured === undefined) {
          return [];
        }

        const short =
          table.schema === "public"
            ? table.name
            : `${table.schema}.${table.name}`;

        return disagreements(
          type,
          subjectFromTag(tag.args, short),
          configured,
        ).map((message) => ({
          message: `${short} is tagged @bsb subject, and subjects.${type} disagrees: ${message}.`,
          target: short,
        }));
      }),
  },
];
