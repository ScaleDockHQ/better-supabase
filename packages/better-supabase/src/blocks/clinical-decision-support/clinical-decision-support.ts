import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult as AsyncResultType } from "../../core/result.ts";
import type { CARE_ALERT_DECISIONS } from "../../sql/modules/clinical-decision-support-values.ts";
import type { RecordRef, BlockOptions } from "../shared.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { AsyncResult, err } from "../../core/result.ts";
import {
  CARE_ALERT_KINDS,
  CARE_ALERT_SEVERITIES,
  CARE_ALERT_STATUSES,
  CARE_BUILT_IN_SOURCE,
  CARE_RULE_KINDS,
} from "../../sql/modules/clinical-decision-support-values.ts";
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
  stringsOf,
  textOf,
} from "../shared.ts";

export { CARE_BUILT_IN_SOURCE };

/** What an alert is about. */
export type CareAlertKind = (typeof CARE_ALERT_KINDS)[number];

/** The kinds of the built-in rule set. */
export type CareRuleKind = (typeof CARE_RULE_KINDS)[number];

/** How serious an alert is. */
export type CareAlertSeverity = (typeof CARE_ALERT_SEVERITIES)[number];

/** Where an alert stands. */
export type CareAlertStatus = (typeof CARE_ALERT_STATUSES)[number];

/** What a member decides on an open alert. */
export type CareAlertDecision = (typeof CARE_ALERT_DECISIONS)[number];

