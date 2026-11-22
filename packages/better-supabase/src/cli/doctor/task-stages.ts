import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import { blockTables } from "../../sql/index.ts";
import { errorText } from "../core/errors.ts";
import { ident as sqlIdent, literal as sqlString } from "./live.ts";

const SUBJECT_TYPE = "task";

interface StageOption {
  readonly option: string;
  readonly key: string | undefined;
  readonly category: string | undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function reference(option: string, value: unknown): StageOption | undefined {
  if (typeof value === "string") {
    return { option, key: value, category: undefined };
  }

  if (isRecord(value) && typeof value["category"] === "string") {
    return { option, key: undefined, category: value["category"] };
  }

  return undefined;
}

/** The stage options `blocks.tasks.options` sets: hold, start and expired. */
function stageOptions(context: DoctorContext): StageOption[] {
  const options = context.config.blocks["tasks"]?.options;
  const claims: unknown = options?.["claims"];
  const hold: unknown = options?.["hold"];

  return [
    reference("hold.stage", isRecord(hold) ? hold["stage"] : undefined),
    reference(
      "claims.startStage",
      isRecord(claims) ? claims["startStage"] : undefined,
    ),
    reference(
      "claims.expiredStage",
      isRecord(claims) ? claims["expiredStage"] : undefined,
    ),
  ].filter((each): each is StageOption => each !== undefined);
}

export const TASK_STAGE_RULES: readonly Rule[] = [
  {
    code: "BS245",
    severity: "warning",
    title: "A task pipeline lacks a stage an option names",
    description:
      "`blocks.tasks.options.hold.stage`, `claims.startStage` and `claims.expiredStage` name a stage by key or `{ category }`. A hold in a pipeline without that stage raises TASK_HOLD_STAGE_MISSING, and a claim or an expiry in a pipeline without it leaves the task where it is, silently. Doctor lists each live pipeline of the task subject type that has no live stage for an option that is set. Needs a database; saved snapshots skip it.",
    async check(context) {
      const db = context.database;

      if (!db || "skipped" in db) {
        return [];
      }

      const wanted = stageOptions(context);
      const tables = blockTables(context.config).byBlock["pipelines"];
      const pipelines = tables?.["pipelines"];
      const stages = tables?.["stages"];

      if (wanted.length === 0 || !pipelines || !stages) {
        return [];
      }

      const pipelineColumns: Readonly<Record<string, string | null>> =
        pipelines.columns;

      const stageColumns: Readonly<Record<string, string | null>> =
        stages.columns;

      const p = (logical: string): string | null =>
        pipelineColumns[logical] ?? null;

      const s = (logical: string): string | null =>
        stageColumns[logical] ?? null;

      const columns = [
        p("id"),
        p("key"),
        p("subjectType"),
        p("archivedAt"),
        s("pipeline"),
        s("key"),
        s("category"),
        s("archivedAt"),
      ];

      if (columns.includes(null)) {
        return [];
      }

      const findings: FindingInput[] = [];

      for (const each of wanted) {
        const match =
          each.key === undefined
            ? `st.${sqlIdent(s("category") ?? "")}::text = ${sqlString(each.category ?? "")}`
            : `st.${sqlIdent(s("key") ?? "")} = ${sqlString(each.key)}`;

        try {
          const rows = await db.query<{ key: string }>(
            `select pl.${sqlIdent(p("key") ?? "")} as key from ${pipelines.table} pl where pl.${sqlIdent(p("subjectType") ?? "")} = ${sqlString(SUBJECT_TYPE)} and pl.${sqlIdent(p("archivedAt") ?? "")} is null and not exists (select 1 from ${stages.table} st where st.${sqlIdent(s("pipeline") ?? "")} = pl.${sqlIdent(p("id") ?? "")} and st.${sqlIdent(s("archivedAt") ?? "")} is null and ${match}) group by 1 order by 1`,
          );

          if (rows.length > 0) {
            const named =
              each.key === undefined
                ? `the category ${each.category ?? ""}`
                : `the stage ${each.key}`;

            findings.push({
              message: `blocks.tasks.options.${each.option} names ${named}, which ${rows.map((row) => row.key).join(", ")} ${rows.length === 1 ? "has" : "have"} no live stage for. Add the stage to the pipeline, or point the option at a category all pipelines share.`,
              target: pipelines.table,
            });
          }
        } catch (cause) {
          const text = errorText(cause);

          if (!text.includes("does not exist")) {
            findings.push({
              message: `Could not read the task pipelines (${db.describe}): ${text}`,
            });
          }
        }
      }

      return findings;
    },
  },
];
