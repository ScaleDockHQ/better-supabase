import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type {
  OptimizedStops,
  RouteOptimizer,
  RoutePoint,
} from "../dispatch/route-optimizer.ts";
import type { BlockOptions } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { AsyncResult, ok } from "../../core/result.ts";
import {
  PICK_LINE_STATUSES,
  PICK_LIST_STATUSES,
  PICK_WAVE_STATUSES,
} from "../../sql/modules/warehouse-values.ts";
import {
  nearestNeighbourOptimizer,
  optimizeStops,
} from "../dispatch/route-optimizer.ts";
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
  /** The place in the walking order, from `setPickRoute`; absent until set. */
  readonly routePosition?: number;
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

/** A bin to put stock in: a rule for a variant, or for any variant. */
export interface PutawayRule {
  readonly id: string;
  readonly organizationId: string;
  readonly locationId: string;
  readonly binId: string;
  /** Absent for a rule that applies to every variant. */
  readonly variantId?: string;
  /** Lowest first. */
  readonly priority: number;
  /** The most of the variant the bin takes, a decimal string. */
  readonly maxQuantity?: string;
  readonly active: boolean;
  readonly createdAt: Temporal.Instant;
}

/** What `savePutawayRule` takes. */
export interface PutawayRuleInput {
  /** Changes this rule; absent creates one. */
  readonly id?: string;
  readonly locationId?: string;
  readonly binId?: string;
  readonly variantId?: string;
  /** 0 to 10000. Default 100. */
  readonly priority?: number;
  /** More than zero. */
  readonly maxQuantity?: number;
  readonly active?: boolean;
}

/** What `saveBinSlot` takes. */
export interface BinSlotInput {
  readonly binId: string;
  /** How far the bin is from the dispatch area, lowest closest. Default 0. */
  readonly walkRank?: number;
  /** In the unit of variant sizes; no limit when absent. */
  readonly capacity?: number;
}

/** A bin with its slot and how full it is. */
export interface BinSlot {
  readonly binId: string;
  readonly code: string;
  readonly locationId: string;
  readonly hold: boolean;
  readonly active: boolean;
  /** Absent for a bin without a slot. */
  readonly walkRank?: number;
  /** A decimal string; absent when the bin has no limit. */
  readonly capacity?: string;
  /** A decimal string: stock in the bin times the variant sizes. */
  readonly used: string;
}

/** Why a bin is suggested. */
export type PutawaySource = "rule" | "stock" | "free";

/** One bin of a putaway suggestion. */
export interface PutawayPlacement {
  readonly binId: string;
  readonly binCode: string;
  /** A decimal string. */
  readonly quantity: string;
  readonly source: PutawaySource;
  /** The rule behind a `rule` placement. */
  readonly ruleId?: string;
}

/** Where the stock of one variant goes. Nothing has moved. */
export interface PutawaySuggestion {
  readonly locationId: string;
  readonly variantId: string;
  /** A decimal string. */
  readonly quantity: string;
  readonly placements: readonly PutawayPlacement[];
  /** What no bin has room for, a decimal string. */
  readonly unassigned: string;
}

/** What `suggestPutaway` takes. */
export interface PutawayRequest {
  readonly locationId: string;
  readonly variantId: string;
  /** More than zero. */
  readonly quantity: number;
}

/** What `suggestSlotting` takes. */
export interface SlottingOptions {
  readonly locationId: string;
  /** How far back picks count, 1 to 365. Default 30. */
  readonly days?: number;
  /** How many variants, 1 to 500. Default 50. */
  readonly limit?: number;
}

/** Where a fast-moving variant should live. Nothing has moved. */
export interface SlottingSuggestion {
  readonly variantId: string;
  /** Picked quantity in the period, a decimal string. */
  readonly velocity: string;
  readonly picks: number;
  /** A decimal string: stock in bins of the location. */
  readonly onHand: string;
  readonly currentBinId?: string;
  readonly suggestedBinId?: string;
  readonly action: "keep" | "move";
}

/** What `optimizePickRoute` takes. */
export interface OptimizePickRouteOptions {
  /** Where a line's bin is; lines without a point go last, in their order. */
  readonly locate: (line: PickLine) => RoutePoint | undefined;
  /** Default: `nearestNeighbourOptimizer()`. */
  readonly optimizer?: RouteOptimizer;
  /** Where the picker starts, such as the packing desk. */
  readonly start?: RoutePoint;
  readonly end?: RoutePoint;
}

