import "server-only";
import { aiRuns } from "@/features/assistant/assistant-server";
import { bsbCore } from "@/lib/supabase/server-core";

/** The newest runs one read covers; totals past it are lower bounds. */
export const USAGE_WINDOW = 200;

const num = (value: unknown): number =>
  typeof value === "number" && Number.isFinite(value) ? value : 0;

export interface ModelSpend {
  readonly id: string;
  readonly model: string;
  readonly runs: number;
  readonly inputTokens: number;
  readonly outputTokens: number;
  readonly costMicroUsd: number;
}

export interface DaySpend {
  readonly day: string;
  readonly costUsd: number;
  readonly runs: number;
}

export interface AiUsage {
  readonly runs: number;
  readonly failed: number;
  readonly inputTokens: number;
  readonly outputTokens: number;
  readonly cachedInputTokens: number;
  readonly costMicroUsd: number;
  readonly capped: boolean;
  readonly models: readonly ModelSpend[];
  readonly days: readonly DaySpend[];
}

/**
 * The token and cost ledger of the caller's newest runs, by model and by day.
 * `ai_runs` rows carry the usage and the gateway's cost, so this reads them as
 * they are; there is no usage rollup in the block (EX-318).
 */
export async function getAiUsage(): Promise<AiUsage> {
  const { supabase } = await bsbCore.context();

  const runs = await aiRuns(supabase).list({ limit: USAGE_WINDOW }).orThrow();

  const models = new Map<string, Omit<ModelSpend, "id" | "model">>();
  const days = new Map<string, { costUsd: number; runs: number }>();

  let inputTokens = 0;
  let outputTokens = 0;
  let cachedInputTokens = 0;
  let costMicroUsd = 0;

  for (const run of runs) {
    const input = num(run.usage["inputTokens"]);
    const output = num(run.usage["outputTokens"]);
    const cost = run.costMicroUsd ?? 0;
    const model = run.model ?? "unknown";
    const day = run.startedAt.toString().slice(0, 10);

    inputTokens += input;
    outputTokens += output;
    cachedInputTokens += num(run.usage["cachedInputTokens"]);
    costMicroUsd += cost;

    const spent = models.get(model) ?? {
      runs: 0,
      inputTokens: 0,
      outputTokens: 0,
      costMicroUsd: 0,
    };

    models.set(model, {
      runs: spent.runs + 1,
      inputTokens: spent.inputTokens + input,
      outputTokens: spent.outputTokens + output,
      costMicroUsd: spent.costMicroUsd + cost,
    });

    const daily = days.get(day) ?? { costUsd: 0, runs: 0 };
    days.set(day, {
      costUsd: daily.costUsd + cost / 1_000_000,
      runs: daily.runs + 1,
    });
  }

  return {
    runs: runs.length,
    failed: runs.filter((run) => run.status === "failed").length,
    inputTokens,
    outputTokens,
    cachedInputTokens,
    costMicroUsd,
    capped: runs.length >= USAGE_WINDOW,
    models: [...models]
      .map(([model, spent]) => ({ id: model, model, ...spent }))
      .toSorted((a, b) => b.costMicroUsd - a.costMicroUsd),
    days: [...days]
      .map(([day, spent]) => ({ day, ...spent }))
      .toSorted((a, b) => a.day.localeCompare(b.day)),
  };
}
