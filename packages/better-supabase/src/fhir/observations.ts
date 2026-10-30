import type {
  Observation,
  ObservationComponent,
  ObservationDefinition,
  ObservationFlag,
  ObservationIngestItem,
  ObservationStatus,
  ObservationValue,
  ObservationValueType,
} from "../blocks/observations/observations.ts";
import type { Result } from "../core/result.ts";
import type { FhirSubjectOptions, Untrusted } from "./shared.ts";
import type {
  FhirAnnotation,
  FhirCodeableConcept,
  FhirCoding,
  FhirIdentifier,
  FhirObservation,
  FhirObservationComponent,
  FhirObservationReferenceRange,
  FhirObservationStatus,
  FhirObservationValue,
  FhirPeriod,
  FhirQuantity,
  FhirReference,
} from "./types.ts";

import {
  compact,
  fhirTime,
  identifiers,
  instantOf,
  Issues,
  notes,
  referenceId,
  fieldsOf,
  itemsOf,
  subjectOf,
  text,
  UCUM,
  userOf,
  withTemporal,
} from "./shared.ts";

const INTERPRETATION =
  "http://terminology.hl7.org/CodeSystem/v3-ObservationInterpretation";

const DATA_ABSENT = "http://terminology.hl7.org/CodeSystem/data-absent-reason";

/** The observation fields `toFhirObservation` reads. */
export type FhirObservationSource = Pick<
  Observation,
  | "id"
  | "definitionKey"
  | "title"
  | "valueType"
  | "subjectId"
  | "observedAt"
  | "value"
  | "status"
  | "createdAt"
> &
  Partial<
    Pick<
      Observation,
      | "unit"
      | "flag"
      | "method"
      | "device"
      | "externalId"
      | "performerId"
      | "note"
    >
  >;

/** The component fields the observation mappers read. */
export type FhirObservationDefinitionComponent = Pick<
  ObservationComponent,
  "key"
> &
  Partial<
    Pick<
      ObservationComponent,
      "title" | "code" | "unit" | "referenceLow" | "referenceHigh"
    >
  >;

/** The definition fields `toFhirObservation` reads. */
export interface FhirObservationDefinition extends Partial<
  Pick<
    ObservationDefinition,
    "codeSystem" | "code" | "unit" | "referenceLow" | "referenceHigh"
  >
> {
  readonly components?: readonly FhirObservationDefinitionComponent[];
}

export interface FhirObservationOptions extends FhirSubjectOptions {
  /**
   * The observation's definition (`db.observations.definitions()`), for its
   * code, its component codes and its reference range. Without it the code is
   * the definition's title only.
   */
  readonly definition?: FhirObservationDefinition;
  /** Such as the `vital-signs` category the FHIR vital signs profile requires. */
  readonly category?: readonly FhirCodeableConcept[];
  /** The `system` of the identifier that carries `externalId`. */
  readonly identifierSystem?: string;
}

function statusOf(status: ObservationStatus): FhirObservationStatus {
  switch (status) {
    case "final": {
      return "final";
    }

    case "amended": {
      return "amended";
    }

    case "entered_in_error": {
      return "entered-in-error";
    }

    default: {
      const never: never = status;

      return never;
    }
  }
}

function interpretationOf(flag: ObservationFlag): string {
  switch (flag) {
    case "normal": {
      return "N";
    }

    case "low": {
      return "L";
    }

    case "high": {
      return "H";
    }

    case "critical_low": {
      return "LL";
    }

    case "critical_high": {
      return "HH";
    }

    default: {
      const never: never = flag;

      return never;
    }
  }
}

const quantity = (value: number, unit: string | undefined): FhirQuantity =>
  unit === undefined ? { value } : { value, unit, system: UCUM, code: unit };

const concept = (
  system: string | undefined,
  code: string | undefined,
  title: string,
): FhirCodeableConcept =>
  code === undefined
    ? { text: title }
    : {
        coding: [compact<FhirCoding>({ system, code, display: title })],
        text: title,
      };

function componentsOf(
  value: ObservationValue,
  definition: FhirObservationDefinition | undefined,
  unit: string | undefined,
): FhirObservationComponent[] {
  const values = typeof value === "object" ? value : {};

  const parts =
    definition?.components ??
    Object.keys(values).map((key): FhirObservationDefinitionComponent => ({
      key,
    }));

  return parts.map((part): FhirObservationComponent => {
    const code = concept(
      definition?.codeSystem,
      part.code,
      part.title ?? part.key,
    );

    const entry = values[part.key];

    return typeof entry === "number"
      ? { code, valueQuantity: quantity(entry, part.unit ?? unit) }
      : {
          code,
          dataAbsentReason: {
            coding: [{ system: DATA_ABSENT, code: "unknown" }],
          },
        };
  });
}

