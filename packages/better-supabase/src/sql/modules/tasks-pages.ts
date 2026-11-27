import type { BlockSqlContext } from "../context.ts";
import type { TaskNames } from "./tasks-functions.ts";

import {
  filterAny,
  filterFlag,
  filterSet,
  listBody,
  listDeclare,
  searchPattern,
} from "../list-template.ts";
import { fail, userGrant } from "../shared.ts";
import { asText } from "./over-app.ts";

/**
 * A project's progress: the share of its live items that are completed.
 * Canceled items are left out, and a project with no live items (none, or only
 * canceled ones) is null instead of dividing by zero.
 */
export function projectProgressSql(
  items: string,
  projectColumn: string,
  projectId: string,
  archivedAt: string,
  state: (value: string, labels: readonly string[], negate?: boolean) => string,
  stateColumn: string,
): string {
  const live = `count(*) filter (where ${state(stateColumn, ["canceled"], true)})`;

  return `(
      select case when count(*) = 0 then null else round(100.0 * count(*) filter (where ${state(stateColumn, ["completed"])}) / nullif(${live}, 0)) end
      from ${items} y where y.${projectColumn} = ${projectId} and y.${archivedAt} is null
    )`;
}

/** What the page functions read from the task function builder. */
interface PageHelpers {
  readonly w: (column: string) => string;
  readonly a: (column: string) => string;
  readonly p: (column: string) => string;
  readonly has: (logical: string) => boolean;
  readonly row: (alias: string) => string;
  readonly budgetText: string;
  readonly state: (
    value: string,
    labels: readonly string[],
    negate?: boolean,
  ) => string;
}

/**
 * The keyset page functions of the tasks block (ADR 1077): `page_tasks`, and
 * `page_projects` and `get_project` when the app has a projects table.
 */
