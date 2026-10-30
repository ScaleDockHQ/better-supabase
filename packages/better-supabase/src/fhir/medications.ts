import type {
  Medication,
  MedicationAdministration,
  MedicationAdministrationStatus,
  MedicationCodeSystem,
  MedicationOrder,
  MedicationOrderImport,
  MedicationOrderStatus,
  MedicationSchedule,
} from "../blocks/medications/medications.ts";
import type { Result } from "../core/result.ts";
import type { FhirSubjectOptions, Untrusted } from "./shared.ts";
import type {
  FhirCodeableConcept,
  FhirCoding,
  FhirDayOfWeek,
  FhirDosage,
  FhirDoseAndRate,
  FhirIdentifier,
  FhirMedicationAdministration,
  FhirMedicationAdministrationDosage,
  FhirMedicationAdministrationPerformer,
  FhirMedicationAdministrationStatus,
  FhirMedicationRequest,
  FhirMedicationRequestStatus,
  FhirPeriod,
  FhirQuantity,
  FhirRatio,
  FhirReference,
  FhirTiming,
  FhirTimingRepeat,
} from "./types.ts";

import {
  compact,
  fhirTime,
  identifiers,
  Issues,
  notes,
  plainDateOf,
  referenceId,
  fieldsOf,
  itemsOf,
  subjectOf,
  text,
  UCUM,
  userOf,
  withTemporal,
} from "./shared.ts";

/**
 * The code system URI of each medications block code system. `custom` has none:
 * pass `customCodeSystem` for the app's own list.
 */
export const FHIR_MEDICATION_SYSTEMS: Readonly<
  Record<Exclude<MedicationCodeSystem, "custom">, string>
> = {
  gtin: "https://www.gs1.org/gtin",
  hpk: "urn:oid:2.16.840.1.113883.2.4.4.7",
  atc: "http://www.whocc.no/atc",
  rxnorm: "http://www.nlm.nih.gov/research/umls/rxnorm",
};

const PERFORM_FUNCTION =
  "http://terminology.hl7.org/CodeSystem/med-admin-perform-function";

const DAYS: readonly FhirDayOfWeek[] = [
  "mon",
  "tue",
  "wed",
  "thu",
  "fri",
  "sat",
  "sun",
];

/** ISO weekday numbers (1 is Monday) by FHIR day code. */
const WEEKDAY = new Map<unknown, number>(
  DAYS.map((day, index) => [day, index + 1]),
);

/** The medication fields the medication mappers read. */
export type FhirMedicationSource = Pick<
  Medication,
  "id" | "name" | "codeSystem"
> &
  Partial<Pick<Medication, "code">>;

/** The order fields the medication mappers read. */
export type FhirMedicationOrderSource = Pick<
  MedicationOrder,
  | "id"
  | "subject"
  | "medicationId"
  | "dose"
  | "doseUnit"
  | "asNeeded"
  | "startsOn"
  | "status"
> &
  Partial<
    Pick<
      MedicationOrder,
      | "route"
      | "schedule"
      | "asNeededReason"
      | "maxPerDay"
      | "endsOn"
      | "prescriber"
      | "externalId"
      | "stoppedReason"
    >
  > & {
    /** Present on `ordersOf` and `chart` rows. */
    readonly medication?: FhirMedicationSource;
  };

export interface FhirMedicationOptions extends FhirSubjectOptions {
  /** The code system URI of the `custom` code system. */
  readonly customCodeSystem?: string;
}

export interface FhirMedicationRequestOptions extends FhirMedicationOptions {
  /** The `system` of the identifier that carries `externalId`. */
  readonly identifierSystem?: string;
}

function requestStatusOf(
  status: MedicationOrderStatus,
): FhirMedicationRequestStatus {
  switch (status) {
    case "active": {
      return "active";
    }

    case "paused": {
      return "on-hold";
    }

    case "stopped": {
      return "stopped";
    }

    default: {
      const never: never = status;

      return never;
    }
  }
}

function systemOf(
  system: MedicationCodeSystem,
  custom: string | undefined,
): string | undefined {
  return system === "custom" ? custom : FHIR_MEDICATION_SYSTEMS[system];
}

/**
 * `medicationCodeableConcept` with the medication, else a `Medication`
 * reference.
 */
