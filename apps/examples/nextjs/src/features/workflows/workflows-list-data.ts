import type { RpcClient } from "better-supabase/blocks/organizations";
import type {
  WorkflowRun,
  WorkflowRunsQuery,
} from "better-supabase/blocks/workflows";

import { rpcTransport } from "better-supabase/blocks/workflow-editor";
import { createWorkflows } from "better-supabase/blocks/workflows";
import { tenantOf } from "better-supabase/next";
import { Temporal } from "temporal-polyfill";
import * as v from "valibot";
import "server-only";

import type { RecordListPage } from "@/components/record-list/record-list-types";
import type { SimpleListQuery } from "@/lib/simple-list";

import { bsbCore } from "@/lib/supabase/server-core";

import type {
  DefinitionListRow,
  DefinitionState,
  RunListRow,
} from "./workflow-lists";

import { builderFor } from "./builder/builder-server";
import { workflowName } from "./workflow-labels";
import {
  DEFINITION_STATES,
  definitionList,
  isRunSince,
  RUN_SINCE,
  RUN_STATUSES,
  runList,
} from "./workflow-lists";

type Writable<T> = { -readonly [K in keyof T]: T[K] };

const DEFINITIONS_PAGE = 25;
const RUNS_PAGE = 25;
const RUNS_BATCH = 100;
const RUNS_BATCHES = 5;

const Text = v.fallback(v.nullable(v.string()), null);

const stateOf = (published: number | undefined, draft: boolean | undefined) =>
  published === undefined
    ? draft === true
      ? "draft"
      : ("new" satisfies DefinitionState)
    : "published";

/**
 * One page of the tenant's definitions. The library lists up to 200 with no
 * search or sort of its own, so the list route searches, filters and sorts them
 * here (finding EX-200) and pages by offset.
 */
export async function queryDefinitions(
  supabase: RpcClient,
  tenant: string,
  query: SimpleListQuery,
): Promise<RecordListPage<DefinitionListRow>> {
  const all = await builderFor(supabase)
    .definitions.list({ tenant, limit: 200 })
    .orThrow();

  const needle = query.q?.toLowerCase();

  const rows = all
    .map((definition): DefinitionListRow => ({
      id: definition.id,
      name: definition.name,
      slug: definition.slug,
      state: stateOf(definition.published, definition.draft),
      published: definition.published ?? null,
      updatedAt: definition.updatedAt.epochMilliseconds,
    }))
    .filter(
      (row) =>
        needle === undefined ||
        `${row.name} ${row.slug}`.toLowerCase().includes(needle),
    );

  const states = query.facets["state"];

  const counts = Object.fromEntries(
    DEFINITION_STATES.map((state) => [
      state,
      rows.filter((row) => row.state === state).length,
    ]),
  );

  const shown = rows
    .filter((row) => states === undefined || states.includes(row.state))
    .toSorted((a, b) =>
      query.sort === "name"
        ? a.name.localeCompare(b.name)
        : b.updatedAt - a.updatedAt,
    );

  const offset = Math.max(0, Number(query.after ?? 0) || 0);
  const end = offset + DEFINITIONS_PAGE;

  return {
    items: shown.slice(offset, end),
    nextCursor: end < shown.length ? String(end) : null,
    facetCounts: { state: counts },
  };
}

const rowOf = (
  run: WorkflowRun,
  names: ReadonlyMap<string, string>,
): RunListRow => {
  const definitionId = v.parse(Text, run.attributes["bsb.definition"]);
  const started = (run.startedAt ?? run.createdAt).epochMilliseconds;

  return {
    id: run.id,
    name:
      (definitionId === null ? undefined : names.get(definitionId)) ??
      workflowName(run.definition),
    definitionId,
    status: run.status,
    mode: run.mode === "test" ? "test" : "live",
    createdAt: run.createdAt.epochMilliseconds,
    durationMs:
      run.completedAt === undefined
        ? null
        : run.completedAt.epochMilliseconds - started,
    error: run.error ?? null,
  };
};

/**
 * One page of the tenant's runs, newest first. The library filters by one
 * status, a mode and a creation cursor; the search, several statuses, the
 * definition and the time window are applied here while scanning up to 500
 * runs. The cursor is the creation time of the last row.
 */
