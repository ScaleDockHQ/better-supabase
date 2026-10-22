import type { WorkItem, WorkItemState } from "better-supabase/blocks/tasks";

import * as v from "valibot";

export const WORK_ITEM_SUBJECT = "work_item";

/** The list key the grid's saved views are stored under. */
export const WORK_ITEM_LIST = "work_items";

export const WORK_ITEM_STATES = [
  "triage",
  "backlog",
  "unstarted",
  "started",
  "completed",
  "canceled",
] as const satisfies readonly WorkItemState[];

export const WorkItemStateSchema = v.picklist(WORK_ITEM_STATES);

export const WORK_ITEM_SORTS = [
  "newest",
  "title",
  "priority",
  "state",
] as const;

export type WorkItemSort = (typeof WORK_ITEM_SORTS)[number];

export const WorkItemSortSchema = v.picklist(WORK_ITEM_SORTS);

/** A work item as the client components get it: plain JSON, no Temporal. */
export interface WorkItemRow {
  readonly id: string;
  readonly identifier: string;
  readonly title: string;
  readonly state: WorkItemState;
  readonly stageId: string | null;
  readonly teamId: string | null;
  readonly priority: number;
  readonly rank: string;
  readonly assigneeIds: readonly string[];
  readonly createdAt: string;
}

export interface StageColumn {
  readonly id: string;
  readonly name: string;
  readonly category: string;
  readonly wipLimit: number | null;
}

export interface TeamOption {
  readonly id: string;
  readonly name: string;
}

export interface MemberOption {
  readonly userId: string;
  readonly name: string;
}

/** The grid's filters and sort, read from the URL and stored in saved views. */
export interface WorkGridQuery {
  readonly q: string;
  readonly state: WorkItemState | null;
  readonly sort: WorkItemSort;
}

export interface SavedViewOption {
  readonly id: string;
  readonly name: string;
  readonly query: WorkGridQuery;
}

export function toWorkItemRow(item: WorkItem): WorkItemRow {
  return {
    id: item.id,
    identifier: item.identifier,
    title: item.title,
    state: item.state,
    stageId: item.stageId ?? null,
    teamId: item.teamId ?? null,
    priority: item.priority,
    rank: item.rank,
    assigneeIds: item.assigneeIds,
    createdAt: item.createdAt.toString(),
  };
}

/** The grid query from URL search params, falling back on bad values. */
export function parseWorkGridQuery(
  params: Readonly<Record<string, string | string[] | undefined>>,
): WorkGridQuery {
  const one = (key: string): string | undefined => {
    const value = params[key];

    return Array.isArray(value) ? value[0] : value;
  };

  const state = v.safeParse(WorkItemStateSchema, one("state"));
  const sort = v.safeParse(WorkItemSortSchema, one("sort"));

  return {
    q: one("q")?.trim() ?? "",
    state: state.success ? state.output : null,
    sort: sort.success ? sort.output : "newest",
  };
}

/** The URL search string for a grid query, leaving out defaults. */
export function workGridSearch(query: WorkGridQuery): string {
  const params = new URLSearchParams();

  if (query.q !== "") {
    params.set("q", query.q);
  }

  if (query.state !== null) {
    params.set("state", query.state);
  }

  if (query.sort !== "newest") {
    params.set("sort", query.sort);
  }

  const search = params.toString();

  return search === "" ? "" : `?${search}`;
}