function medicationOf(
  order: FhirMedicationOrderSource,
  options: FhirMedicationOptions | undefined,
):
  | { readonly medicationCodeableConcept: FhirCodeableConcept }
  | { readonly medicationReference: FhirReference } {
  const { medication } = order;

  if (medication === undefined) {
    return {
      medicationReference: { reference: `Medication/${order.medicationId}` },
    };
  }

  return {
    medicationCodeableConcept:
      medication.code === undefined
        ? { text: medication.name }
        : {
            coding: [
              compact<FhirCoding>({
                system: systemOf(
                  medication.codeSystem,
                  options?.customCodeSystem,
                ),
                code: medication.code,
                display: medication.name,
              }),
            ],
            text: medication.name,
          },
  };
}

const timeOfDay = (time: string): string =>
  time.length === 5 ? `${time}:00` : time;

function timingOf(order: FhirMedicationOrderSource): FhirTiming {
  const schedule: MedicationSchedule = order.schedule ?? {};

  return {
    repeat: compact<FhirTimingRepeat>({
      boundsPeriod: compact<FhirPeriod>({
        start: fhirTime(order.startsOn),
        end: fhirTime(order.endsOn),
      }),
      timeOfDay: schedule.times?.map(timeOfDay),
      dayOfWeek: schedule.weekdays?.flatMap((day) => {
        const name = DAYS[day - 1];

        return name === undefined ? [] : [name];
      }),
      ...(schedule.everyHours === undefined
        ? {}
        : { frequency: 1, period: schedule.everyHours, periodUnit: "h" }),
    }),
  };
}

function dosageOf(order: FhirMedicationOrderSource): FhirDosage {
  const unit = order.doseUnit;

  return compact<FhirDosage>({
    timing: timingOf(order),
    ...(order.asNeeded
      ? order.asNeededReason === undefined
        ? { asNeededBoolean: true }
        : { asNeededCodeableConcept: { text: order.asNeededReason } }
      : {}),
    route: text(order.route),
    doseAndRate: [{ doseQuantity: { value: order.dose, unit } }],
    maxDosePerPeriod:
      order.maxPerDay === undefined
        ? undefined
        : {
            numerator: { value: order.maxPerDay, unit },
            denominator: { value: 1, unit: "d", system: UCUM, code: "d" },
          },
  });
}

/**
 * A medications block order as a FHIR R4 `MedicationRequest` with intent
 * `order`. An order from `ordersOf` or `chart` carries its medication's code;
 * otherwise the request references `Medication/<medicationId>`.
 */
export function toFhirMedicationRequest(
  order: FhirMedicationOrderSource,
  options?: FhirMedicationRequestOptions,
): FhirMedicationRequest {
  return compact<FhirMedicationRequest>({
    resourceType: "MedicationRequest",
    id: order.id,
    identifier: identifiers(order.externalId, options?.identifierSystem),
    status: requestStatusOf(order.status),
    statusReason: text(order.stoppedReason),
    intent: "order",
    ...medicationOf(order, options),
    subject: subjectOf(options, order.subject.id),
    requester:
      order.prescriber === undefined
        ? undefined
        : { display: order.prescriber },
    dosageInstruction: [dosageOf(order)],
  });
}

/** The administration fields `toFhirMedicationAdministration` reads. */
export type FhirMedicationAdministrationSource = Pick<
  MedicationAdministration,
  "id" | "orderId" | "status"
> &
  Partial<
    Pick<
      MedicationAdministration,
      | "scheduledAt"
      | "administeredAt"
      | "dose"
      | "performerId"
      | "checkedBy"
      | "reason"
      | "note"
    >
  >;

function administrationStatusOf(
  status: MedicationAdministrationStatus,
): FhirMedicationAdministrationStatus {
  switch (status) {
    case "given": {
      return "completed";
    }

    case "refused":
    case "skipped":
    case "missed": {
      return "not-done";
    }

    case "planned": {
      return "unknown";
    }

    default: {
      const never: never = status;

      return never;
    }
  }
}

function performersOf(
  administration: FhirMedicationAdministrationSource,
  options: FhirSubjectOptions | undefined,
): FhirMedicationAdministrationPerformer[] | undefined {
  const performers = [
    ["performer", userOf(options, administration.performerId)],
    ["verifier", userOf(options, administration.checkedBy)],
  ] as const;

  const list = performers.flatMap(([code, actor]) =>
    actor === undefined
      ? []
      : [{ function: { coding: [{ system: PERFORM_FUNCTION, code }] }, actor }],
  );

  return list.length === 0 ? undefined : list;
}

/**
 * A planned or recorded dose as a FHIR R4 `MedicationAdministration`. Its order
 * supplies the record, the medication, the dose unit and the route. Given doses
 * are `completed`; refused, skipped and missed ones `not-done` with the reason;
 * a planned dose, which FHIR has no status for, `unknown`.
 */
