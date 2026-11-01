import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult as AsyncResultType, Err } from "../../core/result.ts";
import type { FhirMedicationRequestOptions } from "../../fhir/medications.ts";
import type { FhirMedicationRequest } from "../../fhir/types.ts";
import type { PRESCRIPTION_STATUSES } from "../../sql/modules/e-prescribing-values.ts";
import type {
  MedicationCodeSystem,
  MedicationSchedule,
} from "../medications/medications.ts";
import type { BlockOptions, RecordRef } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import { toFhirPrescription } from "../../fhir/prescriptions.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  injectableOf,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

/** Where a prescription stands. */
export type PrescriptionStatus = (typeof PRESCRIPTION_STATUSES)[number];

const STATUSES: readonly PrescriptionStatus[] = [
  "draft",
  "signed",
  "sent",
  "dispensed",
  "cancelled",
];

const CODE_SYSTEMS: readonly MedicationCodeSystem[] = [
  "gtin",
  "hpk",
  "atc",
  "rxnorm",
  "custom",
];

/** The order a signature froze: what the pharmacy is asked to dispense. */
export interface PrescribedOrder {
  readonly orderId: string;
  readonly medicationId: string;
  readonly medicationName: string;
  readonly codeSystem: MedicationCodeSystem;
  readonly code?: string;
  readonly dose: number;
  readonly doseUnit: string;
  readonly route?: string;
  readonly schedule?: MedicationSchedule;
  readonly asNeeded: boolean;
  readonly asNeededReason?: string;
  readonly maxPerDay?: number;
  readonly startsOn: Temporal.PlainDate;
  readonly endsOn?: Temporal.PlainDate;
}

