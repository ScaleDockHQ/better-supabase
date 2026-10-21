import "server-only";
import type { JsonValue } from "better-supabase/blocks/versions";

import { tenantOf } from "better-supabase/next";
import { unstable_rethrow } from "next/navigation";
import * as v from "valibot";

import { getMembers } from "@/features/organization/organization-queries";
import { blocks } from "@/lib/blocks";
import { bs } from "@/lib/supabase/server";

import type {
  MemberOption,
  ProjectHistoryField,
  ProjectOption,
  ProjectVersion,
  TaskQuery,
  TaskRow,
  TaskStatus,
  TaskViewOption,
} from "./project-types";

import {
  PROJECT_HISTORY_FIELDS,
  PROJECT_SUBJECT,
  TASK_LIST,
  parseTaskQuery,
} from "./project-types";

const TASK_LIMIT = 500;

/** The filters of a task query as a repository `where`. */
interface TaskWhere {
  title?: { contains: string };
  status?: { eq: TaskStatus };
  projectId?: { eq: string };
}

function taskWhere(
  query: Pick<TaskQuery, "q" | "status" | "projectId">,
): TaskWhere {
  const where: TaskWhere = {};

  if (query.q !== "") {
    where.title = { contains: query.q };
  }

  if (query.status !== null) {
    where.status = { eq: query.status };
  }

  if (query.projectId !== null) {
    where.projectId = { eq: query.projectId };
  }

  return where;
}

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

const TASK_COLUMNS = [
  "id",
  "title",
  "status",
  "startsOn",
  "dueOn",
  "assigneeId",
  "projectId",
  "rank",
] as const;

/** The tasks for a query, in rank order, so every screen agrees on the order. */
export async function getTasks(
  query: Pick<TaskQuery, "q" | "status" | "projectId">,
): Promise<readonly TaskRow[] | null> {
  "use cache: private";
  const { session, db } = await bs.cached();

  if (!tenantOf(session)) {
    return null;
  }

  const tasks = await db.tasks
    .findMany({
      select: [...TASK_COLUMNS],
      where: taskWhere(query),
      orderBy: { rank: "asc" },
      limit: TASK_LIMIT,
    })
    .orThrow();

  return tasks;
}

/** The organization's projects that aren't in the trash, by name. */
export async function getProjectOptions(): Promise<
  readonly ProjectOption[] | null
> {
  "use cache: private";
  const { session, db } = await bs.cached();

  if (!tenantOf(session)) {
    return null;
  }

  return db.projects
    .findMany({
      select: ["id", "name"],
      where: { deletedAt: { isNull: true } },
      orderBy: { name: "asc" },
      limit: TASK_LIMIT,
    })
    .orThrow();
}

export interface ProjectRecord {
  readonly id: string;
  readonly name: string;
  readonly budgetMinor: bigint;
  readonly currency: string;
  readonly leadId: string | null;
  readonly createdAt: string;
}

/** One project, or `undefined` when it doesn't exist or is in the trash. */
export async function getProject(
  id: string,
): Promise<ProjectRecord | undefined | null> {
  "use cache: private";
  const { session, db } = await bs.cached();

  if (!tenantOf(session)) {
    return null;
  }

  const project = await db.projects
    .findFirst({
      select: ["id", "name", "budgetMinor", "currency", "leadId", "createdAt"],
      where: { id: { eq: id }, deletedAt: { isNull: true } },
    })
    .orThrow();

  return project ?? undefined;
}

const HISTORY_LIMIT = 10;

const Cell = v.optional(
  v.nullable(v.union([v.string(), v.pipe(v.number(), v.transform(String))])),
);

/** A version's content: the columns `subject.versions` keeps. */
const HistoryContent = v.fallback(
  v.object({ name: Cell, budget_minor: Cell, currency: Cell }),
  {},
);

function historyFields(
  content: JsonValue | undefined,
): ProjectVersion["fields"] {
  const parsed = v.parse(HistoryContent, content);
  const fields: Partial<Record<ProjectHistoryField, string>> = {};

  for (const field of PROJECT_HISTORY_FIELDS) {
    const value = parsed[field];

    if (value !== null && value !== undefined) {
      fields[field] = value;
    }
  }

  return fields;
}

/**
 * The project's latest versions with their content, newest first. The versions
 * block keeps one on every change to the configured columns.
 */
export async function getProjectHistory(
  projectId: string,
): Promise<readonly ProjectVersion[] | null> {
  "use cache: private";
  const { session, supabase } = await bs.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const { versions } = blocks(supabase, tenant);

  const listed = await versions
    .list({ type: PROJECT_SUBJECT, id: projectId }, { pageSize: HISTORY_LIMIT })
    .orThrow();

  const loaded = await Promise.all(
    listed.map((version) => versions.get(version.id).orThrow()),
  );

  return loaded.map((version) => ({
    id: version.id,
    number: version.number,
    source: version.source,
    createdAt: version.createdAt.epochMilliseconds,
    fields: historyFields(version.content),
  }));
}

export async function getMemberOptions(
  organizationId: string,
): Promise<readonly MemberOption[]> {
  const members = await getMembers(organizationId);

  return members.map((member) => ({
    userId: member.userId,
    name: member.name ?? member.email ?? member.userId,
  }));
}

/** The caller's saved views of the tasks, in rank order. */
export async function getTaskViews(): Promise<
  readonly TaskViewOption[] | null
> {
  "use cache: private";
  const { session, supabase } = await bs.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const views = await blocks(supabase)
    .savedViews.list(tenant, TASK_LIST)
    .orThrow();

  return views.map((view) => {
    const query = view.state.query ?? {};

    return {
      id: view.id,
      name: view.name,
      query: parseTaskQuery({
        view: view.kind,
        q: query.q,
        status: query.facets?.["status"]?.[0],
        project: query.facets?.["project"]?.[0],
      }),
    };
  });
}
