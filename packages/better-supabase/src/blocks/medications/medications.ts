import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { BlockTemporalOptions, RecordRef } from "../shared.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  errorText,
  injectableOf,
  instantArg,
  instantOf,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
} from "../shared.ts";

/** Where a medication's code comes from. `custom` is the app's own list. */
export type MedicationCodeSystem = "gtin" | "hpk" | "atc" | "rxnorm" | "custom";

/** Who wrote an order: a prescriber in the app, a pharmacy feed or an import. */
export type MedicationOrderSource = "prescriber" | "pharmacy" | "import";

/** `paused` plans no doses until it resumes; `stopped` is final. */
export type MedicationOrderStatus = "active" | "paused" | "stopped";

/**
 * `planned`: due and not yet recorded. `given`, `refused` and `skipped` are
 * recorded by a member; `missed` is set by `markMissed` once a planned dose is
 * late.
 */
export type MedicationAdministrationStatus =
  | "planned"
  | "given"
  | "refused"
  | "skipped"
  | "missed";

/** A medication in the organization's list. */
export interface Medication {
  readonly id: string;
  readonly organizationId: string;
  readonly name: string;
  readonly codeSystem: MedicationCodeSystem;
  readonly code?: string;
  readonly form?: string;
  readonly strength?: string;
  /** The unit a dose is counted in, such as `mg` or `tablet`. */
  readonly unit: string;
  /** A high-risk medication needs a second member to check every dose. */
  readonly highRisk: boolean;
  readonly archivedAt?: Temporal.Instant;
  /**
   * The extra columns (`blocks.medications.options.medicationExtraColumns`),
   * keyed by database name.
   */
  readonly fields?: Readonly<Record<string, unknown>>;
}

/** What `saveMedication` takes. */
export interface MedicationInput {
  readonly name: string;
  readonly unit: string;
  readonly codeSystem?: MedicationCodeSystem;
  readonly code?: string;
  readonly form?: string;
  readonly strength?: string;
  readonly highRisk?: boolean;
  /** Updates this medication instead of adding one. */
  readonly medicationId?: string;
  /** Values for `medicationExtraColumns`, keyed by database name. */
  readonly fields?: Readonly<Record<string, unknown>>;
}

/** A medication as a drug database returns it, for `importMedication`. */
export interface MedicationCatalogItem {
  readonly name: string;
  readonly unit: string;
  readonly codeSystem: MedicationCodeSystem;
  readonly code: string;
  readonly form?: string;
  readonly strength?: string;
  readonly highRisk?: boolean;
}

/**
 * A drug database: G-Standaard, a national formulary, RxNorm or the app's own
 * list. Wrap its API in the app; the block bundles no drug data.
 */
export interface MedicationCatalog {
  /** The catalog contract version. Omitted means 1. */
  readonly apiVersion?: 1;
  search(
    query: string,
    options?: { readonly signal?: AbortSignal },
  ): Promise<readonly MedicationCatalogItem[]>;
  /** The item with this code, or `undefined` when there is none. */
  get(
    code: string,
    options?: { readonly signal?: AbortSignal },
  ): Promise<MedicationCatalogItem | undefined>;
}

/**
 * When a scheduled order's doses fall, in the block's time zone: the `times` of
 * day (`HH:MM`), or every `everyHours` hours from `startTime`. `weekdays` (ISO,
 * 1 is Monday) limits the days; every day when left out.
 */
export interface MedicationSchedule {
  readonly times?: readonly string[];
  readonly everyHours?: number;
  readonly startTime?: string;
  readonly weekdays?: readonly number[];
}

/** What `prescribe` takes. */
export interface MedicationOrderInput<F extends object = Record<never, never>> {
  readonly dose: number;
  /** Defaults to the medication's unit. */
  readonly doseUnit?: string;
  readonly route?: string;
  /** Required unless `asNeeded` is set. */
  readonly schedule?: MedicationSchedule;
  /** Given when needed (PRN), with `recordAsNeeded`. */
  readonly asNeeded?: boolean;
  readonly asNeededReason?: string;
  /** The most of the dose unit given in 24 hours, for as-needed doses. */
  readonly maxPerDay?: number;
  /** Defaults to today in the block's time zone. */
  readonly startsOn?: Temporal.PlainDate;
  readonly endsOn?: Temporal.PlainDate;
  /** The prescriber's name or registration number. */
  readonly prescriber?: string;
  /** A second member checks every dose, as for a high-risk medication. */
  readonly requiresDoubleCheck?: boolean;
  /** The extra columns to set. */
  readonly fields?: Partial<F>;
}

