import "server-only";
import type {
  EvalComparison,
  EvalSummary,
} from "better-supabase/blocks/ai-evals";

import type { OpsListQuery } from "@/components/ops-list/ops-list-params";

import { opsTenant } from "@/features/assistant/assistant-ops";
import { promptSubjects } from "@/features/prompts/prompts-queries";
import { promptsBlock } from "@/features/prompts/prompts-server";

import type { EvalParams } from "./evals-search-params";

import { evalsBlock } from "./evals-server";

const PAGE_SIZE = 25;

export interface EvalSubjectRow {
  readonly id: string;
  readonly title: string;
}

/**
 * The prompts that have an eval workspace, searched and sorted here. A dataset
 * is created on first open, because the block has no read by name (EX-313).
 */
export async function getEvalSubjectPage(
  query: OpsListQuery,
): Promise<{
  readonly items: readonly EvalSubjectRow[];
  readonly nextCursor: string | null;
}> {
  const organizationId = await opsTenant("ai_chat.manage");

  if (organizationId === undefined) {
    return { items: [], nextCursor: null };
  }

  const needle = query.q.toLowerCase();

  const subjects = (await promptSubjects(organizationId))
    .filter(
      (subject) =>
        needle === "" ||
        subject.name.includes(needle) ||
        subject.title.toLowerCase().includes(needle),
    )
    .toSorted((a, b) => a.title.localeCompare(b.title));

  const start = Number(query.cursor ?? 0);

  return {
    items: subjects
      .slice(start, start + PAGE_SIZE)
      .map((subject) => ({ id: subject.name, title: subject.title })),
    nextCursor:
      start + PAGE_SIZE < subjects.length ? String(start + PAGE_SIZE) : null,
  };
}

export interface EvalRunRow {
  readonly id: string;
  readonly promptVersion: number;
  readonly model: string;
  readonly status: string;
  readonly summary: EvalSummary | undefined;
  /** ISO 8601. */
  readonly createdAt: string;
}

export interface EvalResultRow {
  readonly itemId: string;
  readonly input: string;
  readonly expected: string;
  readonly output: string;
  readonly passed: boolean;
  readonly reason: string;
  readonly error: string | undefined;
  readonly latencyMs: number | undefined;
}

export interface EvalWorkspace {
  readonly name: string;
  readonly datasetId: string;
  readonly items: readonly { id: string; input: string; expected: string }[];
  readonly versions: readonly number[];
  readonly runs: readonly EvalRunRow[];
  readonly selected: EvalRunRow | undefined;
  readonly results: readonly EvalResultRow[];
  readonly comparison: EvalComparison | undefined;
}

const text = (value: unknown): string =>
  value === undefined || value === null
    ? ""
    : typeof value === "string"
      ? value
      : JSON.stringify(value);

/** The dataset, runs, trend and results of one prompt's evals. */
export async function getEvalWorkspace(
  name: string,
  params: EvalParams,
): Promise<EvalWorkspace | undefined> {
  const organizationId = await opsTenant("ai_chat.manage");

  if (organizationId === undefined) {
    return undefined;
  }

  const evals = evalsBlock();

  const dataset = await evals.datasets
    .create({ name, organizationId })
    .orThrow();

  const [items, runs, versions] = await Promise.all([
    evals.items.list({ datasetId: dataset.id, limit: 100 }).orThrow(),
    evals.runs.list({ datasetId: dataset.id, limit: 20 }).orThrow(),
    promptsBlock().versions({ name, organizationId }).orThrow(),
  ]);

  const rows: EvalRunRow[] = runs.map((run) => ({
    id: run.id,
    promptVersion: run.promptVersion,
    model: run.model,
    status: run.status,
    summary: run.summary,
    createdAt: run.createdAt.toString(),
  }));

  const selected = rows.find((row) => row.id === params.run) ?? rows[0];

  const baseline =
    selected === undefined
      ? undefined
      : rows[rows.findIndex((row) => row.id === selected.id) + 1];

  const [results, comparison] = await Promise.all([
    selected === undefined
      ? []
      : evals.runs
          .results({
            runId: selected.id,
            limit: 100,
            ...(params.failed ? { onlyFailed: true } : {}),
          })
          .orThrow(),
    selected === undefined || baseline === undefined
      ? undefined
      : evals.runs
          .compare({ baseRunId: baseline.id, candidateRunId: selected.id })
          .orThrow(),
  ]);

  const byId = new Map(items.map((item) => [item.id, item]));

  return {
    name,
    datasetId: dataset.id,
    items: items.map((item) => ({
      id: item.id,
      input: text(item.input),
      expected: text(item.expected),
    })),
    versions: versions.map((entry) => entry.version),
    runs: rows,
    selected,
    results: results.map((result) => {
      const item = byId.get(result.itemId);

      const failedScore = Object.values(result.scores).find(
        (score) => !score.passed,
      );

      return {
        itemId: result.itemId,
        input: text(item?.input),
        expected: text(item?.expected),
        output: result.output ?? "",
        passed: result.passed,
        reason: failedScore?.reason ?? "",
        error: result.error,
        latencyMs: result.latencyMs,
      };
    }),
    comparison,
  };
}
