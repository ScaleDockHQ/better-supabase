/**
 * Structural FHIR R4 (4.0.1) types: the elements the mappers read and write,
 * not the whole specification. A profile layer (zib, US Core) can add
 * extensions and narrow them.
 */

export interface FhirCoding {
  readonly system?: string;
  readonly version?: string;
  readonly code?: string;
  readonly display?: string;
}

export interface FhirCodeableConcept {
  readonly coding?: readonly FhirCoding[];
  readonly text?: string;
}

export interface FhirIdentifier {
  readonly system?: string;
  readonly value?: string;
}

export interface FhirReference {
  readonly reference?: string;
  readonly type?: string;
  readonly identifier?: FhirIdentifier;
  readonly display?: string;
}

/** `start` and `end` are FHIR `date` or `dateTime` strings. */
export interface FhirPeriod {
  readonly start?: string;
  readonly end?: string;
}

export interface FhirQuantity {
  readonly value?: number;
  readonly unit?: string;
  readonly system?: string;
  readonly code?: string;
}

export interface FhirRatio {
  readonly numerator?: FhirQuantity;
  readonly denominator?: FhirQuantity;
}

export interface FhirRange {
  readonly low?: FhirQuantity;
  readonly high?: FhirQuantity;
}

export interface FhirAnnotation {
  readonly text: string;
  readonly time?: string;
}

export interface FhirContactPoint {
  readonly system?:
    | "phone"
    | "fax"
    | "email"
    | "pager"
    | "url"
    | "sms"
    | "other";
  readonly value?: string;
  readonly use?: "home" | "work" | "temp" | "old" | "mobile";
}

export interface FhirHumanName {
  readonly text?: string;
  readonly family?: string;
  readonly given?: readonly string[];
}

export type FhirDayOfWeek =
  | "mon"
  | "tue"
  | "wed"
  | "thu"
  | "fri"
  | "sat"
  | "sun";

export interface FhirTimingRepeat {
  readonly boundsPeriod?: FhirPeriod;
  readonly frequency?: number;
  readonly period?: number;
  readonly periodUnit?: "s" | "min" | "h" | "d" | "wk" | "mo" | "a";
  readonly dayOfWeek?: readonly FhirDayOfWeek[];
  /** `hh:mm:ss` times. */
  readonly timeOfDay?: readonly string[];
  readonly [key: string]: unknown;
}

export interface FhirTiming {
  readonly repeat?: FhirTimingRepeat;
}

export interface FhirMeta {
  readonly profile?: readonly string[];
  readonly lastUpdated?: string;
}

/** What every resource has. */
export interface FhirResource {
  readonly resourceType: string;
  readonly id?: string;
  readonly meta?: FhirMeta;
}

export type FhirAdministrativeGender = "male" | "female" | "other" | "unknown";

export interface FhirPatient extends FhirResource {
  readonly resourceType: "Patient";
  readonly identifier?: readonly FhirIdentifier[];
  readonly active?: boolean;
  readonly name?: readonly FhirHumanName[];
  readonly telecom?: readonly FhirContactPoint[];
  readonly gender?: FhirAdministrativeGender;
  readonly birthDate?: string;
}

export interface FhirRelatedPerson extends FhirResource {
  readonly resourceType: "RelatedPerson";
  readonly active?: boolean;
  readonly patient: FhirReference;
  readonly relationship?: readonly FhirCodeableConcept[];
  readonly name?: readonly FhirHumanName[];
  readonly telecom?: readonly FhirContactPoint[];
  readonly period?: FhirPeriod;
}

export type FhirConditionClinicalStatus = "active" | "resolved";

export interface FhirCondition extends FhirResource {
  readonly resourceType: "Condition";
  readonly clinicalStatus?: FhirCodeableConcept;
  readonly code?: FhirCodeableConcept;
  readonly subject: FhirReference;
  readonly note?: readonly FhirAnnotation[];
}

export type FhirGoalLifecycleStatus =
  | "proposed"
  | "planned"
  | "accepted"
  | "active"
  | "on-hold"
  | "completed"
  | "cancelled"
  | "entered-in-error"
  | "rejected";

