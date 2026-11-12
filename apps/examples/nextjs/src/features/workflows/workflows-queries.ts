import type { WorkflowRunStatus } from "better-supabase/blocks/workflows";

import {
  rpcTransport,
  topologicalOrder,
} from "better-supabase/blocks/workflow-editor";
import { createWorkflows } from "better-supabase/blocks/workflows";
import { tenantOf } from "better-supabase/next";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";
import "server-only";

import { bsb } from "@/lib/supabase/server";
import { bsbCore } from "@/lib/supabase/server-core";

import type { JsonObject } from "./builder/config-templates";

import { builderFor } from "./builder/builder-server";
import { JsonObjectSchema } from "./builder/config-templates";
import { workflowName } from "./workflow-labels";

/** A schedule as plain data, so it crosses the server boundary. */
export interface ScheduleRow {
  readonly id: string;
  readonly name: string;
  readonly workflow: string;
  readonly cron: string;
  readonly nextRunAt: string;
  readonly paused: boolean;
}

/** The active organization's workflow schedules. */
export async function getSchedules(): Promise<readonly ScheduleRow[]> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return [];
  }

  const schedules = await db.workflows.schedules
    .list(tenant, { limit: 100 })
    .orThrow();

  return schedules.map((schedule) => ({
    id: schedule.id,
    name: schedule.name,
    workflow: schedule.workflow,
    cron: schedule.cron,
    nextRunAt: schedule.nextRunAt.toString(),
    paused: schedule.paused,
  }));
}

/** A node of the run's graph, in the order the run walks them. */
export interface RunStepNode {
  readonly id: string;
  readonly kind: string;
  readonly label: string;
  readonly step: string | null;
  readonly config: JsonObject;
}

/** What the run page renders before the live run arrives. */
export interface RunDetailData {
  readonly id: string;
  readonly externalId: string;
  readonly name: string;
  readonly definitionId: string | null;
  readonly version: number | null;
  readonly status: WorkflowRunStatus;
  readonly mode: "live" | "test";
  /** Epoch milliseconds. */
  readonly createdAt: number;
  readonly startedAt: number | null;
  readonly completedAt: number | null;
  readonly error: string | null;
  /** The graph's nodes; empty for a run that is not a graph run. */
  readonly steps: readonly RunStepNode[];
}

const epoch = (instant: { epochMilliseconds: number } | undefined) =>
  instant === undefined ? null : instant.epochMilliseconds;

const Version = v.fallback(v.pipe(v.string(), v.toNumber(), v.integer()), 0);
const Text = v.fallback(v.nullable(v.string()), null);

/**
 * One run of the active organization with the graph version it ran, or `null`
 * when it is not the caller's to read.
 */
export async function getRunDetail(
  runId: string,
): Promise<RunDetailData | null> {
  "use cache: private";
  const { session, supabase } = await bsbCore.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const found = await createWorkflows({
    transport: rpcTransport(supabase, { schema: "api" }),
    schema: "api",
    temporal: Temporal,
  })
    .runs.get(runId)
    .orThrow();

  if (found?.tenant !== tenant) {
    return null;
  }

  const definitionId = v.parse(Text, found.attributes["bsb.definition"]);
  const rawVersion = v.parse(Version, found.attributes["bsb.version"]);
  const version = rawVersion === 0 ? null : rawVersion;
  const builder = builderFor(supabase);
  let name = workflowName(found.definition);
  let steps: readonly RunStepNode[] = [];

  if (definitionId !== null) {
    const [definition, versions] = await Promise.all([
      builder.definitions.get(definitionId).orThrow(),
      builder.versions.list(definitionId, { limit: 50 }).orThrow(),
    ]);

    name = definition?.name ?? name;
    const match = versions.find((candidate) => candidate.version === version);

    const graph =
      match === undefined
        ? undefined
        : (await builder.versions.get(match.id).orThrow())?.graph;

    if (graph !== undefined) {
      const ordered = topologicalOrder(graph) ?? graph.nodes;

      steps = ordered.map((node) => ({
        id: node.id,
        kind: node.kind,
        label: node.label ?? node.id,
        step: node.step ?? null,
        config: v.parse(v.fallback(JsonObjectSchema, {}), node.config),
      }));
    }
  }

  return {
    id: found.id,
    externalId: found.externalId,
    name,
    definitionId,
    version,
    status: found.status,
    mode: found.mode === "test" ? "test" : "live",
    createdAt: found.createdAt.epochMilliseconds,
    startedAt: epoch(found.startedAt),
    completedAt: epoch(found.completedAt),
    error: found.error ?? null,
    steps,
  };
}