export function toFhirMedicationAdministration(
  administration: FhirMedicationAdministrationSource,
  order: FhirMedicationOrderSource,
  options?: FhirMedicationOptions,
): FhirMedicationAdministration {
  const { status } = administration;
  const notDone = administrationStatusOf(status) === "not-done";

  return compact<FhirMedicationAdministration>({
    resourceType: "MedicationAdministration",
    id: administration.id,
    status: administrationStatusOf(status),
    statusReason: notDone
      ? [{ text: administration.reason ?? status }]
      : undefined,
    ...medicationOf(order, options),
    subject: subjectOf(options, order.subject.id),
    effectiveDateTime: fhirTime(
      administration.administeredAt ?? administration.scheduledAt,
    ),
    performer: performersOf(administration, options),
    request: { reference: `MedicationRequest/${administration.orderId}` },
    note: notes(administration.note),
    dosage:
      administration.dose === undefined && order.route === undefined
        ? undefined
        : compact<FhirMedicationAdministrationDosage>({
            route: text(order.route),
            dose:
              administration.dose === undefined
                ? undefined
                : { value: administration.dose, unit: order.doseUnit },
          }),
  });
}

export interface FhirMedicationRequestImportOptions {
  /** The subject type the orders are on, such as `client`. */
  readonly subjectType: string;
  /** The record id. Default: the id in `subject.reference`. */
  readonly subjectId?: string;
}

const IMPORT_INTENTS = new Set([
  "order",
  "original-order",
  "reflex-order",
  "filler-order",
  "instance-order",
  "plan",
]);

const stringOf = (value: unknown): string | undefined =>
  typeof value === "string" && value !== "" ? value : undefined;

const firstOf = <T>(value: unknown): Untrusted<T> => itemsOf<T>(value)[0] ?? {};

const CODED_SYSTEMS = ["gtin", "hpk", "atc", "rxnorm"] as const;

const codeSystemOf = (system: unknown): MedicationCodeSystem =>
  CODED_SYSTEMS.find((key) => FHIR_MEDICATION_SYSTEMS[key] === system) ??
  "custom";

interface ImportedMedication {
  readonly medicationId?: string;
  readonly medication?: MedicationOrderImport["medication"];
}

function importMedication(
  resource: Untrusted<FhirMedicationRequest>,
  unit: string | undefined,
  issues: Issues,
): ImportedMedication | undefined {
  const reference = referenceId(
    fieldsOf<FhirReference>(resource.medicationReference),
  );

  if (reference !== undefined) {
    return { medicationId: reference };
  }

  const concept = fieldsOf<FhirCodeableConcept>(
    resource.medicationCodeableConcept,
  );

  const coding = firstOf<FhirCoding>(concept.coding);
  const code = stringOf(coding.code);
  const name = stringOf(concept.text) ?? stringOf(coding.display) ?? code;

  if (code === undefined || name === undefined) {
    issues.add(
      ["medicationCodeableConcept"],
      "medication needs a coded medication or a Medication reference",
    );

    return;
  }

  if (unit === undefined) {
    issues.add(
      ["dosageInstruction", 0, "doseAndRate", 0, "doseQuantity", "unit"],
      "dose needs a unit to add the medication",
    );

    return;
  }

  return {
    medication: { name, unit, codeSystem: codeSystemOf(coding.system), code },
  };
}

function importSchedule(
  repeat: Untrusted<FhirTimingRepeat>,
  issues: Issues,
): MedicationSchedule | undefined {
  const path = ["dosageInstruction", 0, "timing", "repeat"];

  const times = Array.isArray(repeat.timeOfDay)
    ? repeat.timeOfDay.filter((time) => typeof time === "string")
    : [];

  const weekdays = Array.isArray(repeat.dayOfWeek)
    ? repeat.dayOfWeek.flatMap((day) => {
        const weekday = WEEKDAY.get(day);

        return weekday === undefined ? [] : [weekday];
      })
    : [];

  const hourly =
    repeat.frequency === 1 &&
    repeat.periodUnit === "h" &&
    typeof repeat.period === "number"
      ? repeat.period
      : undefined;

  if (times.length === 0 && hourly === undefined) {
    issues.add(
      path,
      "timing needs timeOfDay, or a frequency of 1 every period hours",
    );

    return;
  }

  return compact<MedicationSchedule>({
    times:
      times.length === 0 ? undefined : times.map((time) => time.slice(0, 5)),
    everyHours: hourly,
    weekdays: weekdays.length === 0 ? undefined : weekdays,
  });
}

