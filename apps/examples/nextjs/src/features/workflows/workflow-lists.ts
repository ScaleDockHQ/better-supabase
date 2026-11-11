import type { WorkflowRunStatus } from "better-supabase/blocks/workflows";

import { defineSimpleList } from "@/lib/simple-list";

/** The definitions overview: `/workflows?q=&state=&sort=&after=`. */
export const definitionList = defineSimpleList({
  facets: ["state"],
  sorts: ["updated", "name"],
  defaultSort: "updated",
});

/**
 * The runs overview: `/workflows/runs?q=&status=&mode=&definition=&since=`.
 * `since` is one of the `RUN_SINCE` keys.
 */
export const runList = defineSimpleList({
  facets: ["status", "mode", "definition", "since"],
  sorts: ["newest"],
  defaultSort: "newest",
});

export const DEFINITION_STATES = ["published", "draft", "new"] as const;

export type DefinitionState = (typeof DEFINITION_STATES)[number];

export const RUN_STATUSES = [
  "queued",
  "running",
  "waiting",
  "completed",
  "failed",
  "cancelled",
] as const satisfies readonly WorkflowRunStatus[];

export const RUN_MODES = ["live", "test"] as const;

/** How far back a runs overview looks, by the `since` facet's value. */
export const RUN_SINCE = {
  hour: 3_600_000,
  day: 86_400_000,
  week: 604_800_000,
} as const;

export type RunSince = keyof typeof RUN_SINCE;

export const isRunSince = (value: string): value is RunSince =>
  Object.hasOwn(RUN_SINCE, value);

/** A definition row as the overview grid shows it. */
export interface DefinitionListRow {
  readonly id: string;
  readonly name: string;
  readonly slug: string;
  readonly state: DefinitionState;
  readonly published: number | null;
  /** Epoch milliseconds. */
  readonly updatedAt: number;
}

/** A run row as the overview grid shows it. */
export interface RunListRow {
  readonly id: string;
  readonly name: string;
  /** The builder definition it ran, when it is a graph run. */
  readonly definitionId: string | null;
  readonly status: WorkflowRunStatus;
  readonly mode: "live" | "test";
  /** Epoch milliseconds. */
  readonly createdAt: number;
  readonly durationMs: number | null;
  readonly error: string | null;
}
