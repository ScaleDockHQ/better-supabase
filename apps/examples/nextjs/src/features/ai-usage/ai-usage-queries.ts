import "server-only";
import { opsAccess } from "@/features/assistant/assistant-ops";
import { aiRuns } from "@/features/assistant/assistant-server";
import { getMembers } from "@/features/organization/organization-queries";
import { bsbCore } from "@/lib/supabase/server-core";

/** The newest runs one read covers; totals past it are lower bounds. */
export const USAGE_WINDOW = 200;

const num = (value: unknown): number =>
  typeof value === "number" && Number.isFinite(value) ? value : 0;

/** The ranges the page offers, in days; `0` is every run in the window. */
export const USAGE_RANGES = [7, 30, 90, 0] as const;

export type UsageRange = (typeof USAGE_RANGES)[number];

/** The range a `range` search param names. */
export const usageRangeOf = (value: string): UsageRange =>
  USAGE_RANGES.find((range) => String(range) === value) ?? 0;

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

export interface UserSpend {
  readonly id: string;
  /** The member's name, else their email, else the user id. */
  readonly name: string;
  readonly runs: number;
  readonly inputTokens: number;
  readonly outputTokens: number;
  readonly costMicroUsd: number;
}

export interface UserSpendRead {
  readonly users: readonly UserSpend[];
  readonly failed: boolean;
}

export interface AiUsage {
  readonly runs: number;
  readonly failed: number;
  readonly inputTokens: number;
  readonly outputTokens: number;
  readonly cachedInputTokens: number;
  readonly costMicroUsd: number;
  readonly capped: boolean;
  /** The range the numbers cover, in days; `0` for every run in the window. */
  readonly range: UsageRange;
  readonly models: readonly ModelSpend[];
  readonly days: readonly DaySpend[];
}

/**
 * The token and cost ledger of the caller's newest runs, by model and by day.
 * `ai_runs` rows carry the usage and the gateway's cost, so this reads them as
 * they are; there is no usage rollup in the block (EX-318). `range` keeps the
 * runs of the last N days (EX-306). The per-user rollup is `getAiUserUsage`,
 * because `ai_runs` is readable by its owner only.
 */
export async function getAiUsage(range: UsageRange = 0): Promise<AiUsage> {
  const { supabase } = await bsbCore.context();

  const window = await aiRuns(supabase).list({ limit: USAGE_WINDOW }).orThrow();

  const since =
    range === 0
      ? undefined
      : Temporal.Now.instant().subtract({ hours: range * 24 });

  const runs =
    since === undefined
      ? window
      : window.filter(
          (run) => Temporal.Instant.compare(run.startedAt, since) >= 0,
        );

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
    capped: window.length >= USAGE_WINDOW,
    range,
    models: [...models]
      .map(([model, spent]) => ({ id: model, model, ...spent }))
      .toSorted((a, b) => b.costMicroUsd - a.costMicroUsd),
    days: [...days]
      .map(([day, spent]) => ({ day, ...spent }))
      .toSorted((a, b) => a.day.localeCompare(b.day)),
  };
}

/**
 * What each member of the active organization spent in the range, most
 * expensive first. `undefined` for a caller without `ai_chat.manage`, who may
 * not read other members' runs (EX-306).
 */
export async function getAiUserUsage(
  range: UsageRange = 0,
): Promise<UserSpendRead | undefined> {
  const access = await opsAccess("ai_chat.manage");

  if (!access.allowed || access.organizationId === undefined) {
    return;
  }

  const { organizationId } = access;
  const { supabase } = await bsbCore.context();

  const [rollup, members] = await Promise.all([
    aiRuns(supabase).usageByUser({
      organizationId,
      ...(range === 0
        ? {}
        : { since: Temporal.Now.instant().subtract({ hours: range * 24 }) }),
      limit: 50,
    }),
    getMembers(organizationId),
  ]);

  if (!rollup.ok) {
    return { users: [], failed: true };
  }

  const names = new Map(
    members.map((member) => [member.userId, member.name ?? member.email]),
  );

  return {
    failed: false,
    users: rollup.data.map((usage) => ({
      id: usage.userId,
      name: names.get(usage.userId) ?? usage.userId,
      runs: usage.runs,
      inputTokens: usage.inputTokens,
      outputTokens: usage.outputTokens,
      costMicroUsd: usage.costMicroUsd,
    })),
  };
}
