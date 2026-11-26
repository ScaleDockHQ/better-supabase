import type { WorkflowRunStatus } from "better-supabase/blocks/workflows";

import {
  rpcTransport,
  topologicalOrder,
} from "better-supabase/blocks/workflow-editor";
import { createWorkflows } from "better-supabase/blocks/workflows";
import { tenantOf } from "better-supabase/next";
import { Temporal } from "temporal-polyfill";
import "server-only";

import { bsbCore } from "@/lib/supabase/server-core";

import { builderFor, findDefinition } from "../builder/builder-server";

export interface DefinitionVersionRow {
  readonly version: number;
  readonly status: string;
  /** Epoch milliseconds. */
  readonly createdAt: number;
}

export interface DefinitionStepRow {
  readonly id: string;
  readonly kind: string;
  readonly label: string;
}

export interface DefinitionRunRow {
  readonly id: string;
  readonly status: WorkflowRunStatus;
  readonly mode: "live" | "test";
  /** Epoch milliseconds. */
  readonly createdAt: number;
  readonly durationMs: number | null;
}

export interface DefinitionDetailData {
  readonly id: string;
  readonly name: string;
  readonly slug: string;
  readonly description: string;
  readonly published: number | null;
  /** Epoch milliseconds. */
  readonly updatedAt: number;
  readonly versions: readonly DefinitionVersionRow[];
  /** The steps of the newest version, in the order a run walks them. */
  readonly steps: readonly DefinitionStepRow[];
  /** The latest runs of this definition, newest first. */
  readonly runs: readonly DefinitionRunRow[];
}

const RECENT_RUNS = 50;

/**
 * One definition of the active organization, or `null` when it is not the
 * caller's.
 */
export async function getDefinitionDetail(
  id: string,
): Promise<DefinitionDetailData | null> {
  "use cache: private";
  const { session, supabase } = await bsbCore.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const definition = await findDefinition(supabase, id);

  if (definition === undefined) {
    return null;
  }

  const builder = builderFor(supabase);

  const [versions, runs] = await Promise.all([
    builder.versions.list(id, { limit: 50 }).orThrow(),
    createWorkflows({
      transport: rpcTransport(supabase, { schema: "api" }),
      schema: "api",
      temporal: Temporal,
    })
      .runs.list({
        tenant,
        mode: "all",
        definitionId: [id],
        limit: RECENT_RUNS,
      })
      .orThrow(),
  ]);

  const newest = versions.toSorted((a, b) => b.version - a.version).at(0);

  const graph =
    newest === undefined
      ? undefined
      : (await builder.versions.get(newest.id).orThrow())?.graph;

  const steps =
    graph === undefined
      ? []
      : (topologicalOrder(graph) ?? graph.nodes).map((node) => ({
          id: node.id,
          kind: node.kind,
          label: node.label ?? node.id,
        }));

  return {
    id: definition.id,
    name: definition.name,
    slug: definition.slug,
    description: definition.description ?? "",
    published: definition.published ?? null,
    updatedAt: definition.updatedAt.epochMilliseconds,
    versions: versions
      .toSorted((a, b) => b.version - a.version)
      .map((version) => ({
        version: version.version,
        status: version.status,
        createdAt: version.createdAt.epochMilliseconds,
      })),
    steps,
    runs: runs.map((run) => ({
      id: run.id,
      status: run.status,
      mode: run.mode === "test" ? "test" : "live",
      createdAt: run.createdAt.epochMilliseconds,
      durationMs:
        run.completedAt === undefined
          ? null
          : run.completedAt.epochMilliseconds -
            (run.startedAt ?? run.createdAt).epochMilliseconds,
    })),
  };
}
