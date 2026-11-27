import type { TaskEventData } from "../../core/block-events.ts";
import type { Events } from "../../core/event-map.ts";

import { defineEvents, event } from "../../core/event-map.ts";

/** A project event. `subjectType` is `project` unless the app renamed it. */
export interface ProjectEventData {
  readonly organizationId: string;
  readonly projectId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly key: string;
  readonly name: string;
  readonly actorId?: string | null;
  readonly actorKind?: string;
  readonly actorName?: string | null;
}

/** A milestone event. The project fields name the milestone's project. */
export interface MilestoneEventData extends ProjectEventData {
  readonly milestoneId: string;
}

/** An iteration event. */
export interface IterationEventData {
  readonly organizationId: string;
  readonly iterationId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly name: string;
  readonly actorId?: string | null;
  readonly actorKind?: string;
  readonly actorName?: string | null;
}

/** The events of the `tasks` block: type to data. */
export type TasksEvents = {
  readonly "task.created": TaskEventData;
  readonly "task.updated": TaskEventData;
  readonly "task.assigned": TaskEventData;
  readonly "task.closed": TaskEventData;
  readonly "task.reopened": TaskEventData;
  readonly "task.archived": TaskEventData;
  readonly "task.restored": TaskEventData;
  readonly "task.deleted": TaskEventData;
  readonly "task.unblocked": TaskEventData;
  readonly "task.claimed": TaskEventData;
  readonly "task.released": TaskEventData;
  readonly "task.claim_expired": TaskEventData;
  readonly "task.failed": TaskEventData;
  readonly "task.delegated": TaskEventData;
  readonly "task.held": TaskEventData;
  readonly "task.hold_released": TaskEventData;
  readonly "project.created": ProjectEventData;
  readonly "project.updated": ProjectEventData;
  readonly "project.archived": ProjectEventData;
  readonly "project.restored": ProjectEventData;
  readonly "project.deleted": ProjectEventData;
  readonly "iteration.created": IterationEventData;
  readonly "iteration.updated": IterationEventData;
  readonly "iteration.deleted": IterationEventData;
  readonly "iteration.started": IterationEventData;
  readonly "iteration.completed": IterationEventData;
  readonly "project_milestone.created": MilestoneEventData;
  readonly "project_milestone.updated": MilestoneEventData;
  readonly "project_milestone.deleted": MilestoneEventData;
};

/** The `tasks` block's event types, for its manifest and `onBlockEvent`. */
export const tasksEvents: Events<TasksEvents> = defineEvents({
  "task.created": event<TaskEventData>(),
  "task.updated": event<TaskEventData>(),
  "task.assigned": event<TaskEventData>(),
  "task.closed": event<TaskEventData>(),
  "task.reopened": event<TaskEventData>(),
  "task.archived": event<TaskEventData>(),
  "task.restored": event<TaskEventData>(),
  "task.deleted": event<TaskEventData>(),
  "task.unblocked": event<TaskEventData>(),
  "task.claimed": event<TaskEventData>(),
  "task.released": event<TaskEventData>(),
  "task.claim_expired": event<TaskEventData>(),
  "task.failed": event<TaskEventData>(),
  "task.delegated": event<TaskEventData>(),
  "task.held": event<TaskEventData>(),
  "task.hold_released": event<TaskEventData>(),
  "project.created": event<ProjectEventData>(),
  "project.updated": event<ProjectEventData>(),
  "project.archived": event<ProjectEventData>(),
  "project.restored": event<ProjectEventData>(),
  "project.deleted": event<ProjectEventData>(),
  "iteration.created": event<IterationEventData>(),
  "iteration.updated": event<IterationEventData>(),
  "iteration.deleted": event<IterationEventData>(),
  "iteration.started": event<IterationEventData>(),
  "iteration.completed": event<IterationEventData>(),
  "project_milestone.created": event<MilestoneEventData>(),
  "project_milestone.updated": event<MilestoneEventData>(),
  "project_milestone.deleted": event<MilestoneEventData>(),
});
