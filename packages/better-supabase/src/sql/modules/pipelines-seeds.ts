import type { BlockSqlContext } from "../context.ts";
import type { BlockSeeds, SeedRow, SeedTable } from "../seeds.ts";
import type { PipelineBinding } from "./pipelines-bindings.ts";

import { rankKeys } from "../../core/rank-keys.ts";
import { sqlString } from "../../core/template.ts";
import { pipelineBindings } from "./pipelines-bindings.ts";

/**
 * The named stage-template sets bindings can declare through `variant`. A
 * preset names one to seed only that set of pipelines.
 */
export const PIPELINE_VARIANTS = ["b2b-sales", "recruiting"] as const;

/** The key of the pipeline the first-use path and the seeds both create. */
const DEFAULT_KEY = "default";

/**
 * The bindings whose pipeline can be declared: one without `scope` has exactly
 * one default pipeline per organization. A scoped binding (a job, a case kind)
 * needs a pipeline per scope value, which only exists once the first record
 * names it, so `default_pipeline` still creates those on first use.
 */
export function seedableBindings(
  bindings: readonly PipelineBinding[],
): readonly PipelineBinding[] {
  return bindings.filter((binding) => binding.scope === undefined);
}

function pipelineRows(
  ctx: BlockSqlContext,
  bindings: readonly PipelineBinding[],
  variant: string | undefined,
): readonly SeedTable[] {
  const p = (column: string): string => ctx.col("pipelines", column);
  const pipelines = ctx.table("pipelines");
  const stages = ctx.table("stages");
  const s = (column: string): string => ctx.col("stages", column);

  const pipelineKey = (binding: PipelineBinding) =>
    ({
      ref: {
        table: pipelines,
        tenantColumn: p("tenant"),
        column: p("id"),
        match: {
          [p("subjectType")]: binding.type,
          [p("scope")]: null,
          [p("key")]: DEFAULT_KEY,
        },
      },
    }) as const;

  const variantOf =
    variant === undefined ? {} : ({ variant, defaultVariant: true } as const);

  const pipelineTable: SeedTable = {
    table: pipelines,
    tenantColumn: p("tenant"),
    key: [p("subjectType"), p("scope"), p("key")],
    ...variantOf,
    rows: bindings.map((binding): SeedRow => ({
      values: {
        [p("subjectType")]: binding.type,
        [p("scope")]: null,
        [p("key")]: DEFAULT_KEY,
        [p("name")]: "Default",
        // The first pipeline of a type is its default; a later seed run
        // never adds a second one.
        [p("isDefault")]: {
          sql: `not exists (select 1 from ${pipelines} d where d.${p("tenant")} = p_tenant and d.${p("subjectType")} = ${sqlString(binding.type)} and d.${p("scope")} is null and d.${p("isDefault")} and d.${p("archivedAt")} is null)`,
        },
      },
    })),
  };

  const stageKey = ctx.has("stages", "systemKey") ? "systemKey" : "key";

  const stageTable: SeedTable = {
    table: stages,
    tenantColumn: s("tenant"),
    key: [s("pipeline"), s(stageKey)],
    ...variantOf,
    rows: bindings.flatMap((binding) => {
      const ranks = rankKeys(binding.stages.length);

      return binding.stages.map((stage, index): SeedRow => {
        const values: Record<string, SeedRow["values"][string]> = {
          [s("pipeline")]: pipelineKey(binding),
          [s("key")]: stage.key,
          [s("name")]: stage.name,
          [s("category")]: {
            sql: ctx.cast("stages", "category", sqlString(stage.category)),
          },
          [s("outcome")]: {
            sql: ctx.cast(
              "stages",
              "outcome",
              sqlString(binding.categories[stage.category] ?? "open"),
            ),
          },
          [s("rank")]: ranks[index] ?? "V",
        };

        if (ctx.has("stages", "systemKey")) {
          values[s("systemKey")] = stage.key;
        }

        if (ctx.has("stages", "probability")) {
          values[s("probability")] = stage.probability ?? null;
        }

        return { values };
      });
    }),
  };

  return [pipelineTable, stageTable];
}

/**
 * `pipelines.seeds`: each unscoped binding's default pipeline with its stage
 * template. Bindings that name a `variant` are seeded for that variant and when
 * none is given; the others are always seeded.
 */
export const pipelineSeeds: BlockSeeds = {
  variants: PIPELINE_VARIANTS,
  defaults: (ctx: BlockSqlContext): readonly SeedTable[] => {
    const bindings = seedableBindings(pipelineBindings(ctx));

    const named = [
      ...new Set(
        bindings.flatMap((binding) =>
          binding.variant === undefined ? [] : [binding.variant],
        ),
      ),
    ].toSorted();

    const groups: readonly (readonly [string | undefined, typeof bindings])[] =
      [
        [
          undefined,
          bindings.filter((binding) => binding.variant === undefined),
        ],
        ...named.map(
          (variant) =>
            [
              variant,
              bindings.filter((binding) => binding.variant === variant),
            ] as const,
        ),
      ];

    // Pipelines of every group come first, so a stage's reference resolves.
    const tables = groups
      .filter(([, group]) => group.length > 0)
      .map(([variant, group]) => pipelineRows(ctx, group, variant));

    return [
      ...tables.map(([pipelines]) => pipelines!),
      ...tables.map(([, stages]) => stages!),
    ];
  },
};