/** A prescription of one medication order. */
export interface Prescription {
  readonly id: string;
  readonly organizationId: string;
  readonly orderId: string;
  readonly subject: RecordRef;
  /** The member who may sign it. */
  readonly prescriberId: string;
  readonly prescriberName?: string;
  readonly status: PrescriptionStatus;
  /** The frozen order; set once the prescriber signs. */
  readonly order?: PrescribedOrder;
  readonly signedBy?: string;
  readonly signedAt?: Temporal.Instant;
  /** The key of the gateway that took it. */
  readonly gateway?: string;
  /** The gateway's id for it. */
  readonly gatewayReference?: string;
  readonly sentAt?: Temporal.Instant;
  /** Why the last delivery failed; the prescription stays signed. */
  readonly deliveryError?: string;
  readonly dispensedAt?: Temporal.Instant;
  readonly cancelledAt?: Temporal.Instant;
  readonly cancelReason?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface PrescriptionListOptions {
  readonly orderId?: string;
  readonly subject?: RecordRef;
  readonly status?: PrescriptionStatus;
  readonly prescriberId?: string;
  /** 1 to 200. Default 50. */
  readonly limit?: number;
  readonly offset?: number;
}

/** What a gateway gets to deliver. */
export interface PrescriptionDelivery {
  /** A signed prescription. */
  readonly prescription: Prescription;
  /** The prescription as a FHIR R4 `MedicationRequest`. */
  readonly medicationRequest: FhirMedicationRequest;
}

/** What a gateway gets to cancel a prescription it took. */
export interface PrescriptionCancellation {
  readonly prescription: Prescription;
  readonly reason: string;
}

/** What a gateway answers for a delivery. */
export interface PrescriptionReceipt {
  /** The gateway's id for the prescription, up to 200 characters. */
  readonly reference?: string;
}

/** What a gateway gets next to a request. */
export interface PrescriptionRequest {
  readonly signal?: AbortSignal;
}

/**
 * A channel to a pharmacy or a national prescription service. Write it in the
 * app or its own package; the block bundles no national format. It gets the
 * signed prescription and its FHIR R4 `MedicationRequest`, and answers with a
 * reference, or throws when it can't deliver.
 */
export interface PrescriptionGateway {
  /** The port contract version. Omitted means 1. */
  readonly apiVersion?: 1;
  /** Stored on the prescription as `gateway`, 1 to 100 characters. */
  readonly key: string;
  deliver(
    delivery: PrescriptionDelivery,
    request: PrescriptionRequest,
  ): PrescriptionReceipt | Promise<PrescriptionReceipt>;
  /**
   * Withdraws a prescription the gateway took. Called before a sent
   * prescription is cancelled; when it throws, the prescription stays sent.
   */
  cancel?(
    cancellation: PrescriptionCancellation,
    request: PrescriptionRequest,
  ): void | Promise<void>;
}

export interface EPrescribingClient {
  /**
   * Drafts a prescription for an active medication order. The signed-in member
   * becomes the prescriber; a service call names one with `prescriberId`. Needs
   * `e_prescribing.write`.
   */
  create(
    orderId: string,
    input?: {
      readonly prescriberId?: string;
      readonly prescriberName?: string;
    },
  ): AsyncResultType<Prescription>;
  /**
   * Signs a draft and freezes the order. Only the prescriber signs, as a
   * signed-in user with `e_prescribing.sign`.
   */
  sign(prescriptionId: string): AsyncResultType<Prescription>;
  /**
   * Delivers a signed prescription through the gateway and records the receipt.
   * When the gateway throws, the failure is stored on the prescription, it
   * stays signed, and the call is an error with hint
   * `PRESCRIPTION_DELIVERY_FAILED`. Needs `e_prescribing.write`.
   */
  send(
    prescriptionId: string,
    options?: { readonly signal?: AbortSignal },
  ): AsyncResultType<Prescription>;
  /** Marks a sent prescription as dispensed. Needs `e_prescribing.write`. */
  dispense(
    prescriptionId: string,
    options?: { readonly at?: Temporal.Instant },
  ): AsyncResultType<Prescription>;
  /**
   * Cancels a prescription that is not dispensed. A signed or sent one needs a
   * `reason`. Needs to be the prescriber or hold `e_prescribing.manage`.
   */
  cancel(
    prescriptionId: string,
    options?: { readonly reason?: string; readonly signal?: AbortSignal },
  ): AsyncResultType<Prescription>;
  get(prescriptionId: string): AsyncResultType<Prescription>;
  list(
    options?: PrescriptionListOptions,
  ): AsyncResultType<readonly Prescription[]>;
  /** The signed prescription as the `MedicationRequest` a gateway receives. */
  medicationRequest(
    prescriptionId: string,
  ): AsyncResultType<FhirMedicationRequest>;
}

/** Options for {@link createEPrescribing}. */
export interface EPrescribingOptions extends BlockOptions {
  /** Delivers signed prescriptions; `send` is an error without one. */
  readonly gateway?: PrescriptionGateway;
  /** Subject and user references and code systems of the FHIR request. */
  readonly fhir?: FhirMedicationRequestOptions;
  /** `before` and `after` hooks per method (ADR 0015). */
  readonly hooks?: NoInfer<BlockHooks<EPrescribingClient>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

const KEY_LENGTH = 100;
const REFERENCE_LENGTH = 200;
const ERROR_LENGTH = 1000;

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

const optionalNumber = (value: unknown): number | undefined =>
  value === null || value === undefined ? undefined : Number(value);

const dateOf = (value: unknown): Temporal.PlainDate =>
  temporal().PlainDate.from(textOf(value));

const optionalDate = (value: unknown): Temporal.PlainDate | undefined =>
  value === null || value === undefined ? undefined : dateOf(value);

function scheduleOf(value: unknown): MedicationSchedule | undefined {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return undefined;
  }

  const row = recordOf(value, "schedule");

  const list = (entry: unknown): readonly unknown[] | undefined =>
    Array.isArray(entry) ? entry : undefined;