/** A pick list in walking order and the optimization behind it. */
export interface OptimizedPickRoute {
  readonly pickList: PickList;
  readonly optimization: OptimizedStops;
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
  recordPick(input: {
    lineId: string;
    pick: PickRecord;
  }): AsyncResult<PickList>;
  /**
   * Finishes a list: lines with less picked than asked for become short, and
   * the picker's work item moves to done.
   */
  completePickList(pickListId: string): AsyncResult<PickList>;
  getPickList(pickListId: string): AsyncResult<PickList>;
  listPickLists(options?: PickListOptions): AsyncResult<readonly PickList[]>;
  listPickWaves(): AsyncResult<readonly PickWave[]>;
  /**
   * Creates a putaway rule, or changes the one named by `input.id`; needs
   * `warehouse.manage`.
   */
  savePutawayRule(input: PutawayRuleInput): AsyncResult<PutawayRule>;
  /** `false` when the rule was already gone. */
  deletePutawayRule(ruleId: string): AsyncResult<boolean>;
  listPutawayRules(options?: {
    readonly locationId?: string;
    readonly variantId?: string;
  }): AsyncResult<readonly PutawayRule[]>;
  /** Sets a bin's walk rank and capacity; needs `warehouse.manage`. */
  saveBinSlot(
    input: BinSlotInput,
  ): AsyncResult<{
    readonly binId: string;
    readonly walkRank: number;
    readonly capacity?: string;
  }>;
  /** Sets the space one unit of a variant takes in a bin. */
  saveVariantSize(input: {
    readonly variantId: string;
    readonly size: number;
  }): AsyncResult<{ readonly variantId: string; readonly size: string }>;
  /** The bins of a location with their slot and how full they are. */
  listBinSlots(locationId: string): AsyncResult<readonly BinSlot[]>;
  /**
   * Suggests bins for stock to put away: rule bins, then bins that hold the
   * variant, then the closest free ones.
   */
  suggestPutaway(request: PutawayRequest): AsyncResult<PutawaySuggestion>;
  /**
   * Suggests bins for each variant of a goods receipt. Needs the inventory
   * block's receipt tables.
   */
  suggestReceiptPutaway(
    receiptId: string,
  ): AsyncResult<readonly PutawaySuggestion[]>;
  /** Suggests the closest bins for a location's fastest movers. */
  suggestSlotting(
    options: SlottingOptions,
  ): AsyncResult<readonly SlottingSuggestion[]>;
  /**
   * Sets the walking order of an open list: `lineIds` first, the other open
   * lines after them.
   */
  setPickRoute(input: {
    pickListId: string;
    lineIds: readonly string[];
  }): AsyncResult<PickList>;
  /**
   * Orders an open list's lines by the bins' places with `optimizer` (nearest
   * neighbour by default) and saves it as the route. A failing optimizer falls
   * back to nearest neighbour; the result says which one ran.
   */
  optimizePickRoute(
    input: { pickListId: string } & OptimizePickRouteOptions,
  ): AsyncResult<OptimizedPickRoute>;
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
    input: { countId: string } & { readonly approve?: boolean },
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
    ...optional("routePosition", optionalNumber(row["routePosition"])),
    ...optional("pickedAt", optionalInstant(row["pickedAt"])),
    ...optional("pickedBy", optionalText(row["pickedBy"])),
  };
}

const optionalNumber = (value: unknown): number | undefined =>
  typeof value === "number" && Number.isFinite(value) ? value : undefined;

function ruleOf(value: unknown, fn: string): PutawayRule {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    locationId: textOf(row["locationId"]),
    binId: textOf(row["binId"]),
    priority: Number(row["priority"]),
    active: row["active"] === true,
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...optional("variantId", optionalText(row["variantId"])),
    ...optional("maxQuantity", optionalText(row["maxQuantity"])),
  };
}

function binSlotOf(value: unknown, fn: string): BinSlot {
  const row = recordOf(value, fn);

  return {
    binId: textOf(row["binId"]),
    code: textOf(row["code"]),
    locationId: textOf(row["locationId"]),
    hold: row["hold"] === true,
    active: row["active"] === true,
    used: textOf(row["used"]),
    ...optional("walkRank", optionalNumber(row["walkRank"])),
    ...optional("capacity", optionalText(row["capacity"])),
  };
}

function suggestionOf(value: unknown, fn: string): PutawaySuggestion {
  const row = recordOf(value, fn);

  return {
    locationId: textOf(row["locationId"]),
    variantId: textOf(row["variantId"]),
    quantity: textOf(row["quantity"]),
    unassigned: textOf(row["unassigned"]),
    placements: recordsOf(row["placements"] ?? [], fn).map((item) => {
      const placement = recordOf(item, fn);

      return {
        binId: textOf(placement["binId"]),
        binCode: textOf(placement["binCode"]),
        quantity: textOf(placement["quantity"]),
        source: enumOrThrow(
          placement["source"],
          ["rule", "stock", "free"] as const,
          "placement source",
        ),
        ...optional("ruleId", optionalText(placement["ruleId"])),
      };
    }),
  };
}

