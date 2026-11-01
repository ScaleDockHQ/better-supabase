import type { AiEvals, EvalItem, EvalRun, EvalScore } from "./ai-evals.ts";
import type { EvalScorer } from "./scorers.ts";

/** The payload a queue job carries: which run to work on. */
export interface EvalJobPayload {
  readonly runId: string;
}

/** What one job invocation did. */
export interface EvalJobResult {
  readonly runId: string;
  /** Items scored in this invocation. */
  readonly processed: number;
  /**
   * Whether the run is closed. `false` means the time budget ran out first:
   * enqueue the same payload again to continue.
   */
  readonly done: boolean;
  readonly run: EvalRun | undefined;
}

export interface EvalJobOptions {
  readonly evals: Pick<AiEvals, "items" | "runs">;
  /**
   * Produces the model's answer for one item with the run's prompt version and
   * model. A thrown error becomes the item's error and does not stop the run.
   */
  readonly task: (
    item: EvalItem,
    run: EvalRun,
  ) => Promise<string | { readonly output: string }>;
  readonly scorers: readonly EvalScorer[];
  /** Items read per page. Default 25. */
  readonly pageSize?: number;
  /**
   * Stop after this many milliseconds and report `done: false`. Default: no
   * limit.
   */
  readonly budgetMs?: number;
  /** Items scored at once. Default 1. */
  readonly concurrency?: number;
}

const messageOf = (error: unknown): string =>
  error instanceof Error ? error.message : String(error);

async function scoreItem(
  item: EvalItem,
  output: string,
  scorers: readonly EvalScorer[],
): Promise<Record<string, EvalScore>> {
  const scores: Record<string, EvalScore> = {};

  for (const scorer of scorers) {
    try {
      scores[scorer.name] = await scorer.score({
        input: item.input,
        output,
        expected: item.expected,
      });
    } catch (error) {
      scores[scorer.name] = {
        score: 0,
        passed: false,
        reason: `The scorer failed: ${messageOf(error)}`,
      };
    }
  }

  return scores;
}

/**
 * A handler for a queue job that works through a run: it reads the items the
 * run has no result for, answers and scores each one, stores the result and
 * closes the run when none are left. A retry after a crash continues where the
 * run stopped, because stored results are skipped and a repeated result
 * replaces the earlier one. Database errors throw, so the queue retries.
 */
export function createEvalJob(
  options: EvalJobOptions,
): (payload: EvalJobPayload) => Promise<EvalJobResult> {
  const pageSize = options.pageSize ?? 25;
  const concurrency = Math.max(1, options.concurrency ?? 1);

  return async ({ runId }) => {
    const deadline =
      options.budgetMs === undefined ? Infinity : Date.now() + options.budgetMs;

    const found = await options.evals.runs.get(runId).orThrow();

    if (found === undefined) {
      throw new TypeError(`Eval run ${runId} does not exist`);
    }

    if (found.status !== "running") {
      return { runId, processed: 0, done: true, run: found };
    }

    let processed = 0;

    const work = async (item: EvalItem): Promise<void> => {
      const started = Date.now();
      let output: string | undefined;
      let error: string | undefined;

      try {
        const answer = await options.task(item, found);

        output = typeof answer === "string" ? answer : answer.output;
      } catch (cause) {
        error = messageOf(cause);
      }

      const scores =
        output === undefined
          ? {}
          : await scoreItem(item, output, options.scorers);

      await options.evals.runs
        .record(runId, item.id, {
          ...(output === undefined ? {} : { output }),
          scores,
          ...(error === undefined ? {} : { error }),
          latencyMs: Date.now() - started,
        })
        .orThrow();

      processed += 1;
    };

    while (Date.now() < deadline) {
      const page = await options.evals.items
        .list(found.datasetId, { pendingRun: runId, limit: pageSize })
        .orThrow();

      if (page.length === 0) {
        const run = await options.evals.runs.finish(runId).orThrow();

        return { runId, processed, done: true, run };
      }

      for (let start = 0; start < page.length; start += concurrency) {
        await Promise.all(page.slice(start, start + concurrency).map(work));

        if (Date.now() >= deadline) {
          break;
        }
      }
    }

    return { runId, processed, done: false, run: undefined };
  };
}
