import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { BlockOptions } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import {
  MAINTENANCE_CALIBRATION_RESULTS,
  MAINTENANCE_PLAN_KINDS,
  MAINTENANCE_PLAN_STATUSES,
  MAINTENANCE_PRIORITIES,
} from "../../sql/modules/maintenance-values.ts";
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

/** What triggers a plan: time or a meter. */
export type MaintenancePlanKind = (typeof MAINTENANCE_PLAN_KINDS)[number];

/** Whether a plan generates work orders. */
export type MaintenancePlanStatus = (typeof MAINTENANCE_PLAN_STATUSES)[number];

/** How urgent a plan's work orders are. */
export type MaintenancePriority = (typeof MAINTENANCE_PRIORITIES)[number];

/** How a calibration ended. */
export type MaintenanceCalibrationResult =
  (typeof MAINTENANCE_CALIBRATION_RESULTS)[number];

/** A spare part a plan puts on its work orders. */
export interface MaintenancePart {
  readonly id: string;
  readonly name: string;
  /** A decimal string. */
  readonly quantity: string;
  /** The inventory variant, when the part is stocked. */
  readonly variantId?: string;
}

/** A preventive maintenance plan. */
export interface MaintenancePlan {
  readonly id: string;
  readonly organizationId: string;
  readonly title: string;
  readonly kind: MaintenancePlanKind;
  readonly assetId?: string;
  readonly everyDays?: number;
  readonly meterId?: string;
  /** A decimal string. */
  readonly everyValue?: string;
  readonly priority: MaintenancePriority;
  readonly status: MaintenancePlanStatus;
  readonly lastDoneAt?: Temporal.Instant;
  readonly nextDueAt?: Temporal.Instant;
  /** The open dispatch work order, if one was generated. */
  readonly workOrderId?: string;
  /** Whether a work order should be generated now. */
  readonly due: boolean;
  readonly parts: readonly MaintenancePart[];
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** A meter, such as hours run. */
export interface MaintenanceMeter {
  readonly id: string;
  readonly organizationId: string;
  readonly name: string;
  readonly unit: string;
  readonly assetId?: string;
  /** The latest reading, a decimal string. */
  readonly reading: string;
  readonly readAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
}

/** A calibration of an instrument. */
export interface MaintenanceCalibration {
  readonly id: string;
  readonly organizationId: string;
  readonly assetId?: string;
  readonly instrument: string;
  readonly performedAt: Temporal.Instant;
  readonly dueAt: Temporal.Instant;
  readonly result: MaintenanceCalibrationResult;
  readonly reference?: string;
  readonly performedBy?: string;
}

/** A work order the generator opened for a plan. */
export interface MaintenanceGenerated {
  readonly planId: string;
  readonly workOrderId: string;
}

export interface MaintenancePlanInput {
  readonly title: string;
  readonly kind: MaintenancePlanKind;
  /** Required for a time plan. */
  readonly everyDays?: number;
  /** Required for a meter plan. */
  readonly meterId?: string;
  /** Required for a meter plan, a decimal string. */
  readonly everyValue?: string;
  readonly assetId?: string | null;
  /** Default `normal`. */
  readonly priority?: MaintenancePriority;
  readonly parts?: readonly {
    readonly name: string;
    /** Default 1. */
    readonly quantity?: string | number;
    readonly variantId?: string | null;
  }[];
}

/** What `updatePlan` changes; the kind and meter stay. */
export type MaintenancePlanChange = Partial<
  Omit<MaintenancePlanInput, "kind" | "meterId"> & {
    readonly status: MaintenancePlanStatus;
  }
>;

export interface MaintenanceCalibrationInput {
  readonly assetId?: string | null;
  readonly instrument: string;
  readonly performedAt: Temporal.Instant;
  /** On or after `performedAt`. */
  readonly dueAt: Temporal.Instant;
  readonly result: MaintenanceCalibrationResult;
  readonly reference?: string | null;
}

export interface MaintenancePlanListOptions {
  readonly status?: MaintenancePlanStatus;
  readonly kind?: MaintenancePlanKind;
  readonly assetId?: string;
  /** Only the plans that are due now. */
  readonly due?: boolean;
  /** 1 to 200. Default 50. */
  readonly limit?: number;
  readonly offset?: number;
}

export interface MaintenanceCalibrationListOptions {
  readonly assetId?: string;
  /** Due on or before. */
  readonly dueBefore?: Temporal.Instant;
  /** 1 to 200. Default 50. */
  readonly limit?: number;
  readonly offset?: number;
}

export interface Maintenance {
  /** Creates a plan; needs `maintenance.manage`. */
  createPlan(input: MaintenancePlanInput): AsyncResult<MaintenancePlan>;
  updatePlan(
    planId: string,
    change: MaintenancePlanChange,
  ): AsyncResult<MaintenancePlan>;
  deletePlan(planId: string): AsyncResult<MaintenancePlan>;
  listPlans(
    options?: MaintenancePlanListOptions,
  ): AsyncResult<readonly MaintenancePlan[]>;
  /**
   * Opens a dispatch work order, with the plan's parts, for every due plan that
   * has none open. A done work order moves the plan's next due date.
   */
  generateWorkOrders(): AsyncResult<readonly MaintenanceGenerated[]>;
  /** Adds a meter; needs `maintenance.manage`. */
  createMeter(input: {
    readonly name: string;
    readonly unit: string;
    readonly assetId?: string;
  }): AsyncResult<MaintenanceMeter>;
  /**
   * Records a reading, never below the previous one; needs
   * `maintenance.record`.
   */
  recordReading(
    meterId: string,
    value: string | number,
    readAt?: Temporal.Instant,
  ): AsyncResult<MaintenanceMeter>;
  listMeters(): AsyncResult<readonly MaintenanceMeter[]>;
  recordCalibration(
    input: MaintenanceCalibrationInput,
  ): AsyncResult<MaintenanceCalibration>;
  listCalibrations(
    options?: MaintenanceCalibrationListOptions,
  ): AsyncResult<readonly MaintenanceCalibration[]>;
}

/** Options for {@link createMaintenance}. */
export interface MaintenanceOptions extends BlockOptions {
  /** `before` and `after` hooks per method (ADR 0015). */
  readonly hooks?: NoInfer<BlockHooks<Maintenance>>;
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

function partOf(value: unknown, fn: string): MaintenancePart {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    name: textOf(row["name"]),
    quantity: textOf(row["quantity"]),
    ...optional("variantId", optionalText(row["variantId"])),
  };
}

function planOf(value: unknown, fn: string): MaintenancePlan {
  const row = recordOf(value, fn);
  const everyDays = row["everyDays"];

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    title: textOf(row["title"]),
    kind: enumOrThrow(row["kind"], MAINTENANCE_PLAN_KINDS, "plan kind"),
    priority: enumOrThrow(
      row["priority"],
      MAINTENANCE_PRIORITIES,
      "plan priority",
    ),
    status: enumOrThrow(
      row["status"],
      MAINTENANCE_PLAN_STATUSES,
      "plan status",
    ),
    due: row["due"] === true,
    parts: recordsOf(row["parts"] ?? [], fn).map((part) => partOf(part, fn)),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("assetId", optionalText(row["assetId"])),
    ...optional(
      "everyDays",
      typeof everyDays === "number" ? everyDays : undefined,
    ),
    ...optional("meterId", optionalText(row["meterId"])),
    ...optional("everyValue", optionalText(row["everyValue"])),
    ...optional("lastDoneAt", optionalInstant(row["lastDoneAt"])),
    ...optional("nextDueAt", optionalInstant(row["nextDueAt"])),
    ...optional("workOrderId", optionalText(row["workOrderId"])),
  };
}

