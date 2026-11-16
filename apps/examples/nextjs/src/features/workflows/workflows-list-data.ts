import type { PageOptions } from "better-supabase/blocks";
import type { RpcClient } from "better-supabase/blocks/organizations";
import type { WorkflowDefinition } from "better-supabase/blocks/workflow-editor";
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

import type {
  RecordListPage,
  RecordListUrlQuery,
} from "@/components/record-list/record-list-types";
import type { Mutable } from "@/lib/block-status-list";

import { organizationPager, pageEntityRows } from "@/lib/block-entity-page";
import { bsbCore } from "@/lib/supabase/server-core";

import type {
  DefinitionListRow,
  DefinitionState,
  RunListRow,
} from "./workflow-lists";

import { builderFor } from "./builder/builder-server";
import { workflowName } from "./workflow-labels";
import {
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
const NAME_PAGE = 100;
const NAME_PAGES = 5;

const Text = v.fallback(v.nullable(v.string()), null);

const stateOf = (published: number | undefined, draft: boolean | undefined) =>
  published === undefined
    ? draft === true
      ? "draft"
      : ("new" satisfies DefinitionState)
    : "published";

const definitionRowOf = (
  definition: WorkflowDefinition,
): DefinitionListRow => ({
  id: definition.id,
  name: definition.name,
  slug: definition.slug,
  state: stateOf(definition.published, definition.draft),
  published: definition.published ?? null,
  updatedAt: definition.updatedAt.epochMilliseconds,
});

/**
 * One page of the tenant's definitions. The block's `definitions.page`
 * searches, filters by state, sorts and pages in the database, and `facets`
 * counts the states under the same search.
 */
export function queryDefinitions(
  supabase: RpcClient,
  tenant: string,
  query: RecordListUrlQuery,
): Promise<RecordListPage<DefinitionListRow>> {
  return pageEntityRows({
    pager: organizationPager(tenant, builderFor(supabase).definitions),
    map: {
      sorts: {
        updated: { by: "updatedAt", direction: "desc" },
        name: { by: "name", direction: "asc" },
      },
    },
    query,
    pageSize: DEFINITIONS_PAGE,
    rowsOf: (items) => items.map(definitionRowOf),
  });
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
 * status, the definitions (`definitionId`, in the database), a mode and a
 * creation cursor; the search, several statuses and the time window are applied
 * here while scanning up to 500 runs. The cursor is the creation time of the
 * last row.
 */
export async function queryRuns(
  supabase: RpcClient,
  tenant: string,
  query: RecordListUrlQuery,
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

    if (definitions !== undefined) {
      filter.definitionId = definitions;
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

/**
 * The tenant's definitions by id, for run names and the definition facet: up to
 * `NAME_PAGES` pages of `NAME_PAGE`, by name.
 */
export async function definitionNames(
  supabase: RpcClient,
  tenant: string,
): Promise<ReadonlyMap<string, string>> {
  const pager = organizationPager(tenant, builderFor(supabase).definitions);
  const names = new Map<string, string>();

  let after: readonly string[] | undefined;

  for (let round = 0; round < NAME_PAGES; round += 1) {
    const options: Mutable<PageOptions> = {
      limit: NAME_PAGE,
      sort: { by: "name", direction: "asc" },
    };

    if (after !== undefined) {
      options.after = after;
    }

    const page = await pager.page(options).orThrow();

    for (const definition of page.items) {
      names.set(definition.id, definition.name);
    }

    if (!page.hasMore || page.nextCursor === null) {
      break;
    }

    after = page.nextCursor;
  }

  return names;
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