function valueOf(
  type: ObservationValueType,
  value: ObservationValue,
  unit: string | undefined,
): FhirObservationValue {
  switch (type) {
    case "number": {
      return typeof value === "number"
        ? { valueQuantity: quantity(value, unit) }
        : {};
    }

    case "integer": {
      if (typeof value !== "number") {
        return {};
      }

      return unit === undefined
        ? { valueInteger: value }
        : { valueQuantity: quantity(value, unit) };
    }

    case "boolean": {
      return typeof value === "boolean" ? { valueBoolean: value } : {};
    }

    case "code": {
      return typeof value === "string"
        ? { valueCodeableConcept: { coding: [{ code: value }] } }
        : {};
    }

    case "text": {
      return typeof value === "string" ? { valueString: value } : {};
    }

    case "components": {
      return {};
    }

    default: {
      const never: never = type;

      return never;
    }
  }
}

function rangeOf(
  definition: FhirObservationDefinition | undefined,
  unit: string | undefined,
): FhirObservationReferenceRange[] | undefined {
  const low = definition?.referenceLow;
  const high = definition?.referenceHigh;

  if (low === undefined && high === undefined) {
    return undefined;
  }

  return [
    compact<FhirObservationReferenceRange>({
      low: low === undefined ? undefined : quantity(low, unit),
      high: high === undefined ? undefined : quantity(high, unit),
    }),
  ];
}

/**
 * An observations block observation as a FHIR R4 `Observation`. Pass its
 * definition for the LOINC code, the component codes and the reference range.
 */
export function toFhirObservation(
  observation: FhirObservationSource,
  options?: FhirObservationOptions,
): FhirObservation {
  const { definition } = options ?? {};
  const unit = observation.unit ?? definition?.unit;
  const { value } = observation;

  const components =
    observation.valueType === "components" && value !== null
      ? componentsOf(value, definition, unit)
      : undefined;

  const performer = userOf(options, observation.performerId);

  return compact<FhirObservation>({
    resourceType: "Observation",
    id: observation.id,
    identifier: identifiers(observation.externalId, options?.identifierSystem),
    status: statusOf(observation.status),
    category: options?.category,
    code: concept(definition?.codeSystem, definition?.code, observation.title),
    subject: subjectOf(options, observation.subjectId),
    effectiveDateTime: fhirTime(observation.observedAt),
    issued: fhirTime(observation.createdAt),
    performer: performer === undefined ? undefined : [performer],
    ...(value === null
      ? {
          dataAbsentReason: {
            coding: [{ system: DATA_ABSENT, code: "unknown" }],
          },
        }
      : valueOf(observation.valueType, value, unit)),
    interpretation:
      observation.flag === undefined
        ? undefined
        : [
            {
              coding: [
                {
                  system: INTERPRETATION,
                  code: interpretationOf(observation.flag),
                },
              ],
            },
          ],
    note: notes(observation.note),
    method: text(observation.method),
    device:
      observation.device === undefined
        ? undefined
        : { display: observation.device },
    referenceRange:
      observation.valueType === "components"
        ? undefined
        : rangeOf(definition, unit),
    component: components,
  });
}

/** The definition fields `fromFhirObservation` matches codes and units on. */
export type FhirImportDefinition = Pick<
  ObservationDefinition,
  "key" | "valueType"
> &
  Partial<Pick<ObservationDefinition, "codeSystem" | "code" | "unit">> & {
    readonly components?: readonly Pick<
      ObservationComponent,
      "key" | "code" | "unit"
    >[];
  };

export interface FhirObservationImportOptions {
  /** The subject type the observations are recorded on, such as `client`. */
  readonly subjectType: string;
  /** The definitions to match codes against: `db.observations.definitions()`. */
  readonly definitions: readonly FhirImportDefinition[];
  /** The record id. Default: the id in `subject.reference`. */
  readonly subjectId?: string;
  /** Default `import`. */
  readonly source?: "device" | "import";
}

const IMPORTABLE = new Set(["final", "amended", "corrected", "preliminary"]);

const codingsOf = (value: unknown): Untrusted<FhirCoding>[] =>
  itemsOf<FhirCoding>(fieldsOf<FhirCodeableConcept>(value).coding);

const matches = (
  codings: readonly Untrusted<FhirCoding>[],
  system: string | undefined,
  code: string | undefined,
): boolean =>
  code !== undefined &&
  codings.some(
    (coding) =>
      coding.code === code &&
      (system === undefined || coding.system === system),
  );

const stringOf = (value: unknown): string | undefined =>
  typeof value === "string" && value !== "" ? value : undefined;

function numberOf(
  source: Untrusted<FhirObservationValue>,
  unit: string | undefined,
  path: readonly PropertyKey[],
  issues: Issues,
): number | undefined {
  if (typeof source.valueInteger === "number") {
    return source.valueInteger;
  }

  const value = fieldsOf<FhirQuantity>(source.valueQuantity);

  if (typeof value.value !== "number") {
    issues.add(path, `${path.join(".")} needs a numeric value`);

    return;
  }

  const code = stringOf(value.code) ?? stringOf(value.unit);

  if (unit !== undefined && code !== undefined && code !== unit) {
    issues.add(
      [...path, "valueQuantity", "code"],
      `${path.join(".")} is in ${code}, the definition in ${unit}`,
    );

    return;
  }

  return value.value;
}