/** What `updateOrder` takes: a key left out keeps its value, `null` clears it. */
export interface MedicationOrderPatch<F extends object = Record<never, never>> {
  readonly dose?: number;
  readonly doseUnit?: string;
  readonly route?: string | null;
  readonly schedule?: MedicationSchedule | null;
  readonly asNeeded?: boolean;
  readonly asNeededReason?: string | null;
  readonly maxPerDay?: number | null;
  readonly startsOn?: Temporal.PlainDate;
  readonly endsOn?: Temporal.PlainDate | null;
  readonly prescriber?: string | null;
  readonly requiresDoubleCheck?: boolean;
  /** The extra columns to change; a key left out keeps its value. */
  readonly fields?: Partial<F>;
}

/** One order of `importOrders`, from a pharmacy feed or another system. */
export interface MedicationOrderImport<
  F extends object = Record<never, never>,
> extends MedicationOrderInput<F> {
  readonly subject: RecordRef;
  /** The order's id in the source; an id imported before is skipped. */
  readonly externalId: string;
  /** A medication in the list, or a catalog item to add or update. */
  readonly medicationId?: string;
  readonly medication?: MedicationCatalogItem;
  /** Default `import`. */
  readonly source?: MedicationOrderSource;
}

/** A medication prescribed for a record. */
export interface MedicationOrder<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  readonly subject: RecordRef;
  readonly medicationId: string;
  readonly dose: number;
  readonly doseUnit: string;
  readonly route?: string;
  readonly schedule?: MedicationSchedule;
  readonly asNeeded: boolean;
  readonly asNeededReason?: string;
  readonly maxPerDay?: number;
  readonly startsOn: Temporal.PlainDate;
  readonly endsOn?: Temporal.PlainDate;
  readonly prescriber?: string;
  readonly source: MedicationOrderSource;
  readonly externalId?: string;
  readonly requiresDoubleCheck: boolean;
  readonly status: MedicationOrderStatus;
  readonly stoppedReason?: string;
  /** The prescriber's signature, set by `approveOrder`. */
  readonly signatureId?: string;
  readonly createdBy?: string;
  /** The extra columns, keyed by database name. */
  readonly fields: ExtraFields<F>;
}

/** An order with its medication, as `ordersOf` and `chart` return it. */
export interface MedicationOrderWithMedication<
  F extends object = Record<never, never>,
> extends MedicationOrder<F> {
  readonly medication: Medication;
}

/** A planned or recorded dose. */
export interface MedicationAdministration {
  readonly id: string;
  readonly organizationId: string;
  readonly orderId: string;
  /** Left out for an as-needed dose. */
  readonly scheduledAt?: Temporal.Instant;
  readonly administeredAt?: Temporal.Instant;
  readonly status: MedicationAdministrationStatus;
  readonly dose?: number;
  readonly performerId?: string;
  /** The member who checked a high-risk dose. */
  readonly checkedBy?: string;
  /** Why a dose was refused, skipped or given as needed. */
  readonly reason?: string;
  readonly note?: string;
  /** The member's signature on the dose, when it was recorded with one. */
  readonly signatureId?: string;
  /**
   * The extra columns
   * (`blocks.medications.options.administrationExtraColumns`), keyed by
   * database name.
   */
  readonly fields?: Readonly<Record<string, unknown>>;
}

/** What `recordAdministration` takes. */
export interface MedicationAdministrationInput {
  readonly status: "given" | "refused" | "skipped";
  /** Defaults to the planned dose. */
  readonly dose?: number;
  /** Required when refused or skipped. */
  readonly reason?: string;
  /** Required for a high-risk dose: another member who may administer. */
  readonly checkedBy?: string;
  readonly note?: string;
  /**
   * The caller's completed signature on the dose (subject type
   * `medication_administration`, the dose's id). Needs the signatures block.
   */
  readonly signatureId?: string;
  /** Values for `administrationExtraColumns`, keyed by database name. */
  readonly fields?: Readonly<Record<string, unknown>>;
}