/** A tenant rule of the built-in set. */
export interface CareRule {
  readonly id: string;
  readonly organizationId: string;
  readonly kind: CareRuleKind;
  /** The medications the rule names, from the medications catalog. */
  readonly medicationIds: readonly string[];
  readonly minDose?: number;
  readonly maxDose?: number;
  /** The most of the dose unit in 24 hours. */
  readonly maxPerDay?: number;
  readonly severity: CareAlertSeverity;
  readonly message?: string;
  readonly active: boolean;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface CareRuleInput {
  /** Set to change a rule; leave out to add one. */
  readonly id?: string;
  readonly kind: CareRuleKind;
  /**
   * One medication for a dose range, two for an interaction, two or more for a
   * therapy group.
   */
  readonly medicationIds: readonly string[];
  readonly minDose?: number | null;
  readonly maxDose?: number | null;
  readonly maxPerDay?: number | null;
  /** Default `warning`. */
  readonly severity?: CareAlertSeverity;
  /** The text of the alert. Without it the built-in text names the medication. */
  readonly message?: string | null;
  /** Default `true`. */
  readonly active?: boolean;
}

/** An alert about a record. */
export interface CareAlert {
  readonly id: string;
  readonly organizationId: string;
  readonly subject: RecordRef;
  readonly kind: CareAlertKind;
  readonly severity: CareAlertSeverity;
  /** `built-in` or the key of the engine that raised it. */
  readonly source: string;
  readonly ruleId?: string;
  /** The medication orders involved. */
  readonly orderIds: readonly string[];
  readonly message: string;
  readonly details?: Readonly<Record<string, unknown>>;
  readonly fingerprint: string;
  readonly status: CareAlertStatus;
  readonly decidedBy?: string;
  readonly decidedAt?: Temporal.Instant;
  readonly decisionReason?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface CareAlertListOptions {
  readonly subject?: RecordRef;
  /** Default: every status but `resolved`. */
  readonly status?: CareAlertStatus;
  readonly kind?: CareAlertKind;
  /** 1 to 200. Default 50. */
  readonly limit?: number;
  readonly offset?: number;
}

/** An active medication order, as an engine sees it. */
export interface CareDecisionMedication {
  readonly orderId: string;
  readonly medicationId: string;
  readonly name: string;
  /** `gtin`, `hpk`, `atc`, `rxnorm` or `custom`. */
  readonly codeSystem: string;
  readonly code: string | null;
  readonly dose: number;
  readonly doseUnit: string;
  readonly asNeeded: boolean;
  readonly maxPerDay: number | null;
  /** `{ times }` or `{ everyHours }`, as the order stores it. */
  readonly schedule: Readonly<Record<string, unknown>> | null;
  readonly startsOn: string;
  readonly endsOn: string | null;
}

/** The latest observation of one kind. */
export interface CareDecisionObservation {
  readonly key: string;
  readonly code: string | null;
  readonly codeSystem: string | null;
  readonly unit: string | null;
  readonly valueNumber: number | null;
  readonly valueText: string | null;
  readonly valueCode: string | null;
  readonly flag: string | null;
  readonly observedAt: string;
}

/** A granted consent. */
export interface CareDecisionConsent {
  readonly purpose: string;
  readonly status: string;
  readonly scope: unknown;
  readonly grantedAt: string;
  readonly validUntil: string | null;
}

/** The active care plan. */
export interface CareDecisionPlan {
  readonly id: string;
  readonly title: string;
  readonly version: number;
  readonly reviewOn: string | null;
}

/**
 * What a `ClinicalDecisionSupport` engine gets for one record: its active
 * medication orders, the latest observation of each kind, granted consents and
 * the active care plan. Care blocks that aren't installed contribute an empty
 * list or `null`.
 */
export interface CareDecisionContext {
  readonly organizationId: string;
  readonly subject: RecordRef;
  readonly medications: readonly CareDecisionMedication[];
  readonly observations: readonly CareDecisionObservation[];
  readonly consents: readonly CareDecisionConsent[];
  readonly carePlan: CareDecisionPlan | null;
}

/** An alert an engine raises. */
export interface CareDecisionAlert {
  /** Default `other`. */
  readonly kind?: CareAlertKind;
  /** Default `warning`. */
  readonly severity?: CareAlertSeverity;
  /** What the member reads, up to 1000 characters. */
  readonly message: string;
  /**
   * Identifies the finding across evaluations, up to 200 characters. Keep it
   * stable: the same fingerprint updates the alert and keeps a member's
   * decision. Default: a hash of the kind and the message.
   */
  readonly fingerprint?: string;
  /** The medication orders involved. */
  readonly orderIds?: readonly string[];
  readonly details?: Readonly<Record<string, unknown>>;
}

/** What an engine gets next to the context. */
export interface CareDecisionRequest {
  readonly signal?: AbortSignal;
}

/**
 * An external clinical decision support engine: interaction, allergy and
 * contraindication checks from a drug database or a service. Write it in the
 * app or its own package; the block bundles none. It gets the record's context
 * and returns the alerts it raises now. Alerts it raised before and no longer
 * returns are resolved.
 */
export interface ClinicalDecisionSupport {
  /** The port contract version. Omitted means 1. */
  readonly apiVersion?: 1;
  /**
   * The source name stored on its alerts, 1 to 100 characters. `built-in` is
   * reserved.
   */
  readonly key: string;
  evaluate(
    context: CareDecisionContext,
    request: CareDecisionRequest,
  ): readonly CareDecisionAlert[] | Promise<readonly CareDecisionAlert[]>;
}

export interface ClinicalDecisionSupportClient {
  /**
   * Adds a rule, or changes `input.id`; needs
   * `clinical_decision_support.manage`.
   */
  saveRule(input: CareRuleInput): AsyncResultType<CareRule>;
  deleteRule(ruleId: string): AsyncResultType<CareRule>;
  rules(): AsyncResultType<readonly CareRule[]>;
  /**
   * Runs the built-in rules over the record's active medication orders, then
   * each configured engine over the record's context, and returns the record's
   * open alerts, serious ones first. An engine that throws makes the call an
   * error with hint `CARE_ENGINE_FAILED`; the alerts of the engines before it
   * are already stored. Needs `clinical_decision_support.write`.
   */
  evaluate(
    subject: RecordRef,
    options?: { readonly signal?: AbortSignal },
  ): AsyncResultType<readonly CareAlert[]>;
  /** The context an engine would get; needs `clinical_decision_support.read`. */
  context(subject: RecordRef): AsyncResultType<CareDecisionContext>;
  /** Alerts by severity, newest first. */
  alerts(options?: CareAlertListOptions): AsyncResultType<readonly CareAlert[]>;
  /**
   * Acknowledges or overrides an alert. An override, and any decision on a
   * critical alert, needs a `reason`. Needs `clinical_decision_support.write`.
   */
  decide(
    alertId: string,
    decision: CareAlertDecision,
    options?: { readonly reason?: string },
  ): AsyncResultType<CareAlert>;
}

/** Options for {@link createClinicalDecisionSupport}. */
export interface ClinicalDecisionSupportOptions extends BlockOptions {
  /** External engines `evaluate` runs after the built-in rules, in order. */
  readonly engines?: readonly ClinicalDecisionSupport[];
  /** `before` and `after` hooks per method (ADR 0015). */
  readonly hooks?: NoInfer<BlockHooks<ClinicalDecisionSupportClient>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

const KEY_LENGTH = 100;

function optional<K extends string, V>(
  key: K,
  value: V | undefined,
): { readonly [P in K]?: V } {
  // SAFETY: a one-key object literal for the key the caller names.
  return (value === undefined ? {} : { [key]: value }) as {
    readonly [P in K]?: V;
  };
}

const numberOf = (value: unknown): number | undefined =>
  value === null || value === undefined ? undefined : Number(value);

const definedOf = (input: object): Record<string, unknown> =>
  Object.fromEntries(
    Object.entries(input).filter(([, value]) => value !== undefined),
  );

function recordOrUndefined(
  value: unknown,
): Readonly<Record<string, unknown>> | undefined {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return undefined;
  }