export async function queryRuns(
  supabase: RpcClient,
  tenant: string,
  query: SimpleListQuery,
  names: ReadonlyMap<string, string>,
): Promise<RecordListPage<RunListRow>> {
  const workflows = createWorkflows({
    transport: rpcTransport(supabase, { schema: "api" }),
    schema: "api",
    temporal: Temporal,
  });

  const statuses = query.facets["status"] ?? [];
  const modes = query.facets["mode"] ?? [];
  const definitions = query.facets["definition"];
  const window = query.facets["since"]?.[0];

  const sinceMs =
    window !== undefined && isRunSince(window)
      ? Temporal.Now.instant().epochMilliseconds - RUN_SINCE[window]
      : undefined;

  const needle = query.q?.toLowerCase();

  const mode =
    modes.length === 1 && modes[0] !== undefined
      ? modes[0] === "test"
        ? "test"
        : "live"
      : "all";

  const status =
    statuses.length === 1
      ? RUN_STATUSES.find((known) => known === statuses[0])
      : undefined;

  const items: RunListRow[] = [];

  let cursor =
    query.after === undefined
      ? undefined
      : Temporal.Instant.fromEpochMilliseconds(Number(query.after));

  let next: string | null = null;
  let exhausted = false;
  let done = false;

  for (let round = 0; round < RUNS_BATCHES && !done; round += 1) {
    const filter: Writable<WorkflowRunsQuery> = {
      tenant,
      mode,
      limit: RUNS_BATCH,
    };

    if (status !== undefined) {
      filter.status = status;
    }

    if (cursor !== undefined) {
      filter.cursor = cursor;
    }

    const batch = await workflows.runs.list(filter).orThrow();

    for (const run of batch) {
      if (sinceMs !== undefined && run.createdAt.epochMilliseconds < sinceMs) {
        exhausted = true;
        done = true;
        break;
      }

      const row = rowOf(run, names);

      const matches =
        (statuses.length < 2 || statuses.includes(row.status)) &&
        (definitions === undefined ||
          (row.definitionId !== null &&
            definitions.includes(row.definitionId))) &&
        (needle === undefined ||
          `${row.name} ${run.externalId}`.toLowerCase().includes(needle));

      if (!matches) {
        continue;
      }

      items.push(row);

      if (items.length === RUNS_PAGE) {
        next = String(row.createdAt);
        done = true;
        break;
      }
    }

    if (!done && batch.length < RUNS_BATCH) {
      exhausted = true;
      done = true;
    }

    cursor = batch.at(-1)?.createdAt;
  }

  if (next === null && !exhausted && cursor !== undefined) {
    next = String(cursor.epochMilliseconds);
  }

  return { items, nextCursor: next };
}

const FIRST_PAGE = runList.defaults;

/** The facet values the runs overview offers for `definition`. */
export interface RunDefinitionOption {
  readonly value: string;
  readonly label: string;
}

/** The tenant's definitions by id, for run names and the definition facet. */
export async function definitionNames(
  supabase: RpcClient,
  tenant: string,
): Promise<ReadonlyMap<string, string>> {
  const all = await builderFor(supabase)
    .definitions.list({ tenant, limit: 200 })
    .orThrow();

  return new Map(all.map((definition) => [definition.id, definition.name]));
}

/** The definitions overview's first page, for the server render. */
export async function getDefinitionsPage(): Promise<
  RecordListPage<DefinitionListRow>
> {
  "use cache: private";
  const { session, supabase } = await bsbCore.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return { items: [], nextCursor: null };
  }

  return queryDefinitions(supabase, tenant, definitionList.defaults);
}

export interface RunsOverview {
  readonly page: RecordListPage<RunListRow>;
  readonly definitions: readonly RunDefinitionOption[];
  readonly tenant: string | null;
}

/** The runs overview's first page and the definitions its facet offers. */
export async function getRunsPage(): Promise<RunsOverview> {
  "use cache: private";
  const { session, supabase } = await bsbCore.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return {
      page: { items: [], nextCursor: null },
      definitions: [],
      tenant: null,
    };
  }

  const names = await definitionNames(supabase, tenant);

  return {
    page: await queryRuns(supabase, tenant, FIRST_PAGE, names),
    definitions: [...names].map(([value, label]) => ({ value, label })),
    tenant,
  };
}