  return {
    ...optional(
      "times",
      list(row["times"])?.map((time) => textOf(time)),
    ),
    ...optional("everyHours", optionalNumber(row["everyHours"])),
    ...optional("startTime", optionalText(row["startTime"])),
    ...optional("weekdays", list(row["weekdays"])?.map(Number)),
  };
}

function orderOf(value: unknown): PrescribedOrder | undefined {
  if (value === null || value === undefined) {
    return undefined;
  }

  const row = recordOf(value, "order");

  return {
    orderId: textOf(row["orderId"]),
    medicationId: textOf(row["medicationId"]),
    medicationName: textOf(row["medicationName"]),
    codeSystem: enumOrThrow(row["codeSystem"], CODE_SYSTEMS, "code system"),
    dose: Number(row["dose"]),
    doseUnit: textOf(row["doseUnit"]),
    asNeeded: row["asNeeded"] === true,
    startsOn: dateOf(row["startsOn"]),
    ...optional("code", optionalText(row["code"])),
    ...optional("route", optionalText(row["route"])),
    ...optional("schedule", scheduleOf(row["schedule"])),
    ...optional("asNeededReason", optionalText(row["asNeededReason"])),
    ...optional("maxPerDay", optionalNumber(row["maxPerDay"])),
    ...optional("endsOn", optionalDate(row["endsOn"])),
  };
}

function prescriptionOf(value: unknown, fn: string): Prescription {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    orderId: textOf(row["orderId"]),
    subject: { type: textOf(row["subjectType"]), id: textOf(row["subjectId"]) },
    prescriberId: textOf(row["prescriberId"]),
    status: enumOrThrow(row["status"], STATUSES, "prescription status"),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("prescriberName", optionalText(row["prescriberName"])),
    ...optional("order", orderOf(row["order"])),
    ...optional("signedBy", optionalText(row["signedBy"])),
    ...optional("signedAt", optionalInstant(row["signedAt"])),
    ...optional("gateway", optionalText(row["gateway"])),
    ...optional("gatewayReference", optionalText(row["gatewayReference"])),
    ...optional("sentAt", optionalInstant(row["sentAt"])),
    ...optional("deliveryError", optionalText(row["deliveryError"])),
    ...optional("dispensedAt", optionalInstant(row["dispensedAt"])),
    ...optional("cancelledAt", optionalInstant(row["cancelledAt"])),
    ...optional("cancelReason", optionalText(row["cancelReason"])),
  };
}

function gatewayOf(gateway: PrescriptionGateway): PrescriptionGateway {
  injectableOf("prescription gateway", gateway);

  if (gateway.key.trim() === "" || gateway.key.length > KEY_LENGTH) {
    throw new TypeError(
      `prescription gateway key "${gateway.key}" must be 1 to ${String(KEY_LENGTH)} characters`,
    );
  }

  return gateway;
}

const failure = (message: string, hint: string, status: number): Err =>
  err({ kind: "unexpected", message, status, hint });

const causeText = (cause: unknown): string =>
  cause instanceof Error ? cause.message : String(cause);

/**
 * E-prescribing: prescriptions over medication orders that the prescriber
 * signs, a gateway delivers as a FHIR R4 `MedicationRequest` and the pharmacy
 * dispenses. The gateway plugs in through the `PrescriptionGateway` port.
 */
