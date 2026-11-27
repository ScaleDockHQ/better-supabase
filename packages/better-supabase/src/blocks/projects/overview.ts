import type { FacetResult } from "../../core/block-helpers.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { RecordRef } from "../../schema/types.ts";
import type { ValueOf } from "../read-all.ts";
import type { Relation } from "../relations/relations.ts";
import type { SubjectMember } from "../subjects/members.ts";
import type { Tag } from "../tags/tags.ts";
import type { Project, Task } from "../tasks/tasks.ts";
import type { ActivityEntry } from "../timeline/timeline.ts";
import type { ProjectFinancials } from "./projects.ts";

import { requireTenant } from "../../core/block-tenant.ts";
import { AsyncResult as Async, ok } from "../../core/result.ts";

/** One task's card counts for a board or a list. */
export interface ProjectCard {
  readonly comments: number;
  readonly tags: readonly Tag[];
  readonly attachments: number;
  readonly subtasks:
    | { readonly done: number; readonly total: number }
    | undefined;
}

/** What `projects.overview` returns for one project. */
export interface ProjectOverview {
  readonly project: Project;
  readonly members: readonly SubjectMember[];
  readonly milestones: readonly {
    readonly id: string;
    readonly name: string;
  }[];
  /** The latest posted update, or null when the project has none. */
  readonly update: {
    readonly id: string;
    readonly health: string;
    readonly body: string;
  } | null;
  readonly health: Project["health"];
  readonly tasks: Readonly<Record<string, number>>;
  readonly financials: ProjectFinancials;
  readonly blockedBy: readonly RecordRef[];
  readonly blocking: readonly RecordRef[];
  readonly files: number;
  readonly activity: readonly ActivityEntry[];
  readonly views: readonly { readonly id: string; readonly name: string }[];
}

/** The part clients `overview`, `cards` and `views` call. */
export interface ProjectPageParts {
  readonly tasks: {
    getProject(projectId: string): AsyncResult<Project>;
    facets(options: {
      organizationId: string;
      filters?: { readonly projectId?: readonly string[] };
    }): AsyncResult<readonly FacetResult[]>;
    getTask(taskId: string): AsyncResult<Task>;
    pageMilestones(
      projectId: string,
    ): AsyncResult<readonly { readonly id: string; readonly name: string }[]>;
  };
  readonly comments: {
    counts(
      subjects: readonly RecordRef[],
    ): AsyncResult<Readonly<Record<string, number>>>;
  };
  readonly attachments: {
    counts(input: {
      type: string;
      ids: readonly string[];
    }): AsyncResult<Readonly<Record<string, number>>>;
  };
  readonly tags: {
    forSubjects(input: {
      type: string;
      ids: readonly string[];
    }): AsyncResult<Readonly<Record<string, readonly Tag[]>>>;
  };
  readonly timeline: {
    list(input: {
      subject: RecordRef;
      limit?: number;
    }): AsyncResult<readonly ActivityEntry[]>;
  };
  readonly relations: {
    of(input: {
      subject: RecordRef;
      kind?: string;
    }): AsyncResult<readonly Relation[]>;
  };
  readonly "saved-views": {
    page(options: {
      organizationId: string;
      filters?: { readonly list?: readonly string[] };
    }): AsyncResult<{
      readonly items: readonly { id: string; name: string }[];
    }>;
  };
  readonly subjects: {
    readonly members: {
      list(subject: RecordRef): AsyncResult<readonly SubjectMember[]>;
    };
  };
}

