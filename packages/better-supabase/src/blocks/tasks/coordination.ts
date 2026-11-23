import type { BlockFields } from "../../core/block-fields.ts";
import type { IdempotencyClaims } from "../../core/idempotent-write.ts";
import type { Result } from "../../core/result.ts";
import type { blockCall } from "../shared.ts";
import type { Task, TaskInput } from "./tasks.ts";

import { idempotentCall } from "../../core/idempotent-write.ts";
import { AsyncResult, ok } from "../../core/result.ts";
import {
  isRecord,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

/** Who acts, as a label on events and timelines. It never grants access. */
export interface TaskActorProfile {
  /** A short lowercase word such as `agent`. */
  readonly kind?: string;
  readonly name?: string;
}

/** The public part of a task's live claim. The token stays with the holder. */
export interface TaskClaim {
  readonly holderId: string;
  /** Counts claims of this task, so a stale holder can be told apart. */
  readonly epoch: number;
  readonly claimedAt: Temporal.Instant;
  readonly expiresAt: Temporal.Instant;
  readonly profile?: TaskActorProfile;
}

/** A claimed task with the token that renews or releases the claim. */
export interface ClaimedTask<F extends object = Record<never, never>> {
  readonly task: Task<F>;
  readonly claim: TaskClaim & { readonly token: string };
}

/** One entry of a plan: a task, with a key other entries can name. */
export type TaskPlanItem<F extends object = Record<never, never>> = Omit<
  TaskInput<F>,
  "attachmentIds" | "parentId"
> & {
  /** A name for this entry, unique within the plan. */
  readonly key?: string;
  /** A task id, or the key of another entry. */
  readonly parentId?: string | { readonly key: string };
  readonly assigneeIds?: readonly string[];
  /** Prerequisites: task ids, or the keys of other entries. */
  readonly needs?: readonly (string | { readonly key: string })[];
};

/** What `createPlan` made. */
export interface TaskPlanResult<F extends object = Record<never, never>> {
  /** The created tasks, in plan order. */
  readonly tasks: readonly Task<F>[];
  /** Task ids by plan key. */
  readonly keys: Readonly<Record<string, string>>;
}

export interface TaskStageTime {
  readonly stageId: string;
  readonly stageName?: string;
  readonly category?: string;
  readonly enteredAt: Temporal.Instant;
  readonly exitedAt?: Temporal.Instant;
  /** Seconds in the stage. The open stage counts up to now. */
  readonly seconds: number;
}

export interface TaskMove {
  readonly taskId: string;
  /** The lane to move to; the task's own stage when left out. */
  readonly stageId?: string;
  /** Place the task just before this one. */
  readonly beforeId?: string;
  /** Place the task just after this one. */
  readonly afterId?: string;
}

export interface TaskMoveResult {
  readonly accepted: readonly { readonly taskId: string }[];
  readonly rejected: readonly {
    readonly taskId: string;
    readonly hint?: string;
    readonly reason: string;
  }[];
}

export interface TasksCoordination<F extends object = Record<never, never>> {
  /**
   * Replaces the task's prerequisites (tasks that block it). Needs the
   * relations block and its manage permission. A cycle or a prerequisite of
   * another tenant is refused.
   */
  setNeeds(input: {
    taskId: string;
    needs: readonly string[];
  }): AsyncResult<Task<F>>;
  /**
   * Creates a plan of tasks in one transaction. The plan is checked before the
   * first write: unknown properties, a duplicate key or a missing key refuse
   * all of it. At most 100 entries (`TASK_PLAN_TOO_LARGE`). With
   * `idempotencyKey` a replay returns the first result.
   */
  createPlan(input: {
    organizationId: string;
    plan: readonly TaskPlanItem<F>[];
    idempotencyKey?: string | undefined;
  }): AsyncResult<TaskPlanResult<F>>;
  /**
   * Takes the lease on a task. A live claim of someone else is refused with
   * `TASK_CLAIMED`, a task that waits on prerequisites with `TASK_NOT_READY`.
   * Claiming again as the same user keeps the token.
   */
  claim(input: {
    taskId: string;
    /** Lease seconds, capped by the `claims.maxLease` option. */
    lease?: number | undefined;
    profile?: TaskActorProfile | undefined;
  }): AsyncResult<ClaimedTask<F>>;
  /**
   * Claims the lowest-numbered ready task that matches `filter`, or resolves
   * with `undefined` when nothing is ready. By default (`claims.next:
   * "assigned"`) only tasks assigned to the caller qualify, and an agent
   * session is always limited that way. `filter.delegateProfile` keeps the
   * tasks reserved for that profile name. A task reserved for another profile
   * is skipped. Concurrent callers get different tasks.
   */
  claimNext(input: {
    organizationId: string;
    filter?:
      | {
          teamId?: string;
          projectId?: string;
          parentId?: string;
          stageId?: string;
          assigneeId?: string;
          delegateProfile?: string;
        }
      | undefined;
    lease?: number | undefined;
    profile?: TaskActorProfile | undefined;
  }): AsyncResult<ClaimedTask<F> | undefined>;
  /** Extends the lease. A lost claim is `TASK_CLAIM_LOST`. */
  renew(input: {
    taskId: string;
    token: string;
    lease?: number | undefined;
  }): AsyncResult<TaskClaim>;
  /** Gives the claim up. A lost claim is `TASK_CLAIM_LOST`. */
  release(input: {
    taskId: string;
    token: string;
    note?: string | undefined;
  }): AsyncResult<true>;
  /**
   * Hands the task to another user: it is assigned and the claim ends, so the
   * new owner claims it with their own token. With `toProfile` the task is
   * reserved for that profile name of the user: a claim under another profile
   * is `TASK_RESERVED`, unless a person with write access takes it over. The
   * reservation clears on the next delegate, on unassigning the user and on
   * close. ADR 1183.
   */
  delegate(input: {
    taskId: string;
    toUserId: string;
    toProfile?: string | undefined;
    profile?: TaskActorProfile | undefined;
  }): AsyncResult<Task<F>>;
  /**
   * Puts the task on hold, for example to ask a person. The note goes through
   * messaging and mentions `askUserIds`. With the `hold.stage` option the task
   * moves to that stage until `releaseHold`.
   */
  hold(input: {
    taskId: string;
    kind: string;
    note?: string | undefined;
    askUserIds?: readonly string[] | undefined;
  }): AsyncResult<Task<F>>;
  /** Ends a hold and returns the task to the stage it came from. */
  releaseHold(input: { taskId: string }): AsyncResult<Task<F>>;
  /**
   * Closes the task as failed: it lands in a canceled stage with the close
   * reason `failed`. `note` is kept and sent with `task.closed` and
   * `task.failed`.
   */
  fail(input: {
    taskId: string;
    stageId?: string | undefined;
    note?: string | undefined;
  }): AsyncResult<true>;
  /** Moves several tasks. A refused move is listed, the others apply. */
  moveMany(input: { moves: readonly TaskMove[] }): AsyncResult<TaskMoveResult>;
  /** The stages the task has been in, with the seconds spent in each. */
  stageTimes(taskId: string): AsyncResult<TaskStageTime[]>;
}

/** What the coordination methods borrow from `createTasks`. */
export interface CoordinationDeps<F extends object> {
  readonly call: ReturnType<typeof blockCall>;
  readonly itemOf: (value: unknown) => Task;
  readonly fields: BlockFields<F>;
  readonly idempotency: IdempotencyClaims | undefined;
  readonly args: (input: object) => Record<string, unknown>;
}

function profileOf(value: unknown): TaskActorProfile | undefined {
  if (!isRecord(value)) {
    return undefined;
  }

  const kind = optionalText(value["kind"]);
  const name = optionalText(value["name"]);

  if (kind === undefined && name === undefined) {
    return undefined;
  }

  return {
    ...(kind === undefined ? {} : { kind }),
    ...(name === undefined ? {} : { name }),
  };
}

function claimOf(value: unknown): TaskClaim {
  const row = recordOf(value, "task claim");
  const profile = profileOf(row["profile"]);

  return {
    holderId: textOf(row["holderId"]),
    epoch: Number(row["epoch"]),
    claimedAt: requiredInstant(row["claimedAt"], "claimedAt"),
    expiresAt: requiredInstant(row["expiresAt"], "expiresAt"),
    ...(profile === undefined ? {} : { profile }),
  };
}

/** The claim of a task row, when it has a live one. */
export function liveClaimOf(value: unknown): TaskClaim | undefined {
  return isRecord(value) ? claimOf(value) : undefined;
}

function stageTimeOf(value: unknown): TaskStageTime {
  const row = recordOf(value, "stage time");
  const name = optionalText(row["stageName"]);
  const category = optionalText(row["category"]);
  const exited = optionalText(row["exitedAt"]);

  return {
    stageId: textOf(row["stageId"]),
    ...(name === undefined ? {} : { stageName: name }),
    ...(category === undefined ? {} : { category }),
    enteredAt: requiredInstant(row["enteredAt"], "enteredAt"),
    ...(exited === undefined
      ? {}
      : { exitedAt: requiredInstant(exited, "exitedAt") }),
    seconds: Number(row["seconds"]),
  };
}

const profileArg = (
  profile: TaskActorProfile | undefined,
): TaskActorProfile | null => profile ?? null;

/** The coordination methods of `createTasks`. */
export function coordinationClient<F extends object>(
  deps: CoordinationDeps<F>,
): TasksCoordination<F> {
  const { call, itemOf, fields } = deps;

  const grantOf = (value: unknown): ClaimedTask => {
    const row = recordOf(value, "claimed task");
    const claim = recordOf(row["claim"], "claim");

    return {
      task: itemOf(row["task"]),
      claim: { ...claimOf(claim), token: textOf(claim["token"]) },
    };
  };

  const parsed = (grant: ClaimedTask): AsyncResult<ClaimedTask<F>> =>
    fields.row(grant.task).map((task) => ({ ...grant, task }));

  const planArg = (
    item: TaskPlanItem<F>,
  ): AsyncResult<Record<string, unknown>> => {
    const { fields: extra, assigneeIds, ...rest } = item;

    return fields
      .args(extra)
      .map((checked) => ({
        ...deps.args(rest),
        ...(assigneeIds === undefined ? {} : { assignees: [...assigneeIds] }),
        ...(checked === undefined ? {} : { fields: checked }),
      }));
  };

  const plansArg = async (
    plan: readonly TaskPlanItem<F>[],
  ): Promise<Result<Record<string, unknown>[]>> => {
    const items: Record<string, unknown>[] = [];

    for (const item of plan) {
      const arg = await planArg(item);

      if (!arg.ok) {
        return arg;
      }

      items.push(arg.data);
    }

    return ok(items);
  };

  const planOf = (value: unknown): TaskPlanResult => {
    const row = recordOf(value, "task plan");
    const keys = isRecord(row["keys"]) ? row["keys"] : {};

    return {
      tasks: recordsOf(row["tasks"], "create_tasks").map(itemOf),
      keys: Object.fromEntries(
        Object.entries(keys).map(([key, id]) => [key, textOf(id)]),
      ),
    };
  };

  return {
    setNeeds: ({ taskId, needs }) =>
      call("set_task_needs", { task: taskId, ids: [...needs] }, (value) =>
        itemOf(value),
      ).andThen(fields.row),
    createPlan: ({ organizationId, plan, idempotencyKey }) =>
      AsyncResult.from(async () => {
        const items = await plansArg(plan);

        if (!items.ok) {
          return items;
        }

        const sent = { tenant: organizationId, items: items.data };

        const made = await idempotentCall({
          claims: deps.idempotency,
          key: idempotencyKey,
          scope: organizationId,
          name: "create_tasks",
          args: sent,
          run: () => call("create_tasks", sent, (value) => value),
          decode: planOf,
        });

        if (!made.ok) {
          return made;
        }

        const rows = await fields.rows([...made.data.tasks]);

        return rows.ok ? ok({ tasks: rows.data, keys: made.data.keys }) : rows;
      }),
    claim: ({ taskId, lease, profile }) =>
      call(
        "claim_task",
        { task: taskId, lease: lease ?? null, profile: profileArg(profile) },
        grantOf,
      ).andThen(parsed),
    claimNext: ({ organizationId, filter, lease, profile }) =>
      AsyncResult.from(async () => {
        const claimed = await call(
          "claim_next_task",
          {
            tenant: organizationId,
            filter: filter ?? null,
            lease: lease ?? null,
            profile: profileArg(profile),
          },
          grantOf,
        );

        if (!claimed.ok) {
          return claimed.error.hint === "TASK_NOTHING_READY"
            ? ok(undefined)
            : claimed;
        }

        return parsed(claimed.data);
      }),
    renew: ({ taskId, token, lease }) =>
      call(
        "renew_task_claim",
        { task: taskId, token, lease: lease ?? null },
        claimOf,
      ),
    release: ({ taskId, token, note }) =>
      call(
        "release_task_claim",
        { task: taskId, token, note: note ?? null },
        () => true as const,
      ),
    delegate: ({ taskId, toUserId, toProfile, profile }) =>
      call(
        "delegate_task",
        {
          task: taskId,
          to_user: toUserId,
          profile: profileArg(profile),
          to_profile: toProfile ?? null,
        },
        (value) => itemOf(value),
      ).andThen(fields.row),
    hold: ({ taskId, kind, note, askUserIds }) =>
      call(
        "hold_task",
        {
          task: taskId,
          kind,
          note: note ?? null,
          ask_user_ids: askUserIds === undefined ? null : [...askUserIds],
        },
        (value) => itemOf(value),
      ).andThen(fields.row),
    releaseHold: ({ taskId }) =>
      call("release_task_hold", { task: taskId }, (value) =>
        itemOf(value),
      ).andThen(fields.row),
    fail: ({ taskId, stageId, note }) =>
      call(
        "close_task",
        {
          task: taskId,
          outcome: "failed",
          note: note ?? null,
          stage: stageId ?? null,
        },
        () => true as const,
      ),
    moveMany: ({ moves }) =>
      call(
        "move_tasks",
        { moves: moves.map((move) => deps.args(move)) },
        (value) => {
          const row = recordOf(value, "move_tasks");

          return {
            accepted: recordsOf(row["accepted"], "accepted").map((each) => ({
              taskId: textOf(each["taskId"]),
            })),
            rejected: recordsOf(row["rejected"], "rejected").map((each) => {
              const hint = optionalText(each["hint"]);

              return {
                taskId: textOf(each["taskId"]),
                ...(hint === undefined ? {} : { hint }),
                reason: textOf(each["reason"]),
              };
            }),
          };
        },
      ),
    stageTimes: (taskId) =>
      call("task_stage_times", { task: taskId }, (value) =>
        recordsOf(value, "task_stage_times").map(stageTimeOf),
      ),
  };
}
