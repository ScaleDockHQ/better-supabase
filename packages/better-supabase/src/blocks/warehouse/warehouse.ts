import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { BlockOptions } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import {
  PICK_LINE_STATUSES,
  PICK_LIST_STATUSES,
  PICK_WAVE_STATUSES,
} from "../../sql/modules/warehouse-values.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

/** Where a pick wave stands. */
export type PickWaveStatus = (typeof PICK_WAVE_STATUSES)[number];

/** Where a pick list stands. */
export type PickListStatus = (typeof PICK_LIST_STATUSES)[number];

/** Where a pick line stands; `short` means less was found than asked for. */
export type PickLineStatus = (typeof PICK_LINE_STATUSES)[number];

/** A group of pick lists that are picked together. */
export interface PickWave {
  readonly id: string;
  readonly organizationId: string;
  readonly name: string;
  readonly locationId: string;
  readonly status: PickWaveStatus;
  readonly releasedAt?: Temporal.Instant;
  readonly completedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
  /** How many lists the wave has; only from `listPickWaves`. */
  readonly lists?: number;
  /** How many of them are still open; only from `listPickWaves`. */
  readonly openLists?: number;
}

/** What `createPickWave` takes. */
export interface PickWaveInput {
  readonly name: string;
  readonly locationId: string;
}

/** One allocation to pick. */
export interface PickLine {
  readonly id: string;
  readonly allocationId: string;
  readonly variantId: string;
  /** Where to find the stock, then where the picker found it. */
  readonly binId?: string;
  readonly lotId?: string;
  readonly serials?: readonly string[];
  /** A decimal string. */
  readonly quantity: string;
  /** A decimal string. */
  readonly picked: string;
  readonly status: PickLineStatus;
  readonly pickedAt?: Temporal.Instant;
  readonly pickedBy?: string;
}

/** One document's stock to pick at one location. */
export interface PickList {
  readonly id: string;
  readonly organizationId: string;
  readonly waveId?: string;
  readonly locationId: string;
  readonly documentType: string;
  readonly documentId: string;
  readonly status: PickListStatus;
  readonly assigneeId?: string;
  /** The picker's work item, when the tasks block is installed. */
  readonly taskId?: string;
  readonly pickedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
  readonly lines: readonly PickLine[];
}

/** What `createPickList` takes. */
export interface PickListInput {
  readonly locationId: string;
  /** The document the stock is allocated to, in snake_case. */
  readonly documentType: string;
  readonly documentId: string;
  /** A draft wave of the same location to put the list in. */
  readonly waveId?: string;
  readonly assigneeId?: string;
}

/** What `recordPick` takes. */
export interface PickRecord {
  /** Added to what was picked; more than zero. */
  readonly quantity: number;
  readonly binId?: string;
  readonly lotId?: string;
  readonly serials?: readonly string[];
}

/** Filters for `listPickLists`. */
export interface PickListOptions {
  readonly waveId?: string;
  readonly status?: PickListStatus;
  readonly documentType?: string;
  readonly documentId?: string;
  /** Only the lists assigned to the caller. */
  readonly mine?: boolean;
  /** 1 to 200. Default 50. */
  readonly limit?: number;
  readonly offset?: number;
}

/** A schedule that opens stock counts. */
export interface CountPlan {
  readonly id: string;
  readonly organizationId: string;
  readonly name: string;
  readonly locationId: string;
  readonly everyDays: number;
  /** The variants to count; all of them when empty. */
  readonly variantIds: readonly string[];
  /** A decimal string, in percent. */
  readonly varianceLimitPct: string;
  /** A date, `YYYY-MM-DD`. */
  readonly nextRunOn: string;
  readonly lastRunAt?: Temporal.Instant;
  readonly lastCountId?: string;
  readonly active: boolean;
  readonly createdAt: Temporal.Instant;
  /** The count a run opened; only on `runCountPlan`. */
  readonly countId?: string;
}

/** What `createCountPlan` takes. */
export interface CountPlanInput {
  readonly name: string;
  readonly locationId: string;
  readonly everyDays: number;
  readonly variantIds?: readonly string[];
  /** Default 5. */
  readonly varianceLimitPct?: number;
  /** A date, `YYYY-MM-DD`. Default today. */
  readonly startsOn?: string;
}

/** One counted line's variance. */
export interface CycleCountVarianceLine {
  readonly lineId: string;
  readonly variantId: string;
  readonly expected: string;
  readonly counted: string;
  readonly variance: string;
  readonly variancePct: string;
}

/** How far a count is from the books, against the limit that applies. */
export interface CycleCountVariance {
  readonly countId: string;
  readonly planId?: string;
  readonly limitPct: string;
  readonly maxVariancePct: string;
  readonly overLimit: boolean;
  readonly lines: readonly CycleCountVarianceLine[];
}