/** The reads a project page makes, over the composite's parts. */
export function projectPageReads(input: {
  readonly tenant: Parameters<typeof requireTenant>[0];
  readonly parts: ProjectPageParts;
  readonly financials: (input: {
    projectId: string;
    subjectType: string;
  }) => AsyncResult<ProjectFinancials>;
  readonly latestUpdate: (
    projectId: string,
  ) => AsyncResult<ProjectOverview["update"]>;
}): {
  overview(input: {
    organizationId: string;
    projectId: string;
    /** The project subject's type. Default: `project`. */
    subjectType?: string;
  }): AsyncResult<ProjectOverview>;
  cards(input: {
    organizationId: string;
    taskIds: readonly string[];
    /** The task subject's type. Default: `task`. */
    subjectType?: string;
  }): AsyncResult<Readonly<Record<string, ProjectCard>>>;
  views(
    projectId: string,
  ): AsyncResult<
    ValueOf<ReturnType<ProjectPageParts["saved-views"]["page"]>>["items"]
  >;
} {
  const { parts, financials, latestUpdate } = input;
  const tenant = (): AsyncResult<string> => requireTenant(input.tenant);

  return {
    overview: ({ organizationId, projectId, subjectType = "project" }) =>
      Async.from(async () => {
        const subject: RecordRef = { type: subjectType, id: projectId };

        const [
          project,
          facets,
          members,
          links,
          files,
          activity,
          views,
          money,
          milestones,
          update,
        ] = await Promise.all([
          parts.tasks.getProject(projectId),
          parts.tasks.facets({
            organizationId,
            filters: { projectId: [projectId] },
          }),
          parts.subjects.members.list(subject),
          parts.relations.of({ subject, kind: "blocks" }),
          parts.attachments.counts({ type: subjectType, ids: [projectId] }),
          parts.timeline.list({ subject, limit: 20 }),
          parts["saved-views"].page({
            organizationId,
            filters: { list: [`project:${projectId}`] },
          }),
          financials({ projectId, subjectType }),
          parts.tasks.pageMilestones(projectId),
          latestUpdate(projectId),
        ]);

        if (!project.ok) {
          return project;
        }

        if (!facets.ok) {
          return facets;
        }

        if (!members.ok) {
          return members;
        }

        if (!links.ok) {
          return links;
        }

        if (!files.ok) {
          return files;
        }

        if (!activity.ok) {
          return activity;
        }

        if (!views.ok) {
          return views;
        }

        if (!money.ok) {
          return money;
        }

        if (!milestones.ok) {
          return milestones;
        }

        if (!update.ok) {
          return update;
        }

        const state = facets.data.find((facet) => facet.facet === "state");

        return ok({
          project: project.data,
          members: members.data,
          milestones: milestones.data,
          update: update.data,
          health: project.data.health,
          tasks: Object.fromEntries(
            (state?.values ?? []).map((value) => [
              value.value,
              value.count.value,
            ]),
          ),
          financials: money.data,
          blockedBy: links.data
            .filter((link) => link.direction === "in")
            .map((link) => link.subject),
          blocking: links.data
            .filter((link) => link.direction === "out")
            .map((link) => link.subject),
          files: files.data[projectId] ?? 0,
          activity: activity.data,
          views: views.data.items,
        });
      }),
    cards: ({ taskIds, subjectType = "task" }) =>
      Async.from(async () => {
        if (taskIds.length === 0) {
          return ok({});
        }

        const subjects = taskIds.map((id): RecordRef => ({
          type: subjectType,
          id,
        }));

        const [comments, tags, files, tasks] = await Promise.all([
          parts.comments.counts(subjects),
          parts.tags.forSubjects({ type: subjectType, ids: taskIds }),
          parts.attachments.counts({ type: subjectType, ids: taskIds }),
          Promise.all(taskIds.map((id) => parts.tasks.getTask(id))),
        ]);

        if (!comments.ok) {
          return comments;
        }

        if (!tags.ok) {
          return tags;
        }

        if (!files.ok) {
          return files;
        }

        const byId = new Map<string, Task>();

        for (const task of tasks) {
          if (!task.ok) {
            return task;
          }

          byId.set(task.data.id, task.data);
        }

        return ok(
          Object.fromEntries(
            taskIds.map((id) => [
              id,
              {
                comments: comments.data[id] ?? 0,
                tags: tags.data[id] ?? [],
                attachments: files.data[id] ?? 0,
                subtasks: byId.get(id)?.subtasks,
              },
            ]),
          ),
        );
      }),
    views: (projectId) =>
      tenant().andThen((organizationId) =>
        parts["saved-views"]
          .page({ organizationId, filters: { list: [`project:${projectId}`] } })
          .map((page) => page.items),
      ),
  };
}