export interface FhirGoalTarget {
  readonly measure?: FhirCodeableConcept;
  readonly detailQuantity?: FhirQuantity;
  readonly detailString?: string;
  readonly detailBoolean?: boolean;
  readonly dueDate?: string;
}

export interface FhirGoal extends FhirResource {
  readonly resourceType: "Goal";
  readonly lifecycleStatus: FhirGoalLifecycleStatus;
  readonly achievementStatus?: FhirCodeableConcept;
  readonly description: FhirCodeableConcept;
  readonly subject: FhirReference;
  readonly target?: readonly FhirGoalTarget[];
  readonly statusDate?: string;
  readonly addresses?: readonly FhirReference[];
}

export type FhirCarePlanStatus =
  | "draft"
  | "active"
  | "on-hold"
  | "revoked"
  | "completed"
  | "entered-in-error"
  | "unknown";

export type FhirCarePlanActivityStatus =
  | "not-started"
  | "scheduled"
  | "in-progress"
  | "on-hold"
  | "completed"
  | "cancelled"
  | "stopped"
  | "unknown"
  | "entered-in-error";

export interface FhirCarePlanActivityDetail {
  readonly kind?: "Appointment" | "Task";
  readonly code?: FhirCodeableConcept;
  readonly goal?: readonly FhirReference[];
  readonly status: FhirCarePlanActivityStatus;
  readonly statusReason?: FhirCodeableConcept;
  readonly scheduledTiming?: FhirTiming;
  readonly scheduledPeriod?: FhirPeriod;
  readonly performer?: readonly FhirReference[];
  readonly description?: string;
}

export interface FhirCarePlanActivity {
  readonly detail: FhirCarePlanActivityDetail;
}

/** Conditions and goals ride along as contained resources. */
export type FhirCarePlanContained = FhirCondition | FhirGoal;

export interface FhirCarePlan extends FhirResource {
  readonly resourceType: "CarePlan";
  readonly contained?: readonly FhirCarePlanContained[];
  readonly status: FhirCarePlanStatus;
  readonly intent: "plan";
  readonly title?: string;
  readonly subject: FhirReference;
  readonly period?: FhirPeriod;
  readonly created?: string;
  readonly author?: FhirReference;
  readonly addresses?: readonly FhirReference[];
  readonly goal?: readonly FhirReference[];
  readonly activity?: readonly FhirCarePlanActivity[];
}

export type FhirObservationStatus =
  | "registered"
  | "preliminary"
  | "final"
  | "amended"
  | "corrected"
  | "cancelled"
  | "entered-in-error"
  | "unknown";

/** The `value[x]` choices the mappers read and write. */
export interface FhirObservationValue {
  readonly valueQuantity?: FhirQuantity;
  readonly valueCodeableConcept?: FhirCodeableConcept;
  readonly valueString?: string;
  readonly valueBoolean?: boolean;
  readonly valueInteger?: number;
}

export interface FhirObservationComponent extends FhirObservationValue {
  readonly code: FhirCodeableConcept;
  readonly dataAbsentReason?: FhirCodeableConcept;
}

export interface FhirObservationReferenceRange {
  readonly low?: FhirQuantity;
  readonly high?: FhirQuantity;
}

export interface FhirObservation extends FhirResource, FhirObservationValue {
  readonly resourceType: "Observation";
  readonly identifier?: readonly FhirIdentifier[];
  readonly status: FhirObservationStatus;
  readonly category?: readonly FhirCodeableConcept[];
  readonly code: FhirCodeableConcept;
  readonly subject?: FhirReference;
  readonly effectiveDateTime?: string;
  readonly effectiveInstant?: string;
  readonly effectivePeriod?: FhirPeriod;
  readonly issued?: string;
  readonly performer?: readonly FhirReference[];
  readonly dataAbsentReason?: FhirCodeableConcept;
  readonly interpretation?: readonly FhirCodeableConcept[];
  readonly note?: readonly FhirAnnotation[];
  readonly method?: FhirCodeableConcept;
  readonly device?: FhirReference;
  readonly referenceRange?: readonly FhirObservationReferenceRange[];
  readonly component?: readonly FhirObservationComponent[];
}

export interface FhirDoseAndRate {
  readonly doseQuantity?: FhirQuantity;
}