function maxPerDayOf(dosage: Untrusted<FhirDosage>): number | undefined {
  const ratio = fieldsOf<FhirRatio>(dosage.maxDosePerPeriod);
  const per = fieldsOf<FhirQuantity>(ratio.denominator);
  const { value } = fieldsOf<FhirQuantity>(ratio.numerator);

  return per.value === 1 &&
    (per.code === "d" || per.unit === "d") &&
    typeof value === "number"
    ? value
    : undefined;
}

/**
 * Reads a FHIR R4 `MedicationRequest` as an order for
 * `db.medications.importOrders`, such as one from a pharmacy feed. Only active
 * orders import; the first dosage instruction gives the dose, the route and the
 * schedule. A resource the block can't store returns a `validation` error with
 * one issue per problem.
 */
export function fromFhirMedicationRequest(
  input: unknown,
  options: FhirMedicationRequestImportOptions,
): Result<MedicationOrderImport> {
  const issues = new Issues();
  const resource = fieldsOf<FhirMedicationRequest>(input);

  if (resource.resourceType !== "MedicationRequest") {
    issues.add(["resourceType"], "resourceType must be MedicationRequest");

    return issues.failure("MedicationRequest");
  }

  if (resource.status !== "active") {
    issues.add(["status"], `status ${String(resource.status)} is not active`);
  }

  if (!IMPORT_INTENTS.has(String(resource.intent))) {
    issues.add(["intent"], `intent ${String(resource.intent)} is not an order`);
  }

  const externalId = issues.required(
    stringOf(firstOf<FhirIdentifier>(resource.identifier).value) ??
      stringOf(resource.id),
    ["id"],
    "id or identifier is required to import once",
  );

  const subjectId = issues.required(
    options.subjectId ?? referenceId(fieldsOf<FhirReference>(resource.subject)),
    ["subject"],
    "subject must reference the record",
  );

  const dosage = firstOf<FhirDosage>(resource.dosageInstruction);

  const quantity = fieldsOf<FhirQuantity>(
    firstOf<FhirDoseAndRate>(dosage.doseAndRate).doseQuantity,
  );

  const dose = issues.required(
    typeof quantity.value === "number" ? quantity.value : undefined,
    ["dosageInstruction", 0, "doseAndRate", 0, "doseQuantity"],
    "dosageInstruction needs a dose quantity",
  );

  const doseUnit = stringOf(quantity.unit) ?? stringOf(quantity.code);
  const medication = importMedication(resource, doseUnit, issues);

  const asNeededReason = stringOf(
    fieldsOf<FhirCodeableConcept>(dosage.asNeededCodeableConcept).text,
  );

  const asNeeded =
    dosage.asNeededBoolean === true || asNeededReason !== undefined;

  const repeat = fieldsOf<FhirTimingRepeat>(
    fieldsOf<FhirTiming>(dosage.timing).repeat,
  );

  const schedule = asNeeded ? undefined : importSchedule(repeat, issues);
  const bounds = fieldsOf<FhirPeriod>(repeat.boundsPeriod);

  const startsOn = plainDateOf(
    bounds.start ?? resource.authoredOn,
    ["dosageInstruction", 0, "timing", "repeat", "boundsPeriod", "start"],
    issues,
  );

  const endsOn = plainDateOf(
    bounds.end,
    ["dosageInstruction", 0, "timing", "repeat", "boundsPeriod", "end"],
    issues,
  );

  const route = fieldsOf<FhirCodeableConcept>(dosage.route);

  if (
    !issues.empty ||
    externalId === undefined ||
    subjectId === undefined ||
    dose === undefined ||
    medication === undefined
  ) {
    return issues.failure("MedicationRequest");
  }

  return withTemporal((time) =>
    compact<MedicationOrderImport>({
      subject: { type: options.subjectType, id: subjectId },
      externalId,
      ...medication,
      dose,
      doseUnit,
      route:
        stringOf(route.text) ??
        stringOf(firstOf<FhirCoding>(route.coding).display),
      schedule,
      asNeeded: asNeeded ? true : undefined,
      asNeededReason,
      maxPerDay: maxPerDayOf(dosage),
      startsOn:
        startsOn === undefined ? undefined : time.PlainDate.from(startsOn),
      endsOn: endsOn === undefined ? undefined : time.PlainDate.from(endsOn),
      prescriber: stringOf(fieldsOf<FhirReference>(resource.requester).display),
    }),
  );
}