/** What `recordAsNeeded` takes. */
export interface MedicationAsNeededInput {
  readonly reason: string;
  /** Defaults to the order's dose. */
  readonly dose?: number;
  readonly checkedBy?: string;
  readonly note?: string;
  /** Values for `administrationExtraColumns`, keyed by database name. */
  readonly fields?: Readonly<Record<string, unknown>>;
}

/** A record's medication chart: the orders in a range and their doses. */
export interface MedicationChart<F extends object = Record<never, never>> {
  readonly since: Temporal.Instant;
  readonly until: Temporal.Instant;
  readonly orders: readonly MedicationOrderWithMedication<F>[];
  readonly administrations: readonly MedicationAdministration[];
}

export interface MedicationsOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  /**
   * The transport for `importOrders` and `markMissed`, which only the service
   * role may call: a service-role client on the server. Defaults to
   * `transport`.
   */
  readonly service?: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`.
   */
  readonly schema?: string;
  /** The drug database for `searchCatalog` and `importFromCatalog`. */
  readonly catalog?: MedicationCatalog;
  /**
   * A Standard Schema for the order's extra columns
   * (`blocks.medications.options.extraColumns`), keyed by database name. It
   * types and parses them on reads, and validates them on writes.
   */
  readonly fields?: S;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<Medications<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

export interface Medications<F extends object = Record<never, never>> {
  /** Adds a medication to the list, or updates `input.medicationId`. */
  saveMedication(input: {
    organizationId: string;
    input: MedicationInput;
  }): AsyncResult<Medication>;
  /** Takes a medication off the list; its orders keep it. */
  archiveMedication(medicationId: string): AsyncResult<Medication>;
  /** Adds a catalog item, or updates the one with its code system and code. */
  importMedication(input: {
    organizationId: string;
    item: MedicationCatalogItem;
  }): AsyncResult<Medication>;
  /** The organization's medications by name. */
  medications(
    input: { organizationId: string } & {
      readonly search?: string;
      readonly includeArchived?: boolean;
    },
  ): AsyncResult<readonly Medication[]>;
  /** Searches the `catalog` the client was given. */
  searchCatalog(
    input: { query: string } & { readonly signal?: AbortSignal },
  ): AsyncResult<readonly MedicationCatalogItem[]>;
  /** Reads a code from the `catalog` and adds it to the list. */
  importFromCatalog(
    input: { organizationId: string; code: string } & {
      readonly signal?: AbortSignal;
    },
  ): AsyncResult<Medication>;
  /** Prescribes a medication for a record. */
  prescribe(input: {
    organizationId: string;
    subject: RecordRef;
    medicationId: string;
    input: MedicationOrderInput<F>;
  }): AsyncResult<MedicationOrder<F>>;
  /**
   * Imports orders from a pharmacy or another system, skipping the external ids
   * imported before. Service role only.
   */
  importOrders(input: {
    organizationId: string;
    orders: readonly MedicationOrderImport<F>[];
  }): AsyncResult<{
    readonly created: readonly MedicationOrder<F>[];
    readonly skipped: number;
  }>;
  /** Changes an order; the planned doses after now are planned again. */
  updateOrder(input: {
    orderId: string;
    patch: MedicationOrderPatch<F>;
  }): AsyncResult<MedicationOrder<F>>;
  /** Pauses an order and removes its planned doses after now. */
  pauseOrder(orderId: string): AsyncResult<MedicationOrder<F>>;
  resumeOrder(orderId: string): AsyncResult<MedicationOrder<F>>;
  /** Stops an order for good. */
  /**
   * Approves an order with the caller's completed signature on it (subject type
   * `medication_order`, the order's id). Needs the signatures block.
   */
  approveOrder(input: {
    orderId: string;
    signatureId: string;
  }): AsyncResult<MedicationOrder<F>>;
  stopOrder(input: {
    orderId: string;
    reason: string;
  }): AsyncResult<MedicationOrder<F>>;
  /** A record's orders, newest first; stopped ones only when asked. */
  ordersOf(
    input: { subject: RecordRef } & { readonly includeStopped?: boolean },
  ): AsyncResult<readonly MedicationOrderWithMedication<F>[]>;
  /**
   * Plans the doses of the active scheduled orders up to `until`, at most 31
   * days ahead. Run it from a daily job. Returns the doses it added.
   */
  planAdministrations(input: {
    organizationId: string;
    until: Temporal.Instant;
  }): AsyncResult<number>;
  /** Records a planned or missed dose as given, refused or skipped. */
  recordAdministration(input: {
    administrationId: string;
    input: MedicationAdministrationInput;
  }): AsyncResult<MedicationAdministration>;
  /** Records a dose of an as-needed order, within its `maxPerDay`. */
  recordAsNeeded(input: {
    orderId: string;
    input: MedicationAsNeededInput;
  }): AsyncResult<MedicationAdministration>;
  /**
   * Marks the planned doses past `missedAfterMinutes` as missed and notifies
   * the members who manage medications. Service role only; run it from a job.
   */
  markMissed(): AsyncResult<number>;
  /** A record's chart, today in the block's time zone by default. */
  chart(
    input: { subject: RecordRef } & {
      readonly since?: Temporal.Instant;
      readonly until?: Temporal.Instant;
    },
  ): AsyncResult<MedicationChart<F>>;
  /**
   * Prescribes the order, then plans the administrations of the organization up
   * to `until`, so the first doses are on the chart when it returns.
   */
  prescribeAndPlan(input: {
    organizationId: string;
    subject: RecordRef;
    medicationId: string;
    input: MedicationOrderInput<F>;
    until: Temporal.Instant;
  }): AsyncResult<{
    readonly order: MedicationOrder<F>;
    readonly planned: number;
  }>;
}

const CODE_SYSTEMS = ["gtin", "hpk", "atc", "rxnorm", "custom"] as const;
const SOURCES = ["prescriber", "pharmacy", "import"] as const;
const ORDER_STATUSES = ["active", "paused", "stopped"] as const;

const ADMINISTRATION_STATUSES = [
  "planned",
  "given",
  "refused",
  "skipped",
  "missed",
] as const;

function optional<K extends string, V>(
  key: K,
  value: V | undefined,
): { readonly [P in K]?: V } {
  // SAFETY: a one-key object literal for the key the caller names.
  return (value === undefined ? {} : { [key]: value }) as {
    readonly [P in K]?: V;
  };
}

const numberOf = (value: unknown): number =>
  typeof value === "number" ? value : Number(value ?? 0);

const optionalNumber = (value: unknown): number | undefined =>
  value === null || value === undefined ? undefined : numberOf(value);

const dateOf = (value: unknown): Temporal.PlainDate =>
  temporal().PlainDate.from(textOf(value));

const optionalDate = (value: unknown): Temporal.PlainDate | undefined =>
  value === null || value === undefined ? undefined : dateOf(value);

function scheduleOf(value: unknown): MedicationSchedule | undefined {
  if (!isRecord(value)) {
    return undefined;
  }

  const times = Array.isArray(value["times"])
    ? value["times"].map((time) => textOf(time))
    : undefined;

  const weekdays = Array.isArray(value["weekdays"])
    ? value["weekdays"].map((day) => numberOf(day))
    : undefined;

  return {
    ...optional("times", times),
    ...optional("everyHours", optionalNumber(value["everyHours"])),
    ...optional("startTime", optionalText(value["startTime"])),
    ...optional("weekdays", weekdays),
  };
}

/**
 * The `fields` object of a medication or dose, or undefined without extra
 * columns.
 */
const extraFieldsOf = (
  value: unknown,
): Readonly<Record<string, unknown>> | undefined =>
  isRecord(value) ? value : undefined;

/** The `fields` argument, left out when the call sets none. */
const fieldsArg = (
  fields: Readonly<Record<string, unknown>> | undefined,
): { readonly fields?: Readonly<Record<string, unknown>> } =>
  fields === undefined ? {} : { fields };

function medicationOf(value: unknown, fn: string): Medication {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    name: textOf(row["name"]),
    codeSystem: enumOrThrow(row["codeSystem"], CODE_SYSTEMS, "codeSystem"),
    ...optional("code", optionalText(row["code"])),
    ...optional("form", optionalText(row["form"])),
    ...optional("strength", optionalText(row["strength"])),
    unit: textOf(row["unit"]),
    highRisk: row["highRisk"] === true,
    ...optional("archivedAt", optionalInstant(row["archivedAt"])),
    ...optional("fields", extraFieldsOf(row["fields"])),
  };
}

function orderOf(value: unknown, fn: string): MedicationOrder {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    subject: { type: textOf(row["subjectType"]), id: textOf(row["subjectId"]) },
    medicationId: textOf(row["medicationId"]),
    dose: numberOf(row["dose"]),
    doseUnit: textOf(row["doseUnit"]),
    ...optional("route", optionalText(row["route"])),
    ...optional("schedule", scheduleOf(row["schedule"])),
    asNeeded: row["asNeeded"] === true,
    ...optional("asNeededReason", optionalText(row["asNeededReason"])),
    ...optional("maxPerDay", optionalNumber(row["maxPerDay"])),
    startsOn: dateOf(row["startsOn"]),
    ...optional("endsOn", optionalDate(row["endsOn"])),
    ...optional("prescriber", optionalText(row["prescriber"])),
    source: enumOrThrow(row["source"], SOURCES, "source"),
    ...optional("externalId", optionalText(row["externalId"])),
    requiresDoubleCheck: row["requiresDoubleCheck"] === true,
    status: enumOrThrow(row["status"], ORDER_STATUSES, "status"),
    ...optional("stoppedReason", optionalText(row["stoppedReason"])),
    ...optional("signatureId", optionalText(row["signatureId"])),
    ...optional("createdBy", optionalText(row["createdBy"])),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
  };
}

function orderWithMedicationOf(
  value: unknown,
  fn: string,
): MedicationOrderWithMedication {
  const row = recordOf(value, fn);

  return {
    ...orderOf(row, fn),
    medication: medicationOf(row["medication"], fn),
  };
}

function administrationOf(
  value: unknown,
  fn: string,
): MedicationAdministration {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    orderId: textOf(row["orderId"]),
    ...optional("scheduledAt", optionalInstant(row["scheduledAt"])),
    ...optional("administeredAt", optionalInstant(row["administeredAt"])),
    status: enumOrThrow(row["status"], ADMINISTRATION_STATUSES, "status"),
    ...optional("dose", optionalNumber(row["dose"])),
    ...optional("performerId", optionalText(row["performerId"])),
    ...optional("checkedBy", optionalText(row["checkedBy"])),
    ...optional("reason", optionalText(row["reason"])),
    ...optional("note", optionalText(row["note"])),
    ...optional("signatureId", optionalText(row["signatureId"])),
    ...optional("fields", extraFieldsOf(row["fields"])),
  };
}

function chartOf(value: unknown, fn: string): MedicationChart {
  const row = recordOf(value, fn);

  return {
    since: instantOf(row["since"]),
    until: instantOf(row["until"]),
    orders: recordsOf(row["orders"], fn).map((order) =>
      orderWithMedicationOf(order, fn),
    ),
    administrations: recordsOf(row["administrations"], fn).map((dose) =>
      administrationOf(dose, fn),
    ),
  };
}

/**
 * The attrs of a write: the keys the input sets, dates as ISO text, and the
 * extra columns `fields` checked.
 */
function attrsOf(
  input: MedicationOrderInput<object> | MedicationOrderPatch<object>,
  checked: Readonly<Record<string, unknown>> | undefined,
): Record<string, unknown> {
  const { startsOn, endsOn, fields: _fields, ...rest } = input;

  return {
    ...rest,
    ...(checked === undefined ? {} : { fields: checked }),
    ...(startsOn === undefined ? {} : { startsOn: startsOn.toString() }),
    ...(endsOn === undefined ? {} : { endsOn: endsOn?.toString() ?? null }),
  };
}

const many =
  <T>(fn: string, of: (value: unknown, fn: string) => T) =>
  (value: unknown): readonly T[] =>
    recordsOf(value, fn).map((row) => of(row, fn));

const one =
  <T>(fn: string, of: (value: unknown, fn: string) => T) =>
  (value: unknown): T =>
    of(value, fn);

/** Runs a catalog call, its throw as an `unexpected` error. */
const provider = <T>(run: () => Promise<T>): AsyncResult<T> =>
  AsyncResult.from(async () => {
    try {
      return ok(await run());
    } catch (cause) {
      return err(
        dbError("unexpected", errorText(cause), {
          hint: "MEDICATION_CATALOG_FAILED",
        }),
      );
    }
  });

const signalOf = (options: {
  readonly signal?: AbortSignal;
}): { readonly signal?: AbortSignal } =>
  options.signal === undefined ? {} : { signal: options.signal };

/**
 * The medications block: an organization's medication list, orders on any
 * record registered in `config.subjects`, and the doses planned and recorded
 * against them, for a medication chart.
 */
export function createMedications<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: MedicationsOptions<S>): Medications<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const service = blockCall(
    options.service ?? options.transport,
    options.schema,
    options.mappers,
  );

  const catalog = injectableOf("medication catalog", options.catalog);

  const fields: BlockFields<F> = blockFields(
    options.fields,
    "medication order fields",
  );

  /** Checks the extra columns of each order, stopping at the first rejected. */
  const checkAll = (
    orders: readonly MedicationOrderImport<F>[],
  ): AsyncResult<(Readonly<Record<string, unknown>> | undefined)[]> =>
    AsyncResult.from(async () => {
      const checked: (Readonly<Record<string, unknown>> | undefined)[] = [];

      for (const order of orders) {
        const result = await fields.args(order.fields);

        if (!result.ok) {
          return result;
        }

        checked.push(result.data);
      }

      return ok(checked);
    });

  const noCatalog = <T>(): AsyncResult<T> =>
    AsyncResult.err(
      dbError("invalid_request", "createMedications has no catalog", {
        hint: "MEDICATION_NO_CATALOG",
      }),
    );

  const importMedication: Medications<F>["importMedication"] = ({
    organizationId,
    item,
  }) =>
    call(
      "import_medication",
      { tenant: organizationId, item },
      one("import_medication", medicationOf),
    );

  const pause = (orderId: string, paused: boolean) =>
    call(
      "pause_medication_order",
      { order_id: orderId, paused },
      one("pause_medication_order", orderOf),
    ).andThen(fields.row);

  const client: Medications<F> = {
    saveMedication: ({ organizationId, input }) =>
      call(
        "save_medication",
        {
          tenant: organizationId,
          name: input.name,
          unit: input.unit,
          code_system: input.codeSystem ?? "custom",
          code: input.code ?? null,
          form: input.form ?? null,
          strength: input.strength ?? null,
          high_risk: input.highRisk ?? false,
          medication_id: input.medicationId ?? null,
          ...fieldsArg(input.fields),
        },
        one("save_medication", medicationOf),
      ),
    archiveMedication: (medicationId) =>
      call(
        "archive_medication",
        { medication_id: medicationId },
        one("archive_medication", medicationOf),
      ),
    importMedication,
    medications: ({ organizationId, ...list }) =>
      call(
        "list_medications",
        {
          tenant: organizationId,
          search: list.search ?? null,
          include_archived: list.includeArchived ?? false,
        },
        many("list_medications", medicationOf),
      ),
    searchCatalog: ({ query, ...search }) =>
      catalog === undefined
        ? noCatalog()
        : provider(() => catalog.search(query, signalOf(search))),
    importFromCatalog: ({ organizationId, code, ...read }) =>
      catalog === undefined
        ? noCatalog()
        : provider(() => catalog.get(code, signalOf(read))).andThen((item) =>
            item === undefined
              ? AsyncResult.err(
                  dbError("not_found", `the catalog has no ${code}`, {
                    hint: "MEDICATION_NOT_FOUND",
                  }),
                )
              : importMedication({ organizationId, item }),
          ),
    prescribe: ({ organizationId, subject, medicationId, input }) =>
      fields
        .args(input.fields)
        .andThen((checked) =>
          call(
            "prescribe_medication",
            {
              tenant: organizationId,
              subject_type: subject.type,
              subject_id: subject.id,
              medication_id: medicationId,
              attrs: attrsOf(input, checked),
            },
            one("prescribe_medication", orderOf),
          ).andThen(fields.row),
        ),
    importOrders: ({ organizationId, orders }) =>
      checkAll(orders).andThen((checked) =>
        service(
          "import_medication_orders",
          {
            tenant: organizationId,
            items: orders.map(({ subject, ...order }, index) => ({
              ...attrsOf(order, checked[index]),
              subjectType: subject.type,
              subjectId: subject.id,
            })),
          },
          (value) => {
            const row = recordOf(value, "import_medication_orders");

            return {
              created: many(
                "import_medication_orders",
                orderOf,
              )(row["created"]),
              skipped: numberOf(row["skipped"]),
            };
          },
        ).andThen((result) =>
          fields
            .rows(result.created)
            .map((created) => ({ created, skipped: result.skipped })),
        ),
      ),
    updateOrder: ({ orderId, patch }) =>
      fields
        .args(patch.fields)
        .andThen((checked) =>
          call(
            "update_medication_order",
            { order_id: orderId, attrs: attrsOf(patch, checked) },
            one("update_medication_order", orderOf),
          ).andThen(fields.row),
        ),
    pauseOrder: (orderId) => pause(orderId, true),
    resumeOrder: (orderId) => pause(orderId, false),
    approveOrder: ({ orderId, signatureId }) =>
      call(
        "approve_medication_order",
        { order_id: orderId, signature_id: signatureId },
        one("approve_medication_order", orderOf),
      ).andThen(fields.row),
    stopOrder: ({ orderId, reason }) =>
      call(
        "stop_medication_order",
        { order_id: orderId, reason },
        one("stop_medication_order", orderOf),
      ).andThen(fields.row),
    ordersOf: ({ subject, ...list }) =>
      call(
        "medication_orders_of",
        {
          subject_type: subject.type,
          subject_id: subject.id,
          include_stopped: list.includeStopped ?? false,
        },
        many("medication_orders_of", orderWithMedicationOf),
      ).andThen(fields.rows),
    planAdministrations: ({ organizationId, until }) =>
      call(
        "plan_medication_administrations",
        { tenant: organizationId, until: instantArg(until) },
        numberOf,
      ),
    recordAdministration: ({ administrationId, input }) =>
      call(
        "record_medication_administration",
        {
          administration_id: administrationId,
          status: input.status,
          dose: input.dose ?? null,
          reason: input.reason ?? null,
          checked_by: input.checkedBy ?? null,
          note: input.note ?? null,
          ...(input.signatureId === undefined
            ? {}
            : { signature_id: input.signatureId }),
          ...fieldsArg(input.fields),
        },
        one("record_medication_administration", administrationOf),
      ),
    recordAsNeeded: ({ orderId, input }) =>
      call(
        "record_as_needed_administration",
        {
          order_id: orderId,
          dose: input.dose ?? null,
          reason: input.reason,
          checked_by: input.checkedBy ?? null,
          note: input.note ?? null,
          ...fieldsArg(input.fields),
        },
        one("record_as_needed_administration", administrationOf),
      ),
    markMissed: () =>
      service("mark_missed_medication_administrations", {}, numberOf),
    chart: ({ subject, ...range }) =>
      call(
        "medication_chart",
        {
          subject_type: subject.type,
          subject_id: subject.id,
          ...optional("since", instantArg(range.since)),
          ...optional("until", instantArg(range.until)),
        },
        one("medication_chart", chartOf),
      ).andThen((chart) =>
        fields.rows(chart.orders).map((orders) => ({ ...chart, orders })),
      ),
    prescribeAndPlan: ({ until, ...prescription }) =>
      hooked
        .prescribe(prescription)
        .andThen((order) =>
          hooked
            .planAdministrations({
              organizationId: prescription.organizationId,
              until,
            })
            .map((planned) => ({ order, planned })),
        ),
  };

  // Helpers call the hooked client, so app hooks see each step.
  const hooked: Medications<F> = withBlockHooks(client, options.hooks, {
    block: "medications",
    ...(options.logger ? { logger: options.logger } : {}),
  });

  return hooked;
}
