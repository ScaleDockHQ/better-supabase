import * as v from "valibot";

/** The saved views list the task screens share. */
export const TASK_LIST = "tasks";

/** The subject type `appTables.tasks.subject` registers. */
export const TASK_SUBJECT = "task";

/** The subject type `appTables.projects.subject` registers. */
export const PROJECT_SUBJECT = "project";

export const TASK_STATUSES = ["todo", "doing", "done"] as const;

export const TaskStatusSchema = v.picklist(TASK_STATUSES);

export type TaskStatus = v.InferOutput<typeof TaskStatusSchema>;

/** The screens over the same tasks; each one is a saved view kind. */
export const TASK_VIEWS = [
  "table",
  "board",
  "calendar",
  "timeline",
  "gantt",
] as const;

export type TaskView = (typeof TASK_VIEWS)[number];

export interface TaskRow {
  readonly id: string;
  readonly title: string;
  readonly status: TaskStatus;
  /** `YYYY-MM-DD`, or null when unscheduled. */
  readonly startsOn: string | null;
  readonly dueOn: string | null;
  readonly assigneeId: string | null;
  readonly projectId: string;
  readonly rank: string;
}

export interface ProjectOption {
  readonly id: string;
  readonly name: string;
}

export interface MemberOption {
  readonly userId: string;
  readonly name: string;
}

export interface TaskQuery {
  readonly view: TaskView;
  readonly q: string;
  readonly status: TaskStatus | null;
  readonly projectId: string | null;
}

export interface TaskViewOption {
  readonly id: string;
  readonly name: string;
  readonly query: TaskQuery;
}

/** One URL search param as Next.js passes it. */
export type SearchParam = string | string[] | undefined;

const one = (value: SearchParam): string | undefined =>
  Array.isArray(value) ? value[0] : value;

const ProjectIdParam = v.pipe(v.string(), v.uuid());

/** The task query from the URL; unknown values fall back to the defaults. */
export function parseTaskQuery(
  params: Readonly<Record<string, SearchParam>>,
): TaskQuery {
  const view = v.safeParse(v.picklist(TASK_VIEWS), one(params["view"]));
  const status = v.safeParse(TaskStatusSchema, one(params["status"]));
  const projectId = v.safeParse(ProjectIdParam, one(params["project"]));

  return {
    view: view.success ? view.output : "table",
    q: (one(params["q"]) ?? "").trim().slice(0, 200),
    status: status.success ? status.output : null,
    projectId: projectId.success ? projectId.output : null,
  };
}

/** The search string of a query, without the defaults. */
export function taskSearch(query: TaskQuery): string {
  const params = new URLSearchParams();

  if (query.view !== "table") {
    params.set("view", query.view);
  }

  if (query.q !== "") {
    params.set("q", query.q);
  }

  if (query.status !== null) {
    params.set("status", query.status);
  }

  if (query.projectId !== null) {
    params.set("project", query.projectId);
  }

  const search = params.toString();

  return search === "" ? "" : `?${search}`;
}
