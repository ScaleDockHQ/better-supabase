import type { AsyncResult } from "../../core/result.ts";
import type { BlockContext } from "../create-blocks.ts";
import type { ProjectOverview, ProjectPageParts } from "./overview.ts";
import type { ProjectFinancials } from "./projects.ts";

import { AsyncResult as Async, ok } from "../../core/result.ts";
import { blockCall } from "../shared.ts";
import { projectPageReads } from "./overview.ts";

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isList(value: unknown): value is readonly unknown[] {
  return Array.isArray(value);
}

function firstRecord(value: unknown): Record<string, unknown> | undefined {
  if (!isList(value)) {
    return undefined;
  }

  const item = value[0];

  return isRecord(item) ? item : undefined;
}

/** True when `target` is a later calendar day than `start`. */
function dateAfter(
  target: Temporal.PlainDate | undefined,
  start: Temporal.PlainDate | undefined,
): boolean {
  return (
    target !== undefined &&
    start !== undefined &&
    Temporal.PlainDate.compare(target, start) > 0
  );
}

/** The page reads and the glue calls, in their own chunk (ADR 1262). */
export function projectPage(
  options: Pick<BlockContext, "tenant" | "transport" | "schema" | "mappers"> & {
    readonly parts: ProjectPageParts;
  },
  financials: (input: {
    projectId: string;
    subjectType?: string;
  }) => AsyncResult<ProjectFinancials>,
): Pick<
  {
    overview: ReturnType<typeof projectPageReads>["overview"];
    cards: ReturnType<typeof projectPageReads>["cards"];
    views: ReturnType<typeof projectPageReads>["views"];
    postUpdate(input: {
      organizationId: string;
      projectId: string;
      health: "on_track" | "at_risk" | "off_track";
      body: string;
    }): AsyncResult<Readonly<Record<string, unknown>>>;
    dependencies(input: {
      projectId: string;
      subjectType?: string;
    }): AsyncResult<
      readonly {
        readonly direction: "in" | "out";
        readonly projectId: string;
        readonly violated: boolean;
      }[]
    >;
    saveInitiative(input: {
      organizationId: string;
      initiativeId?: string;
      name: string;
      description?: string;
      status?: string;
      priority?: number;
      ownerId?: string;
      targetOn?: string;
      parentId?: string;
    }): AsyncResult<Readonly<Record<string, unknown>>>;
    pageInitiatives(
      organizationId: string,
    ): AsyncResult<readonly Record<string, unknown>[]>;
    linkInitiative(
      initiativeId: string,
      projectId: string,
    ): AsyncResult<boolean>;
  },
  | "overview"
  | "cards"
  | "views"
  | "postUpdate"
  | "dependencies"
  | "saveInitiative"
  | "pageInitiatives"
  | "linkInitiative"
> {
  const call = blockCall(options.transport, options.schema, options.mappers);

  const latestUpdate = (
    projectId: string,
  ): AsyncResult<ProjectOverview["update"]> =>
    call("page_project_updates", { project: projectId }, (value) => {
      const row = firstRecord(value);

      if (row === undefined || typeof row["id"] !== "string") {
        return null;
      }

      return {
        id: row["id"],
        health: typeof row["health"] === "string" ? row["health"] : "",
        body: typeof row["body"] === "string" ? row["body"] : "",
      };
    });

  const page = projectPageReads({
    tenant: options.tenant,
    parts: options.parts,
    financials,
    latestUpdate,
  });

  return {
    overview: (input) => page.overview(input),
    cards: (input) => page.cards(input),
    views: (projectId) => page.views(projectId),
    postUpdate: (input) =>
      call(
        "save_project_update",
        {
          tenant: input.organizationId,
          project: input.projectId,
          health: input.health,
          body: input.body,
        },
        (value) => (isRecord(value) ? value : {}),
      ),
    dependencies: ({ projectId, subjectType = "project" }) =>
      options.parts.relations
        .of({ subject: { type: subjectType, id: projectId }, kind: "blocks" })
        .andThen((links) =>
          Async.from(async () => {
            const self = await options.parts.tasks.getProject(projectId);

            if (!self.ok) {
              return self;
            }

            const rows: {
              direction: "in" | "out";
              projectId: string;
              violated: boolean;
            }[] = [];

            for (const link of links) {
              const other = await options.parts.tasks.getProject(
                link.subject.id,
              );

              if (!other.ok) {
                return other;
              }

              const blocker = link.direction === "in" ? other.data : self.data;

              const dependent =
                link.direction === "in" ? self.data : other.data;

              rows.push({
                direction: link.direction,
                projectId: other.data.id,
                violated: dateAfter(blocker.targetOn, dependent.startOn),
              });
            }

            return ok(rows);
          }),
        ),
    saveInitiative: (input) =>
      call(
        "save_initiative",
        {
          tenant: input.organizationId,
          id: input.initiativeId ?? null,
          attrs: {
            name: input.name,
            description: input.description ?? null,
            status: input.status ?? null,
            priority: input.priority ?? null,
            ownerId: input.ownerId ?? null,
            targetOn: input.targetOn ?? null,
            parentId: input.parentId ?? null,
          },
        },
        (value) => (isRecord(value) ? value : {}),
      ),
    pageInitiatives: (organizationId) =>
      call("page_initiatives", { tenant: organizationId }, (value) =>
        (Array.isArray(value) ? value : []).flatMap((row) =>
          isRecord(row) ? [row] : [],
        ),
      ),
    linkInitiative: (initiativeId, projectId) =>
      call(
        "link_initiative_project",
        { initiative: initiativeId, project: projectId },
        (value) => value === true,
      ),
  };
}