function slottingOf(value: unknown, fn: string): SlottingSuggestion {
  const row = recordOf(value, fn);

  return {
    variantId: textOf(row["variantId"]),
    velocity: textOf(row["velocity"]),
    picks: Number(row["picks"]),
    onHand: textOf(row["onHand"]),
    action: enumOrThrow(row["action"], ["keep", "move"] as const, "action"),
    ...optional("currentBinId", optionalText(row["currentBinId"])),
    ...optional("suggestedBinId", optionalText(row["suggestedBinId"])),
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
    recordPick: ({ lineId, pick }) =>
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
    savePutawayRule: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "save_putaway_rule",
          { tenant: organizationId, input: definedOf(input) },
          (value) => ruleOf(value, "save_putaway_rule"),
        ),
      ),
    deletePutawayRule: (ruleId) =>
      call(
        "delete_putaway_rule",
        { rule_id: ruleId },
        (value) => value === true,
      ),
    listPutawayRules: (filters = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_putaway_rules",
          { tenant: organizationId, filters: definedOf(filters) },
          (value) =>
            recordsOf(value, "list_putaway_rules").map((row) =>
              ruleOf(row, "list_putaway_rules"),
            ),
        ),
      ),
    saveBinSlot: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "save_bin_slot",
          { tenant: organizationId, input: definedOf(input) },
          (value) => {
            const row = recordOf(value, "save_bin_slot");

            return {
              binId: textOf(row["binId"]),
              walkRank: Number(row["walkRank"]),
              ...optional("capacity", optionalText(row["capacity"])),
            };
          },
        ),
      ),
    saveVariantSize: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "save_variant_size",
          { tenant: organizationId, input: definedOf(input) },
          (value) => {
            const row = recordOf(value, "save_variant_size");

            return {
              variantId: textOf(row["variantId"]),
              size: textOf(row["size"]),
            };
          },
        ),
      ),
    listBinSlots: (locationId) =>
      tenant().andThen((organizationId) =>
        call(
          "list_bin_slots",
          { tenant: organizationId, filters: { locationId } },
          (value) =>
            recordsOf(value, "list_bin_slots").map((row) =>
              binSlotOf(row, "list_bin_slots"),
            ),
        ),
      ),
    suggestPutaway: (request) =>
      tenant().andThen((organizationId) =>
        call(
          "suggest_putaway",
          { tenant: organizationId, input: definedOf(request) },
          (value) => suggestionOf(value, "suggest_putaway"),
        ),
      ),
    suggestReceiptPutaway: (receiptId) =>
      call("suggest_receipt_putaway", { receipt_id: receiptId }, (value) =>
        recordsOf(value, "suggest_receipt_putaway").map((row) =>
          suggestionOf(row, "suggest_receipt_putaway"),
        ),
      ),
    suggestSlotting: (slotting) =>
      tenant().andThen((organizationId) =>
        call(
          "suggest_slotting",
          { tenant: organizationId, input: definedOf(slotting) },
          (value) =>
            recordsOf(value, "suggest_slotting").map((row) =>
              slottingOf(row, "suggest_slotting"),
            ),
        ),
      ),
    setPickRoute: ({ pickListId, lineIds }) =>
      call(
        "set_pick_route",
        { pick_list_id: pickListId, line_ids: lineIds },
        list("set_pick_route"),
      ),
    optimizePickRoute: ({ pickListId, ...routeOptions }) =>
      client.getPickList(pickListId).andThen((pickList) => {
        const open = pickList.lines.filter((line) => line.status === "open");

        const located = open.flatMap((line) => {
          const point = routeOptions.locate(line);

          return point === undefined ? [] : [{ id: line.id, point }];
        });

        const placed = new Set(located.map((stop) => stop.id));

        const unplaced = open
          .map((line) => line.id)
          .filter((id) => !placed.has(id));

        return AsyncResult.from(async () =>
          ok(
            await optimizeStops(
              routeOptions.optimizer ?? nearestNeighbourOptimizer(),
              {
                stops: located,
                ...(routeOptions.start ? { start: routeOptions.start } : {}),
                ...(routeOptions.end ? { end: routeOptions.end } : {}),
              },
            ),
          ),
        ).andThen((optimization) =>
          client
            .setPickRoute({
              pickListId,
              lineIds: [...optimization.order, ...unplaced],
            })
            .map((routed) => ({ pickList: routed, optimization })),
        );
      }),
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
    postCycleCount: ({ countId, ...post }) =>
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