  // SAFETY: narrowed to a non-array object above, and JSON objects have string keys.
  return value as Readonly<Record<string, unknown>>;
}

function ruleOf(value: unknown, fn: string): CareRule {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    kind: enumOrThrow(row["kind"], CARE_RULE_KINDS, "rule kind"),
    medicationIds: stringsOf(row["medicationIds"]),
    severity: enumOrThrow(
      row["severity"],
      CARE_ALERT_SEVERITIES,
      "rule severity",
    ),
    active: row["active"] === true,
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("minDose", numberOf(row["minDose"])),
    ...optional("maxDose", numberOf(row["maxDose"])),
    ...optional("maxPerDay", numberOf(row["maxPerDay"])),
    ...optional("message", optionalText(row["message"])),
  };
}

function alertOf(value: unknown, fn: string): CareAlert {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    subject: { type: textOf(row["subjectType"]), id: textOf(row["subjectId"]) },
    kind: enumOrThrow(row["kind"], CARE_ALERT_KINDS, "alert kind"),
    severity: enumOrThrow(
      row["severity"],
      CARE_ALERT_SEVERITIES,
      "alert severity",
    ),
    source: textOf(row["source"]),
    orderIds: stringsOf(row["orderIds"]),
    message: textOf(row["message"]),
    fingerprint: textOf(row["fingerprint"]),
    status: enumOrThrow(row["status"], CARE_ALERT_STATUSES, "alert status"),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("ruleId", optionalText(row["ruleId"])),
    ...optional("details", recordOrUndefined(row["details"])),
    ...optional("decidedBy", optionalText(row["decidedBy"])),
    ...optional("decidedAt", optionalInstant(row["decidedAt"])),
    ...optional("decisionReason", optionalText(row["decisionReason"])),
  };
}

function contextOf(value: unknown, fn: string): CareDecisionContext {
  const row = recordOf(value, fn);
  const plan = recordOrUndefined(row["carePlan"]);

  const list = <T extends object>(key: string): readonly T[] =>
    // SAFETY: the SQL function builds these lists with the documented keys.
    recordsOf(row[key], fn).map((entry) => entry as T);

  return {
    organizationId: textOf(row["organizationId"]),
    subject: { type: textOf(row["subjectType"]), id: textOf(row["subjectId"]) },
    medications: list<CareDecisionMedication>("medications"),
    observations: list<CareDecisionObservation>("observations"),
    consents: list<CareDecisionConsent>("consents"),
    carePlan:
      plan === undefined
        ? null
        : {
            id: textOf(plan["id"]),
            title: textOf(plan["title"]),
            version: Number(plan["version"]),
            reviewOn: optionalText(plan["reviewOn"]) ?? null,
          },
  };
}

/** Checks an engine at construction: version and key. */
function engineOf(engine: ClinicalDecisionSupport): ClinicalDecisionSupport {
  injectableOf("clinical decision support engine", engine);

  if (
    engine.key.trim() === "" ||
    engine.key.length > KEY_LENGTH ||
    engine.key === CARE_BUILT_IN_SOURCE
  ) {
    throw new TypeError(
      `clinical decision support engine key "${engine.key}" must be 1 to ${String(KEY_LENGTH)} characters and not "${CARE_BUILT_IN_SOURCE}"`,
    );
  }

  return engine;
}