export interface Warehouse {
  /** Creates a draft wave; needs `warehouse.manage`. */
  createPickWave(input: PickWaveInput): AsyncResult<PickWave>;
  /**
   * Makes a pick list from a document's open allocations at a location. A list
   * without a wave gets its work item now; one in a wave waits for the
   * release.
   */
  createPickList(input: PickListInput): AsyncResult<PickList>;
  /** Releases a draft wave and makes its work items. */
  releasePickWave(waveId: string): AsyncResult<PickWave>;
  /** Cancels a draft or released wave and its open lists. */
  cancelPickWave(waveId: string): AsyncResult<PickWave>;
  /**
   * Records what a picker found; needs `warehouse.pick`. The stock moves when
   * the document ships, not here.
   */
  recordPick(lineId: string, pick: PickRecord): AsyncResult<PickList>;
  /** Finishes a list: lines with less picked than asked for become short. */
  completePickList(pickListId: string): AsyncResult<PickList>;
  getPickList(pickListId: string): AsyncResult<PickList>;
  listPickLists(options?: PickListOptions): AsyncResult<readonly PickList[]>;
  listPickWaves(): AsyncResult<readonly PickWave[]>;
  /** Creates a cycle count plan; needs `warehouse.manage`. */
  createCountPlan(input: CountPlanInput): AsyncResult<CountPlan>;
  listCountPlans(): AsyncResult<readonly CountPlan[]>;
  /** Opens the plan's count now. Also needs `inventory.manage`. */
  runCountPlan(planId: string): AsyncResult<CountPlan>;
  /** Opens the count of every plan that is due; for a daily job. */
  runDueCountPlans(): AsyncResult<
    readonly { readonly planId: string; readonly countId: string }[]
  >;
  /** The variance of a count against the plan's limit. */
  cycleCountVariance(countId: string): AsyncResult<CycleCountVariance>;
  /**
   * Posts a count through inventory. A count over the variance limit posts only
   * with `approve: true`.
   */
  postCycleCount(
    countId: string,
    options?: { readonly approve?: boolean },
  ): AsyncResult<Record<string, unknown>>;
}

/** Options for {@link createWarehouse}. */
export interface WarehouseOptions extends BlockOptions {
  /** `before` and `after` hooks per method (ADR 0015). */
  readonly hooks?: NoInfer<BlockHooks<Warehouse>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

function optional<K extends string, V>(
  key: K,
  value: V | undefined,
): { readonly [P in K]?: V } {
  // SAFETY: a one-key object literal for the key the caller names.
  return (value === undefined ? {} : { [key]: value }) as {
    readonly [P in K]?: V;
  };
}

const definedOf = (input: object): Record<string, unknown> =>
  Object.fromEntries(
    Object.entries(input).filter(([, value]) => value !== undefined),
  );

const numberOf = (value: unknown): number | undefined =>
  typeof value === "number" ? value : undefined;

const textsOf = (value: unknown): readonly string[] | undefined =>
  Array.isArray(value) ? value.map(textOf) : undefined;

function waveOf(value: unknown, fn: string): PickWave {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    name: textOf(row["name"]),
    locationId: textOf(row["locationId"]),
    status: enumOrThrow(row["status"], PICK_WAVE_STATUSES, "wave status"),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...optional("releasedAt", optionalInstant(row["releasedAt"])),
    ...optional("completedAt", optionalInstant(row["completedAt"])),
    ...optional("lists", numberOf(row["lists"])),
    ...optional("openLists", numberOf(row["openLists"])),
  };
}

function lineOf(value: unknown, fn: string): PickLine {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    allocationId: textOf(row["allocationId"]),
    variantId: textOf(row["variantId"]),
    quantity: textOf(row["quantity"]),
    picked: textOf(row["picked"]),
    status: enumOrThrow(row["status"], PICK_LINE_STATUSES, "line status"),
    ...optional("binId", optionalText(row["binId"])),
    ...optional("lotId", optionalText(row["lotId"])),
    ...optional("serials", textsOf(row["serials"])),
    ...optional("pickedAt", optionalInstant(row["pickedAt"])),
    ...optional("pickedBy", optionalText(row["pickedBy"])),
  };
}

function listOf(value: unknown, fn: string): PickList {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    locationId: textOf(row["locationId"]),
    documentType: textOf(row["documentType"]),
    documentId: textOf(row["documentId"]),
    status: enumOrThrow(row["status"], PICK_LIST_STATUSES, "list status"),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    lines: recordsOf(row["lines"] ?? [], fn).map((item) => lineOf(item, fn)),
    ...optional("waveId", optionalText(row["waveId"])),
    ...optional("assigneeId", optionalText(row["assigneeId"])),
    ...optional("taskId", optionalText(row["taskId"])),
    ...optional("pickedAt", optionalInstant(row["pickedAt"])),
  };
}