function meterOf(value: unknown, fn: string): MaintenanceMeter {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    name: textOf(row["name"]),
    unit: textOf(row["unit"]),
    reading: textOf(row["reading"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...optional("assetId", optionalText(row["assetId"])),
    ...optional("readAt", optionalInstant(row["readAt"])),
  };
}

function calibrationOf(value: unknown, fn: string): MaintenanceCalibration {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    instrument: textOf(row["instrument"]),
    performedAt: requiredInstant(row["performedAt"], "performedAt"),
    dueAt: requiredInstant(row["dueAt"], "dueAt"),
    result: enumOrThrow(
      row["result"],
      MAINTENANCE_CALIBRATION_RESULTS,
      "calibration result",
    ),
    ...optional("assetId", optionalText(row["assetId"])),
    ...optional("reference", optionalText(row["reference"])),
    ...optional("performedBy", optionalText(row["performedBy"])),
  };
}

function planArgs(
  input: Partial<MaintenancePlanInput> & { readonly status?: string },
): Record<string, unknown> {
  const { parts, ...rest } = input;

  return definedOf({
    ...rest,
    parts: parts?.map((part) =>
      definedOf({
        name: part.name,
        quantity:
          part.quantity === undefined ? undefined : String(part.quantity),
        variantId: part.variantId,
      }),
    ),
  });
}