/**
 * Clinical decision support: tenant rules for dose range, duplicate therapy and
 * interactions over a record's medication orders, alerts that members
 * acknowledge or override with a reason, and engines that plug in through the
 * `ClinicalDecisionSupport` port.
 */
export function createClinicalDecisionSupport(
  options: ClinicalDecisionSupportOptions,
): ClinicalDecisionSupportClient {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResultType<string> => requireTenant(options.tenant);
  const engines = (options.engines ?? []).map(engineOf);

  const keys = new Set(engines.map((engine) => engine.key));

  if (keys.size !== engines.length) {
    throw new TypeError("clinical decision support engines need unique keys");
  }

  const contextFor = (
    organizationId: string,
    subject: RecordRef,
  ): AsyncResultType<CareDecisionContext> =>
    call(
      "care_decision_context",
      {
        tenant: organizationId,
        subject_type: subject.type,
        subject_id: subject.id,
      },
      (value) => contextOf(value, "care_decision_context"),
    );

  const runEngine = (
    organizationId: string,
    subject: RecordRef,
    engine: ClinicalDecisionSupport,
    signal: AbortSignal | undefined,
  ): AsyncResultType<unknown> =>
    contextFor(organizationId, subject).andThen((context) =>
      AsyncResult.from(async () => {
        let raised: readonly CareDecisionAlert[];

        try {
          raised = await engine.evaluate(context, {
            ...(signal ? { signal } : {}),
          });
        } catch (cause) {
          return err({
            kind: "unexpected",
            message: `engine ${engine.key} failed: ${cause instanceof Error ? cause.message : String(cause)}`,
            status: 502,
            hint: "CARE_ENGINE_FAILED",
          });
        }

        return call(
          "record_care_alerts",
          {
            tenant: organizationId,
            subject_type: subject.type,
            subject_id: subject.id,
            source: engine.key,
            alerts: raised.map((alert) => definedOf(alert)),
          },
          (value) => value,
        );
      }),
    );

  const client: ClinicalDecisionSupportClient = {
    saveRule: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "save_care_rule",
          { tenant: organizationId, attrs: definedOf(input) },
          (value) => ruleOf(value, "save_care_rule"),
        ),
      ),
    deleteRule: (ruleId) =>
      call("delete_care_rule", { rule_id: ruleId }, (value) =>
        ruleOf(value, "delete_care_rule"),
      ),
    rules: () =>
      tenant().andThen((organizationId) =>
        call("list_care_rules", { tenant: organizationId }, (value) =>
          recordsOf(value, "list_care_rules").map((row) =>
            ruleOf(row, "list_care_rules"),
          ),
        ),
      ),
    evaluate: (subject, run = {}) =>
      tenant().andThen((organizationId) => {
        let chain: AsyncResultType<unknown> = call(
          "evaluate_care_rules",
          {
            tenant: organizationId,
            subject_type: subject.type,
            subject_id: subject.id,
          },
          (value) => value,
        );

        for (const engine of engines) {
          chain = chain.andThen(() =>
            runEngine(organizationId, subject, engine, run.signal),
          );
        }

        return chain.andThen(() => client.alerts({ subject, limit: 200 }));
      }),
    context: (subject) =>
      tenant().andThen((organizationId) => contextFor(organizationId, subject)),
    alerts: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_care_alerts",
          {
            tenant: organizationId,
            filters: definedOf({
              subjectType: list.subject?.type,
              subjectId: list.subject?.id,
              status: list.status,
              kind: list.kind,
              limit: list.limit,
              offset: list.offset,
            }),
          },
          (value) =>
            recordsOf(value, "list_care_alerts").map((row) =>
              alertOf(row, "list_care_alerts"),
            ),
        ),
      ),
    decide: (alertId, decision, decide = {}) =>
      call(
        "decide_care_alert",
        {
          alert_id: alertId,
          decision,
          ...(decide.reason === undefined ? {} : { reason: decide.reason }),
        },
        (value) => alertOf(value, "decide_care_alert"),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "clinical-decision-support",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
