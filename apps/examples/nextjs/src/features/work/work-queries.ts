import "server-only";
import type { WorkItemListOptions } from "better-supabase/blocks/tasks";

import { tenantOf } from "better-supabase/next";
import { unstable_rethrow } from "next/navigation";

import { getMembers } from "@/features/organization/organization-queries";
import { bsb } from "@/lib/supabase/server";

import type {
  MemberOption,
  SavedViewOption,
  StageColumn,
  TeamOption,
  WorkGridQuery,
  WorkItemRow,
} from "./work-types";

import {
  WORK_ITEM_LIST,
  WORK_ITEM_STATES,
  WORK_ITEM_SUBJECT,
  parseWorkGridQuery,
  toWorkItemRow,
} from "./work-types";

const PAGE_SIZE = 200;

type Writable<T> = { -readonly [K in keyof T]: T[K] };

/** A loaded region: its data, no active organization, or a failed read. */
export type Loaded<T> =
  | { readonly kind: "ok"; readonly data: T }
  | { readonly kind: "no-organization" }
  | { readonly kind: "error" };

/**
 * Runs a cached loader. A failed read throws inside the loader, so it is never
 * cached and Retry reads again.
 */
export async function settle<T>(
  load: () => Promise<T | null>,
): Promise<Loaded<T>> {
  try {
    const data = await load();

    return data === null ? { kind: "no-organization" } : { kind: "ok", data };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}

export interface WorkBoardData {
  readonly stages: readonly StageColumn[];
  readonly items: readonly WorkItemRow[];
}

/**
 * The stages of the organization's default work item pipeline and the items on
 * it. No pipeline yet means no items: creating the first item seeds one. Throws
 * on a failed read, so the private cache never keeps an error.
 */
export async function getWorkBoard(
  teamId: string | null,
): Promise<WorkBoardData | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const {
    pipelines,
    $blocks: { tasks: workItems },
  } = db;

  const options: Writable<WorkItemListOptions> = { limit: PAGE_SIZE };

  if (teamId !== null) {
    options.teamId = teamId;
  }

  const [pipelineList, itemList] = await Promise.all([
    pipelines
      .list({ organizationId: tenant, subjectType: WORK_ITEM_SUBJECT })
      .orThrow(),
    workItems.list({ organizationId: tenant, ...options }).orThrow(),
  ]);

  const pipeline =
    pipelineList.find((each) => each.isDefault) ?? pipelineList[0];

  return {
    stages: (pipeline?.stages ?? []).map((stage) => ({
      id: stage.id,
      name: stage.name,
      category: stage.category,
      wipLimit: stage.wipLimit ?? null,
    })),
    items: itemList.map(toWorkItemRow),
  };
}

/** The organization's teams, for the team picker. */
export async function getTeams(): Promise<readonly TeamOption[] | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const teams = await db.teams.list(tenant).orThrow();

  return teams
    .map((team) => ({ id: team.id, name: team.name }))
    .toSorted((a, b) => a.name.localeCompare(b.name));
}

/** The members work can be assigned to. */
export async function getAssignees(
  organizationId: string,
): Promise<readonly MemberOption[]> {
  const members = await getMembers(organizationId);

  return members.map((member) => ({
    userId: member.userId,
    name: member.name ?? member.email ?? member.userId,
  }));
}

const STATE_ORDER = new Map<string, number>(
  WORK_ITEM_STATES.map((state, index) => [state, index]),
);

function sortRows(
  rows: readonly WorkItemRow[],
  sort: WorkGridQuery["sort"],
): readonly WorkItemRow[] {
  switch (sort) {
    case "newest": {
      return rows;
    }

    case "title": {
      return rows.toSorted((a, b) => a.title.localeCompare(b.title));
    }

    case "priority": {
      // 0 means no priority, so it sorts after 4 (low).
      const weight = (row: WorkItemRow) =>
        row.priority === 0 ? 5 : row.priority;

      return rows.toSorted((a, b) => weight(a) - weight(b));
    }

    case "state": {
      return rows.toSorted(
        (a, b) =>
          (STATE_ORDER.get(a.state) ?? 0) - (STATE_ORDER.get(b.state) ?? 0),
      );
    }

    default: {
      const unknown: never = sort;

      return unknown;
    }
  }
}

export interface WorkGridData {
  readonly rows: readonly WorkItemRow[];
  readonly stages: readonly StageColumn[];
}

/** The items the grid shows for a query, filtered in SQL and sorted here. */
export async function getWorkGrid(
  query: WorkGridQuery,
): Promise<WorkGridData | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const {
    pipelines,
    $blocks: { tasks: workItems },
  } = db;

  const options: Writable<WorkItemListOptions> = { limit: PAGE_SIZE };

  if (query.q !== "") {
    options.search = query.q;
  }

  if (query.state !== null) {
    options.states = [query.state];
  }

  const [pipelineList, items] = await Promise.all([
    pipelines
      .list({ organizationId: tenant, subjectType: WORK_ITEM_SUBJECT })
      .orThrow(),
    workItems.list({ organizationId: tenant, ...options }).orThrow(),
  ]);

  const pipeline =
    pipelineList.find((each) => each.isDefault) ?? pipelineList[0];

  return {
    rows: sortRows(items.map(toWorkItemRow), query.sort),
    stages: (pipeline?.stages ?? []).map((stage) => ({
      id: stage.id,
      name: stage.name,
      category: stage.category,
      wipLimit: stage.wipLimit ?? null,
    })),
  };
}

/** The caller's saved views of the grid, in rank order. */
export async function getWorkViews(): Promise<
  readonly SavedViewOption[] | null
> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const views = await db.$blocks.savedViews
    .list({ organizationId: tenant, list: WORK_ITEM_LIST })
    .orThrow();

  return views.map((view) => {
    const query = view.state.query ?? {};
    const state = query.facets?.["state"]?.[0];

    return {
      id: view.id,
      name: view.name,
      query: parseWorkGridQuery({ q: query.q, sort: query.sort, state }),
    };
  });
}