function importValue(
  resource: Untrusted<FhirObservation>,
  definition: FhirImportDefinition,
  issues: Issues,
): ObservationValue | undefined {
  switch (definition.valueType) {
    case "number": {
      return numberOf(resource, definition.unit, ["value"], issues);
    }

    case "integer": {
      const value = numberOf(resource, definition.unit, ["value"], issues);

      if (value !== undefined && !Number.isInteger(value)) {
        issues.add(["value"], "value must be an integer");

        return;
      }

      return value;
    }

    case "boolean": {
      return issues.required(
        typeof resource.valueBoolean === "boolean"
          ? resource.valueBoolean
          : undefined,
        ["valueBoolean"],
        "value must be a boolean",
      );
    }

    case "code": {
      return issues.required(
        stringOf(codingsOf(resource.valueCodeableConcept)[0]?.code) ??
          stringOf(resource.valueString),
        ["valueCodeableConcept"],
        "value must be a code",
      );
    }

    case "text": {
      return issues.required(
        stringOf(resource.valueString),
        ["valueString"],
        "value must be a string",
      );
    }

    case "components": {
      return componentValues(resource, definition, issues);
    }

    default: {
      const never: never = definition.valueType;

      return never;
    }
  }
}

function componentValues(
  resource: Untrusted<FhirObservation>,
  definition: FhirImportDefinition,
  issues: Issues,
): Record<string, number> | undefined {
  const values: Record<string, number> = {};
  const components = itemsOf<FhirObservationComponent>(resource.component);

  for (const [index, component] of components.entries()) {
    const codings = codingsOf(component.code);

    const part = definition.components?.find((candidate) =>
      matches(codings, definition.codeSystem, candidate.code),
    );

    if (part !== undefined) {
      const value = numberOf(
        component,
        part.unit ?? definition.unit,
        ["component", index],
        issues,
      );

      if (value !== undefined) {
        values[part.key] = value;
      }
    }
  }

  return issues.required(
    Object.keys(values).length > 0 ? values : undefined,
    ["component"],
    "component has no value the definition knows",
  );
}

/**
 * Reads a FHIR R4 `Observation` as an item for `db.observations.ingest`,
 * matched to a definition by its code. A resource the block can't store returns
 * a `validation` error with one issue per problem.
 */
export function fromFhirObservation(
  input: unknown,
  options: FhirObservationImportOptions,
): Result<ObservationIngestItem> {
  const issues = new Issues();
  const resource = fieldsOf<FhirObservation>(input);

  if (resource.resourceType !== "Observation") {
    issues.add(["resourceType"], "resourceType must be Observation");

    return issues.failure("Observation");
  }

  if (!IMPORTABLE.has(String(resource.status))) {
    issues.add(
      ["status"],
      `status ${String(resource.status)} is not a recorded value`,
    );
  }

  const codings = codingsOf(resource.code);

  const definition = options.definitions.find((candidate) =>
    matches(codings, candidate.codeSystem, candidate.code),
  );

  if (definition === undefined) {
    issues.add(["code"], "code matches no observation definition");
  }

  const subjectId = issues.required(
    options.subjectId ?? referenceId(fieldsOf<FhirReference>(resource.subject)),
    ["subject"],
    "subject must reference the record",
  );

  const [identifier] = itemsOf<FhirIdentifier>(resource.identifier);

  const externalId = issues.required(
    stringOf(identifier?.value) ?? stringOf(resource.id),
    ["id"],
    "id or identifier is required to import once",
  );

  const period = fieldsOf<FhirPeriod>(resource.effectivePeriod);

  const observedAt = instantOf(
    resource.effectiveDateTime ?? resource.effectiveInstant ?? period.start,
    ["effectiveDateTime"],
    issues,
  );

  const value =
    definition === undefined
      ? undefined
      : importValue(resource, definition, issues);

  const method =
    stringOf(fieldsOf<FhirCodeableConcept>(resource.method).text) ??
    stringOf(codingsOf(resource.method)[0]?.display);

  const note = stringOf(itemsOf<FhirAnnotation>(resource.note)[0]?.text);

  if (
    !issues.empty ||
    definition === undefined ||
    subjectId === undefined ||
    externalId === undefined ||
    observedAt === undefined ||
    value === undefined
  ) {
    return issues.failure("Observation");
  }

  return withTemporal((time) =>
    compact<ObservationIngestItem>({
      subjectType: options.subjectType,
      subjectId,
      definitionKey: definition.key,
      value,
      observedAt: time.Instant.from(observedAt),
      externalId,
      source: options.source ?? "import",
      method,
      device: stringOf(fieldsOf<FhirReference>(resource.device).display),
      note,
    }),
  );
}