/**
 * Maintenance: preventive plans by time or meter that open dispatch work orders
 * with their spare parts, meter readings and calibrations.
 */
export function createMaintenance(options: MaintenanceOptions): Maintenance {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);
  const plan = (fn: string) => (value: unknown) => planOf(value, fn);
  const meter = (fn: string) => (value: unknown) => meterOf(value, fn);

  const client: Maintenance = {
    createPlan: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "create_maintenance_plan",
          { tenant: organizationId, input: planArgs(input) },
          plan("create_maintenance_plan"),
        ),
      ),
    updatePlan: (planId, change) =>
      call(
        "update_maintenance_plan",
        { plan_id: planId, changes: planArgs(change) },
        plan("update_maintenance_plan"),
      ),
    deletePlan: (planId) =>
      call(
        "delete_maintenance_plan",
        { plan_id: planId },
        plan("delete_maintenance_plan"),
      ),
    listPlans: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_maintenance_plans",
          {
            tenant: organizationId,
            filters: definedOf({
              status: list.status,
              kind: list.kind,
              assetId: list.assetId,
              due: list.due,
              limit: list.limit,
              offset: list.offset,
            }),
          },
          (value) =>
            recordsOf(value, "list_maintenance_plans").map((row) =>
              planOf(row, "list_maintenance_plans"),
            ),
        ),
      ),
    generateWorkOrders: () =>
      tenant().andThen((organizationId) =>
        call(
          "generate_maintenance_work_orders",
          { tenant: organizationId },
          (value) =>
            recordsOf(value, "generate_maintenance_work_orders").map((row) => ({
              planId: textOf(row["planId"]),
              workOrderId: textOf(row["workOrderId"]),
            })),
        ),
      ),
    createMeter: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "create_maintenance_meter",
          {
            tenant: organizationId,
            name: input.name,
            unit: input.unit,
            asset_id: input.assetId ?? null,
          },
          meter("create_maintenance_meter"),
        ),
      ),
    recordReading: (meterId, value, readAt) =>
      call(
        "record_meter_reading",
        {
          meter_id: meterId,
          value: String(value),
          read_at: readAt?.toString() ?? null,
        },
        meter("record_meter_reading"),
      ),
    listMeters: () =>
      tenant().andThen((organizationId) =>
        call("list_maintenance_meters", { tenant: organizationId }, (value) =>
          recordsOf(value, "list_maintenance_meters").map((row) =>
            meterOf(row, "list_maintenance_meters"),
          ),
        ),
      ),
    recordCalibration: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "record_calibration",
          {
            tenant: organizationId,
            input: definedOf({
              ...input,
              performedAt: input.performedAt.toString(),
              dueAt: input.dueAt.toString(),
            }),
          },
          (value) => calibrationOf(value, "record_calibration"),
        ),
      ),
    listCalibrations: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_calibrations",
          {
            tenant: organizationId,
            filters: definedOf({
              assetId: list.assetId,
              dueBefore: list.dueBefore?.toString(),
              limit: list.limit,
              offset: list.offset,
            }),
          },
          (value) =>
            recordsOf(value, "list_calibrations").map((row) =>
              calibrationOf(row, "list_calibrations"),
            ),
        ),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "maintenance",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