export interface FhirDosage {
  readonly text?: string;
  readonly timing?: FhirTiming;
  readonly asNeededBoolean?: boolean;
  readonly asNeededCodeableConcept?: FhirCodeableConcept;
  readonly route?: FhirCodeableConcept;
  readonly doseAndRate?: readonly FhirDoseAndRate[];
  readonly maxDosePerPeriod?: FhirRatio;
}

export type FhirMedicationRequestStatus =
  | "active"
  | "on-hold"
  | "cancelled"
  | "completed"
  | "entered-in-error"
  | "stopped"
  | "draft"
  | "unknown";

export type FhirMedicationRequestIntent =
  | "proposal"
  | "plan"
  | "order"
  | "original-order"
  | "reflex-order"
  | "filler-order"
  | "instance-order"
  | "option";

export interface FhirMedicationRequest extends FhirResource {
  readonly resourceType: "MedicationRequest";
  readonly identifier?: readonly FhirIdentifier[];
  readonly status: FhirMedicationRequestStatus;
  readonly statusReason?: FhirCodeableConcept;
  readonly intent: FhirMedicationRequestIntent;
  readonly medicationCodeableConcept?: FhirCodeableConcept;
  readonly medicationReference?: FhirReference;
  readonly subject: FhirReference;
  readonly authoredOn?: string;
  readonly requester?: FhirReference;
  readonly dosageInstruction?: readonly FhirDosage[];
}

export type FhirMedicationAdministrationStatus =
  | "in-progress"
  | "not-done"
  | "on-hold"
  | "completed"
  | "entered-in-error"
  | "stopped"
  | "unknown";

export interface FhirMedicationAdministrationPerformer {
  readonly function?: FhirCodeableConcept;
  readonly actor: FhirReference;
}

export interface FhirMedicationAdministrationDosage {
  readonly text?: string;
  readonly route?: FhirCodeableConcept;
  readonly dose?: FhirQuantity;
}

export interface FhirMedicationAdministration extends FhirResource {
  readonly resourceType: "MedicationAdministration";
  readonly status: FhirMedicationAdministrationStatus;
  readonly statusReason?: readonly FhirCodeableConcept[];
  readonly medicationCodeableConcept?: FhirCodeableConcept;
  readonly medicationReference?: FhirReference;
  readonly subject: FhirReference;
  readonly effectiveDateTime?: string;
  readonly performer?: readonly FhirMedicationAdministrationPerformer[];
  readonly request?: FhirReference;
  readonly note?: readonly FhirAnnotation[];
  readonly dosage?: FhirMedicationAdministrationDosage;
}

export type FhirConsentStatus =
  | "draft"
  | "proposed"
  | "active"
  | "rejected"
  | "inactive"
  | "entered-in-error";

export interface FhirConsentProvision {
  readonly type?: "deny" | "permit";
  readonly period?: FhirPeriod;
  readonly purpose?: readonly FhirCoding[];
}

export interface FhirConsent extends FhirResource {
  readonly resourceType: "Consent";
  readonly status: FhirConsentStatus;
  readonly scope: FhirCodeableConcept;
  readonly category: readonly FhirCodeableConcept[];
  readonly patient?: FhirReference;
  readonly dateTime?: string;
  readonly performer?: readonly FhirReference[];
  readonly policyRule?: FhirCodeableConcept;
  readonly provision?: FhirConsentProvision;
}

export type FhirBundleType =
  | "document"
  | "message"
  | "transaction"
  | "transaction-response"
  | "batch"
  | "batch-response"
  | "history"
  | "searchset"
  | "collection";

export interface FhirBundleEntryRequest {
  readonly method: "GET" | "HEAD" | "POST" | "PUT" | "DELETE" | "PATCH";
  readonly url: string;
}

export interface FhirBundleEntry<R extends FhirResource = FhirResource> {
  readonly fullUrl?: string;
  readonly resource: R;
  readonly search?: { readonly mode: "match" | "include" };
  readonly request?: FhirBundleEntryRequest;
}

export interface FhirBundle<
  R extends FhirResource = FhirResource,
> extends FhirResource {
  readonly resourceType: "Bundle";
  readonly type: FhirBundleType;
  readonly timestamp?: string;
  readonly total?: number;
  readonly entry?: readonly FhirBundleEntry<R>[];
}
