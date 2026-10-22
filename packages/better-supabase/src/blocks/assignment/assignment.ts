import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { FilterQuery } from "../../list/filter-query.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { conditionsOf } from "../rules/rules.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  optionalInstant,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

/** How a queue picks the next owner. */
export type AssignmentStrategy = "round_robin" | "weighted";

const STRATEGIES: readonly AssignmentStrategy[] = ["round_robin", "weighted"];

/** A member in a queue's rotation. */
export interface AssignmentMember {
  readonly userId: string;
  /** The member's share in a weighted queue, 1 to 100. */
  readonly weight: number;
  /** Inactive members stay in the queue but get no records. */
  readonly active: boolean;
  readonly assignedCount: number;
  readonly lastAssignedAt: Temporal.Instant | undefined;
}

/** A queue that picks owners for records of one subject type. */
export interface AssignmentQueue {
  readonly id: string;
  readonly organizationId: string;
  readonly name: string;
  readonly subjectType: string;
  readonly strategy: AssignmentStrategy;
  /** The territory: records the queue takes. Undefined takes every record. */
  readonly conditions: FilterQuery | undefined;
  /** Queues are tried by rank, lowest first, then by name. */
  readonly rank: number;
  readonly enabled: boolean;
  readonly members: readonly AssignmentMember[];
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** What `saveQueue` takes. Leave `id` out to create a queue. */
export interface AssignmentQueueInput {
  readonly id?: string;
  readonly name?: string;
  readonly subjectType?: string;
  readonly strategy?: AssignmentStrategy;
  /** `null` clears the territory. */
  readonly conditions?: FilterQuery | null;
  readonly rank?: number;
  readonly enabled?: boolean;
}

/** A pick: the queue that matched and the member it chose. */
export interface Assignment {
  readonly queueId: string;
  readonly userId: string;
  readonly strategy: AssignmentStrategy;
}

/** A past pick for a record. */
export interface AssignmentRecord {
  /** Undefined when the queue was removed since. */
  readonly queueId: string | undefined;
  /** Undefined when the user was deleted since. */
  readonly userId: string | undefined;
  readonly assignedAt: Temporal.Instant;
}

export interface AssignmentClient {
  saveQueue(
    organizationId: string,
    queue: AssignmentQueueInput,
  ): AsyncResult<AssignmentQueue>;
  /** Replaces the queue's members; members who stay keep their turn. */
  setMembers(
    queueId: string,
    members: readonly {
      readonly userId: string;
      readonly weight?: number;
      readonly active?: boolean;
    }[],
  ): AsyncResult<AssignmentQueue>;
  removeQueue(queueId: string): AsyncResult<boolean>;
  queues(
    organizationId: string,
    options?: { readonly subjectType?: string },
  ): AsyncResult<AssignmentQueue[]>;
  /**
   * Picks an owner for a record from the first queue whose territory matches
   * `fields` (keyed as the rule fields' columns). Undefined when no queue
   * matches. Writing the owner onto the record is up to the app.
   */
  assign(
    organizationId: string,
    subject: {
      readonly type: string;
      readonly id: string;
      readonly fields?: Readonly<Record<string, unknown>>;
    },
  ): AsyncResult<Assignment | undefined>;
  /** The picks for a record, newest first. */
  history(
    organizationId: string,
    subject: { readonly type: string; readonly id: string },
    options?: { readonly limit?: number },
  ): AsyncResult<AssignmentRecord[]>;
}

export interface AssignmentOptions extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  readonly hooks?: NoInfer<BlockHooks<AssignmentClient>>;
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

const strategyOf = (value: unknown): AssignmentStrategy =>
  enumOrThrow(value, STRATEGIES, "assignment strategy");

function memberOf(row: Record<string, unknown>): AssignmentMember {
  return {
    userId: textOf(row["userId"]),
    weight: Number(row["weight"]),
    active: row["active"] === true,
    assignedCount: Number(row["assignedCount"]),
    lastAssignedAt: optionalInstant(row["lastAssignedAt"]),
  };
}

function queueOf(value: unknown): AssignmentQueue {
  const row = recordOf(value, "assignment queue");
  const conditions = row["conditions"];

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    name: textOf(row["name"]),
    subjectType: textOf(row["subjectType"]),
    strategy: strategyOf(row["strategy"]),
    conditions:
      conditions === null || conditions === undefined
        ? undefined
        : conditionsOf(conditions),
    rank: Number(row["rank"]),
    enabled: row["enabled"] === true,
    members: recordsOf(row["members"], "assignment queue members").map(
      memberOf,
    ),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
  };
}

const optionalId = (value: unknown): string | undefined =>
  typeof value === "string" ? value : undefined;

export function createAssignment(options: AssignmentOptions): AssignmentClient {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const client: AssignmentClient = {
    saveQueue: (organizationId, queue) =>
      call("save_assignment_queue", { tenant: organizationId, queue }, queueOf),
    setMembers: (queueId, members) =>
      call("set_assignment_members", { queue: queueId, members }, queueOf),
    removeQueue: (queueId) =>
      call(
        "remove_assignment_queue",
        { queue: queueId },
        (value) => value === true,
      ),
    queues: (organizationId, list = {}) =>
      call(
        "list_assignment_queues",
        { tenant: organizationId, subject_type: list.subjectType ?? null },
        (value) => recordsOf(value, "list_assignment_queues").map(queueOf),
      ),
    assign: (organizationId, subject) =>
      call(
        "assign_subject",
        {
          tenant: organizationId,
          subject_type: subject.type,
          subject_id: subject.id,
          subject: subject.fields ?? {},
        },
        (value) => {
          if (value === null || value === undefined) {
            return;
          }

          const row = recordOf(value, "assign_subject");

          return {
            queueId: textOf(row["queueId"]),
            userId: textOf(row["userId"]),
            strategy: strategyOf(row["strategy"]),
          };
        },
      ),
    history: (organizationId, subject, page = {}) =>
      call(
        "assignment_history",
        {
          tenant: organizationId,
          subject_type: subject.type,
          subject_id: subject.id,
          max_count: page.limit ?? null,
        },
        (value) =>
          recordsOf(value, "assignment_history").map((row) => ({
            queueId: optionalId(row["queueId"]),
            userId: optionalId(row["userId"]),
            assignedAt: requiredInstant(row["assignedAt"], "assignedAt"),
          })),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "assignment",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