export function createEPrescribing(
  options: EPrescribingOptions,
): EPrescribingClient {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResultType<string> => requireTenant(options.tenant);
  const gateway = options.gateway ? gatewayOf(options.gateway) : undefined;

  const one = (
    fn: string,
    args: Record<string, unknown>,
  ): AsyncResultType<Prescription> =>
    call(fn, args, (value) => prescriptionOf(value, fn));

  const get = (prescriptionId: string): AsyncResultType<Prescription> =>
    one("get_prescription", { prescription_id: prescriptionId });

  const requestOf = (
    prescription: Prescription,
  ): AsyncResultType<FhirMedicationRequest> =>
    AsyncResult.from(() => {
      const { order } = prescription;

      if (order === undefined || prescription.status === "draft") {
        return Promise.resolve(
          failure(
            "only a signed prescription has a medication request",
            "PRESCRIPTION_STATUS",
            409,
          ),
        );
      }

      return Promise.resolve(
        ok(toFhirPrescription({ ...prescription, order }, options.fhir)),
      );
    });

  const deliver = (
    prescription: Prescription,
    signal: AbortSignal | undefined,
  ): AsyncResultType<Prescription> =>
    requestOf(prescription).andThen((medicationRequest) =>
      AsyncResult.from(async () => {
        if (gateway === undefined) {
          return failure(
            "no prescription gateway is configured",
            "PRESCRIPTION_GATEWAY_MISSING",
            501,
          );
        }

        const request = signal ? { signal } : {};

        try {
          const receipt = await gateway.deliver(
            { prescription, medicationRequest },
            request,
          );

          return await one("record_prescription_delivery", {
            prescription_id: prescription.id,
            gateway: gateway.key,
            ...(receipt.reference === undefined
              ? {}
              : { reference: receipt.reference.slice(0, REFERENCE_LENGTH) }),
          });
        } catch (cause) {
          const message = `gateway ${gateway.key} failed: ${causeText(cause)}`;

          const recorded = await one("record_prescription_delivery", {
            prescription_id: prescription.id,
            gateway: gateway.key,
            error: message.slice(0, ERROR_LENGTH),
          });

          return recorded.ok
            ? failure(message, "PRESCRIPTION_DELIVERY_FAILED", 502)
            : recorded;
        }
      }),
    );

  const withdraw = (
    prescription: Prescription,
    reason: string | undefined,
    signal: AbortSignal | undefined,
  ): AsyncResultType<Prescription> =>
    AsyncResult.from(async () => {
      if (gateway?.cancel === undefined || prescription.status !== "sent") {
        return ok(prescription);
      }

      try {
        await gateway.cancel(
          { prescription, reason: reason ?? "" },
          signal ? { signal } : {},
        );

        return ok(prescription);
      } catch (cause) {
        return failure(
          `gateway ${gateway.key} could not cancel: ${causeText(cause)}`,
          "PRESCRIPTION_CANCEL_FAILED",
          502,
        );
      }
    });

  const client: EPrescribingClient = {
    create: (orderId, input = {}) =>
      tenant().andThen((organizationId) =>
        one("create_prescription", {
          tenant: organizationId,
          order_id: orderId,
          attrs: definedOf(input),
        }),
      ),
    sign: (prescriptionId) =>
      one("sign_prescription", { prescription_id: prescriptionId }),
    send: (prescriptionId, run = {}) =>
      get(prescriptionId).andThen((prescription) =>
        deliver(prescription, run.signal),
      ),
    dispense: (prescriptionId, run = {}) =>
      one("record_prescription_dispense", {
        prescription_id: prescriptionId,
        ...(run.at === undefined ? {} : { dispensed_at: run.at.toString() }),
      }),
    cancel: (prescriptionId, run = {}) =>
      get(prescriptionId)
        .andThen((prescription) =>
          withdraw(prescription, run.reason, run.signal),
        )
        .andThen(() =>
          one("cancel_prescription", {
            prescription_id: prescriptionId,
            ...(run.reason === undefined ? {} : { reason: run.reason }),
          }),
        ),
    get,
    list: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_prescriptions",
          {
            tenant: organizationId,
            filters: definedOf({
              orderId: list.orderId,
              subjectType: list.subject?.type,
              subjectId: list.subject?.id,
              status: list.status,
              prescriberId: list.prescriberId,
              limit: list.limit,
              offset: list.offset,
            }),
          },
          (value) =>
            recordsOf(value, "list_prescriptions").map((row) =>
              prescriptionOf(row, "list_prescriptions"),
            ),
        ),
      ),
    medicationRequest: (prescriptionId) =>
      get(prescriptionId).andThen(requestOf),
  };

  return withBlockHooks(client, options.hooks, {
    block: "e-prescribing",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