export function taskPageSql(
  ctx: BlockSqlContext,
  n: TaskNames,
  h: PageHelpers,
): { readonly tasks: string; readonly projects: string } {
  const { fn, t } = n;
  const { w, a, p, has, row, budgetText, state } = h;

  const projectRow = (alias: string): string =>
    `${ctx.rowJson("projects", alias)}${budgetText.replaceAll("x.", `${alias}.`)} || jsonb_build_object('progress', ${
      has("project")
        ? projectProgressSql(
            t("items"),
            w("project"),
            `${alias}.${p("id")}`,
            w("archivedAt"),
            state,
            `y.${w("state")}`,
          )
        : "null"
    })`;

  const stateText = ctx.mapsValues("items", "state")
    ? ctx.label("items", "state", `x.${w("state")}`)
    : asText(ctx, "items", `x.${w("state")}`);

  const taskId = {
    expr: `x.${w("number")}`,
    dir: "desc",
    type: "bigint",
  } as const;

  const taskKey = { expr: `x.${w("id")}`, dir: "asc", type: "uuid" } as const;
  const taskKeys = [taskId, taskKey] as const;

  const taskPage = {
    name: "page_tasks",
    from: t("items"),
    alias: "x",
    where: [
      `x.${w("tenant")} = page_tasks.tenant`,
      `x.${w("archivedAt")} is null`,
      n.templates
        ? `(case coalesce(v_filters ->> 'templates', 'exclude') when 'include' then true when 'only' then x.${w("template")} is not null else x.${w("template")} is null end)`
        : "true",
      filterAny("state", stateText),
      filterAny("priority", `x.${w("priority")}::text`),
      filterAny("teamId", `x.${w("team")}`, "uuid"),
      has("project")
        ? filterAny("projectId", `x.${w("project")}`, "uuid")
        : `(not ${filterSet("projectId")})`,
      has("iteration")
        ? filterAny("iterationId", `x.${w("iteration")}`, "uuid")
        : `(not ${filterSet("iterationId")})`,
      filterAny("parentId", `x.${w("parent")}`, "uuid"),
      `(not ${filterSet("assigneeId")} or exists (select 1 from ${t("assignees")} y where y.${a("item")} = x.${w("id")} and ${filterAny("assigneeId", `y.${a("user")}`, "uuid")}))`,
      `(not ${filterFlag("open")} or x.${w("closedAt")} is null)`,
      has("waitingOn")
        ? `(not ${filterFlag("ready")} or (x.${w("waitingOn")} = 0 and x.${w("closedAt")} is null))`
        : `(not ${filterFlag("ready")} or x.${w("closedAt")} is null)`,
      has("waitingOn")
        ? `(not ${filterFlag("waiting")} or (x.${w("waitingOn")} > 0 and x.${w("closedAt")} is null))`
        : `(not ${filterFlag("waiting")})`,
      has("dueAt")
        ? `(v_filters ->> 'dueFrom' is null or x.${w("dueAt")} >= (v_filters ->> 'dueFrom')::timestamptz)`
        : `(v_filters ->> 'dueFrom' is null)`,
      has("dueAt")
        ? `(v_filters ->> 'dueTo' is null or x.${w("dueAt")} <= (v_filters ->> 'dueTo')::timestamptz)`
        : `(v_filters ->> 'dueTo' is null)`,
      `(v_filters ->> 'triage' is null or (v_filters ->> 'triage')::boolean = (x.${w("state")} = 'triage'))`,
      has("milestone")
        ? `(v_filters ->> 'milestoneId' is null or x.${w("milestone")} = (v_filters ->> 'milestoneId')::uuid)`
        : `(v_filters ->> 'milestoneId' is null)`,
      `(v_search is null or x.${w("title")} ilike v_search or x.${w("identifier")} ilike v_search)`,
    ],
    keys: taskKeys,
    sorts: {
      number: taskKeys,
      title: [
        { expr: `lower(x.${w("title")})`, dir: "asc", type: "text" },
        taskKey,
      ],
      dueAt: [
        {
          expr: has("dueAt")
            ? `coalesce(x.${w("dueAt")}, 'infinity'::timestamptz)`
            : `'infinity'::timestamptz`,
          dir: "asc",
          type: "timestamptz",
        },
        taskKey,
      ],
      createdAt: [
        {
          expr: has("createdAt")
            ? `x.${w("createdAt")}`
            : `'epoch'::timestamptz`,
          dir: "desc",
          type: "timestamptz",
        },
        taskKey,
      ],
    },
    facets: { state: stateText, priority: `x.${w("priority")}::text` },
    rowJson: row("x"),
    defaultLimit: 50,
    maxLimit: 200,
    invalid: (message: string) => fail("TASK_INVALID", message, "22023"),
  } as const;

  const projectKey = {
    expr: `x.${p("id")}`,
    dir: "asc",
    type: "uuid",
  } as const;

  const projectNameKeys = [
    { expr: `lower(x.${p("name")})`, dir: "asc", type: "text" },
    projectKey,
  ] as const;

  const projectPage = () =>
    ({
      name: "page_projects",
      from: t("projects"),
      alias: "x",
      where: [
        `x.${p("tenant")} = page_projects.tenant`,
        filterAny("status", `x.${p("status")}::text`),
        filterAny(
          "ownerId",
          ctx.has("projects", "owner") ? `x.${p("owner")}` : "null::uuid",
          "uuid",
        ),
        `(${filterFlag("archived")} or x.${p("archivedAt")} is null)`,
        `(v_search is null or x.${p("name")} ilike v_search or x.${p("key")} ilike v_search)`,
      ],
      keys: projectNameKeys,
      sorts: {
        name: projectNameKeys,
        key: [{ expr: `x.${p("key")}`, dir: "asc", type: "text" }, projectKey],
        createdAt: [
          { expr: `x.${p("createdAt")}`, dir: "desc", type: "timestamptz" },
          projectKey,
        ],
      },
      facets: { status: `x.${p("status")}::text` },
      rowJson: projectRow("x"),
      defaultLimit: 50,
      maxLimit: 200,
      invalid: (message: string) =>
        fail("TASK_PROJECT_INVALID", message, "22023"),
    }) as const;

  const projects = ctx.hasTable("projects")
    ? `
-- A tenant's projects as a keyset page, by name (ADR 1077). It runs as
-- invoker. filters is { status, ownerId (each a value or a list), archived
-- (true adds archived ones), search (name, key), sort (name, key, createdAt),
-- direction, facet, count, limit, after, offset, paged, total, totalCap }.
create or replace function ${fn("page_projects")}(tenant ${ctx.idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_projects.filters, '{}'::jsonb);
  v_search text := ${searchPattern()};
  ${listDeclare(projectPage())}
begin
  ${listBody(projectPage())}
end;
$$;
${userGrant(`${fn("page_projects")}(${ctx.idType}, jsonb)`)}

-- One project the caller can read, or null.
create or replace function ${fn("get_project")}(project uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${projectRow("x")} from ${t("projects")} x where x.${p("id")} = get_project.project
$$;
${userGrant(`${fn("get_project")}(uuid)`)}
`
    : "";

  return {
    tasks: `
-- A tenant's active items as a keyset page, newest number first (ADR 1077). It
-- runs as invoker, so the read policy decides which items are visible. filters
-- is { state, priority, teamId, projectId, iterationId, parentId, assigneeId
-- (each a value or a list), open (true keeps unclosed items), dueFrom, dueTo,
-- templates
-- (include, only), search (title, identifier), sort (number, title, dueAt,
-- createdAt), direction, facet, count, limit, after, offset, paged, total,
-- totalCap }.
create or replace function ${fn("page_tasks")}(tenant ${ctx.idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_tasks.filters, '{}'::jsonb);
  v_search text := ${searchPattern()};
  ${listDeclare(taskPage)}
begin
  ${listBody(taskPage)}
end;
$$;
${userGrant(`${fn("page_tasks")}(${ctx.idType}, jsonb)`)}`,
    projects,
  };
}
