import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks.tasks.options`. */
export type TasksSqlOptions = {
  readonly prefix?: string;
  readonly maxAssignees?: number;
  /** Whether an item's author can delete it without the delete key. */
  readonly authorCanDelete?: boolean;
  readonly notify?: boolean;
  readonly actionPath?: string;
  /**
   * Adds a stored `search_tsv` column and a GIN index to work items, so queries
   * match with `search_tsv @@ websearch_to_tsquery('simple', ...)`. Default
   * `false`.
   */
  readonly searchColumn?: boolean;
  /**
   * Rows with `template_id` set are templates: they take no number, no search
   * document, no pipeline history and no domain events. Needs the templates
   * block. ADR 0244.
   */
  readonly templates?: boolean;
  /**
   * Prerequisites: `needs` rows keep a `waiting_on` count of the open
   * prerequisites on each task, so a `ready` filter lists the tasks nothing
   * blocks. `refuse` is what an unready task refuses: `claims` (default),
   * `started` (claims and a move into a started stage) or `none`. Needs the
   * relations block and the `waiting_on` column. ADR 1110.
   */
  readonly needs?: {
    readonly kind: "blocks";
    readonly refuse?: "claims" | "started" | "none";
  };
  /**
   * Leases for claims, in seconds, and the stages a claim moves a task to:
   * `startStage` when it starts and `expiredStage` when a lease runs out (stage
   * keys of the task's pipeline). ADR 1112.
   */
  readonly claims?: {
    readonly lease?: number;
    readonly maxLease?: number;
    readonly startStage?: string;
    readonly expiredStage?: string;
  };
  /**
   * `stage` is the stage key of the task's pipeline a hold moves the task to.
   * Without it a hold only sets `held_at`. ADR 1114.
   *
   * `approval` files each hold with the approvals block, which needs the
   * `held_at` column: `true` asks one approver (members with the manage
   * permission), or give a `policy` (approvals policy without `run`). An
   * approval releases the task; a rejection cancels it, or with `onReject:
   * "keep"` leaves it on hold. ADR 1161.
   */
  readonly hold?: {
    readonly stage?: string;
    readonly approval?:
      | boolean
      | { readonly policy?: unknown; readonly onReject?: "cancel" | "keep" };
  };
};

export const tasksSqlOptions: BlockOptionsSchema<TasksSqlOptions> =
  blockOptions<TasksSqlOptions>({
    prefix: option.string({ default: "TASK-" }),
    maxAssignees: option.number({ default: 0 }),
    authorCanDelete: option.boolean({ default: true }),
    notify: option.boolean({ default: true }),
    actionPath: option.string(),
    searchColumn: option.boolean({ default: false }),
    templates: option.boolean({ default: false }),
    needs: option.unknown(),
    claims: option.unknown(),
    hold: option.unknown(),
  });