function planOf(value: unknown, fn: string): CountPlan {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    name: textOf(row["name"]),
    locationId: textOf(row["locationId"]),
    everyDays: Number(row["everyDays"]),
    variantIds: textsOf(row["variantIds"]) ?? [],
    varianceLimitPct: textOf(row["varianceLimitPct"]),
    nextRunOn: textOf(row["nextRunOn"]),
    active: row["active"] === true,
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...optional("lastRunAt", optionalInstant(row["lastRunAt"])),
    ...optional("lastCountId", optionalText(row["lastCountId"])),
    ...optional("countId", optionalText(row["countId"])),
  };
}

function varianceOf(value: unknown, fn: string): CycleCountVariance {
  const row = recordOf(value, fn);

  return {
    countId: textOf(row["countId"]),
    limitPct: textOf(row["limitPct"]),
    maxVariancePct: textOf(row["maxVariancePct"]),
    overLimit: row["overLimit"] === true,
    lines: recordsOf(row["lines"] ?? [], fn).map((item) => {
      const line = recordOf(item, fn);

      return {
        lineId: textOf(line["lineId"]),
        variantId: textOf(line["variantId"]),
        expected: textOf(line["expected"]),
        counted: textOf(line["counted"]),
        variance: textOf(line["variance"]),
        variancePct: textOf(line["variancePct"]),
      };
    }),
    ...optional("planId", optionalText(row["planId"])),
  };
}

/**
 * Warehouse work over inventory: pick waves and pick lists made from stock
 * allocations, with the bin, lot and serial numbers a picker confirms, and
 * cycle count plans that hold large variances for a review.
 */
export function createWarehouse(options: WarehouseOptions): Warehouse {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);
  const wave = (fn: string) => (value: unknown) => waveOf(value, fn);
  const list = (fn: string) => (value: unknown) => listOf(value, fn);
  const plan = (fn: string) => (value: unknown) => planOf(value, fn);

  const client: Warehouse = {
    createPickWave: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "create_pick_wave",
          { tenant: organizationId, input: definedOf(input) },
          wave("create_pick_wave"),
        ),
      ),
    createPickList: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "create_pick_list",
          { tenant: organizationId, input: definedOf(input) },
          list("create_pick_list"),
        ),
      ),
    releasePickWave: (waveId) =>
      call("release_pick_wave", { wave_id: waveId }, wave("release_pick_wave")),
    cancelPickWave: (waveId) =>
      call("cancel_pick_wave", { wave_id: waveId }, wave("cancel_pick_wave")),
    recordPick: (lineId, pick) =>
      call(
        "record_pick",
        { line_id: lineId, attrs: definedOf(pick) },
        list("record_pick"),
      ),
    completePickList: (pickListId) =>
      call(
        "complete_pick_list",
        { pick_list_id: pickListId },
        list("complete_pick_list"),
      ),
    getPickList: (pickListId) =>
      call(
        "get_pick_list",
        { pick_list_id: pickListId },
        list("get_pick_list"),
      ),
    listPickLists: (filters = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_pick_lists",
          { tenant: organizationId, filters: definedOf(filters) },
          (value) =>
            recordsOf(value, "list_pick_lists").map((row) =>
              listOf(row, "list_pick_lists"),
            ),
        ),
      ),
    listPickWaves: () =>
      tenant().andThen((organizationId) =>
        call("list_pick_waves", { tenant: organizationId }, (value) =>
          recordsOf(value, "list_pick_waves").map((row) =>
            waveOf(row, "list_pick_waves"),
          ),
        ),
      ),
    createCountPlan: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "create_count_plan",
          { tenant: organizationId, input: definedOf(input) },
          plan("create_count_plan"),
        ),
      ),
    listCountPlans: () =>
      tenant().andThen((organizationId) =>
        call("list_count_plans", { tenant: organizationId }, (value) =>
          recordsOf(value, "list_count_plans").map((row) =>
            planOf(row, "list_count_plans"),
          ),
        ),
      ),
    runCountPlan: (planId) =>
      call("run_count_plan", { plan_id: planId }, plan("run_count_plan")),
    runDueCountPlans: () =>
      tenant().andThen((organizationId) =>
        call("run_due_count_plans", { tenant: organizationId }, (value) =>
          recordsOf(value, "run_due_count_plans").map((row) => ({
            planId: textOf(row["planId"]),
            countId: textOf(row["countId"]),
          })),
        ),
      ),
    cycleCountVariance: (countId) =>
      call("get_cycle_count_variance", { count_id: countId }, (value) =>
        varianceOf(value, "get_cycle_count_variance"),
      ),
    postCycleCount: (countId, post = {}) =>
      call(
        "post_cycle_count",
        { count_id: countId, approve: post.approve ?? false },
        (value) => recordOf(value, "post_cycle_count"),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "warehouse",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
