import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult as AsyncResultType } from "../../core/result.ts";
import type {
  DeadlineCitation,
  DeadlineEvaluation,
  DeadlineRule,
} from "../../sql/modules/deadlines-values.ts";
import type { BlockOptions } from "../shared.ts";

import { plainDateOf } from "../../core/block-helpers.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  DEADLINE_RESULTS,
  DEADLINE_STATES,
  evaluateDeadlineRule,
  RULE_VERSION_STATUSES,
  validateDeadlineRules,
} from "../../sql/modules/deadlines-values.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  optionalInstant,
  recordOf,
  recordsOf,
  textOf,
} from "../shared.ts";

/** A version of a rule set: draft until approved, then frozen. */
export interface RuleVersion {
  readonly id: string;
  readonly jurisdiction: string;
  readonly kind: string;
  readonly version: number;
  readonly status: (typeof RULE_VERSION_STATUSES)[number];
  readonly rules: readonly DeadlineRule[];
  /** SHA-256 of the rules, set when the version is approved. */
  readonly contentHash?: string;
  /** The first day the version applies. */
  readonly effectiveFrom?: Temporal.PlainDate;
  readonly approvedBy?: string;
  readonly approvedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
}

/** A deadline of one rule for one subject. */
export interface Deadline {
  readonly id: string;
  readonly organizationId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly jurisdiction: string;
  readonly kind: string;
  readonly ruleKey: string;
  readonly ruleVersionId: string;
  readonly ruleVersion?: number;
  readonly facts: Readonly<Record<string, unknown>>;
  readonly result: (typeof DEADLINE_RESULTS)[number];
  /** Set when the result is `due`. */
  readonly dueOn?: Temporal.PlainDate;
  /** The facts a result of `unknown` waits for. */
  readonly missing: readonly string[];
  readonly citation: DeadlineCitation;
  readonly state: (typeof DEADLINE_STATES)[number];
  readonly satisfiedAt?: Temporal.Instant;
  readonly satisfiedBy?: string;
  readonly satisfiedAction?: string;
  readonly computedAt: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
}

export interface DeadlineSubject {
  readonly subjectType: string;
  readonly subjectId: string;
}

export interface DeadlineListOptions {
  readonly subjectType?: string;
  readonly subjectId?: string;
  readonly state?: Deadline["state"];
  readonly result?: Deadline["result"];
  /** Only deadlines due before this date. */
  readonly dueBefore?: Temporal.PlainDate;
  /** At most 500; 100 by default. */
  readonly limit?: number;
}

export interface DeadlinesOptions extends BlockOptions {
  readonly hooks?: BlockHooks<Deadlines>;
  readonly logger?: Logger;
}

export interface Deadlines {
  /**
   * Saves rules as a draft version of a rule set, creating the set on first
   * use. Service role only.
   */
  saveRules(input: {
    readonly jurisdiction: string;
    readonly kind: string;
    readonly rules: readonly DeadlineRule[];
    readonly effectiveFrom?: Temporal.PlainDate;
    readonly title?: string;
  }): AsyncResultType<RuleVersion>;
  /**
   * Freezes a draft: stores its content hash and the date it applies from. With
   * the approvals block installed, the approval request must be approved.
   * Service role only.
   */
  approveRules(input: {
    readonly versionId: string;
    readonly approvalId?: string;
    readonly effectiveFrom?: Temporal.PlainDate;
  }): AsyncResultType<RuleVersion>;
  /** The approved version that applies on a date (today by default). */
  rulesAt(input: {
    readonly jurisdiction: string;
    readonly kind: string;
    readonly date?: Temporal.PlainDate;
  }): AsyncResultType<RuleVersion | undefined>;
  /** Computes and stores the deadline of one rule from a subject's facts. */
  compute(
    input: DeadlineSubject & {
      readonly jurisdiction: string;
      readonly kind: string;
      readonly ruleKey: string;
      readonly facts: Readonly<Record<string, unknown>>;
      readonly asOf?: Temporal.PlainDate;
    },
  ): AsyncResultType<Deadline>;
  /** Re-evaluates a subject's pending deadlines with extra facts. */
  recompute(
    input: DeadlineSubject & {
      readonly facts?: Readonly<Record<string, unknown>>;
    },
  ): AsyncResultType<number>;
  /** Records the action that satisfied a deadline. */
  satisfy(input: {
    readonly deadlineId: string;
    readonly action?: string;
  }): AsyncResultType<Deadline>;
  list(options?: DeadlineListOptions): AsyncResultType<readonly Deadline[]>;
}

/**
 * Evaluates one rule against facts in TypeScript, with the same result as the
 * database. Use it to preview a draft or to show a date without a round trip.
 */
export function evaluateRule(
  rule: DeadlineRule,
  facts: Readonly<Record<string, unknown>>,
): DeadlineEvaluation {
  return evaluateDeadlineRule(rule, facts);
}

/** The problems of a rule list, or an empty array when it can be saved. */
export function validateRules(rules: unknown): readonly string[] {
  return validateDeadlineRules(rules);
}

function objectOf(value: unknown): Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? Object.fromEntries(Object.entries(value))
    : {};
}

function optionalText(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}

function isRule(value: unknown): value is DeadlineRule {
  return typeof value === "object" && value !== null && "key" in value;
}

function versionOf(value: unknown, fn: string): RuleVersion {
  const row = recordOf(value, fn);
  const effectiveFrom = row["effectiveFrom"];
  const approvedAt = optionalInstant(row["approvedAt"]);
  const contentHash = optionalText(row["contentHash"]);
  const approvedBy = optionalText(row["approvedBy"]);

  return {
    id: textOf(row["id"]),
    jurisdiction: textOf(row["jurisdiction"]),
    kind: textOf(row["kind"]),
    version: Number(row["version"]),
    status: enumOrThrow(row["status"], RULE_VERSION_STATUSES, "rule status"),
    rules: Array.isArray(row["rules"]) ? row["rules"].filter(isRule) : [],
    createdAt: temporal().Instant.from(textOf(row["createdAt"])),
    ...(contentHash === undefined ? {} : { contentHash }),
    ...(typeof effectiveFrom === "string"
      ? { effectiveFrom: plainDateOf(effectiveFrom, "effectiveFrom") }
      : {}),
    ...(approvedBy === undefined ? {} : { approvedBy }),
    ...(approvedAt === undefined ? {} : { approvedAt }),
  };
}

function deadlineOf(value: unknown, fn: string): Deadline {
  const row = recordOf(value, fn);
  const dueOn = row["dueOn"];
  const satisfiedAt = optionalInstant(row["satisfiedAt"]);
  const satisfiedBy = optionalText(row["satisfiedBy"]);
  const satisfiedAction = optionalText(row["satisfiedAction"]);
  const citation = objectOf(row["citation"]);
  const url = optionalText(citation["url"]);
  const text = optionalText(citation["text"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    subjectType: textOf(row["subjectType"]),
    subjectId: textOf(row["subjectId"]),
    jurisdiction: textOf(row["jurisdiction"]),
    kind: textOf(row["kind"]),
    ruleKey: textOf(row["ruleKey"]),
    ruleVersionId: textOf(row["ruleVersionId"]),
    facts: objectOf(row["facts"]),
    result: enumOrThrow(row["result"], DEADLINE_RESULTS, "deadline result"),
    missing: Array.isArray(row["missing"])
      ? row["missing"].map((item) => textOf(item))
      : [],
    citation: {
      reference: textOf(citation["reference"]),
      ...(url === undefined ? {} : { url }),
      ...(text === undefined ? {} : { text }),
    },
    state: enumOrThrow(row["state"], DEADLINE_STATES, "deadline state"),
    computedAt: temporal().Instant.from(textOf(row["computedAt"])),
    createdAt: temporal().Instant.from(textOf(row["createdAt"])),
    ...(typeof row["ruleVersion"] === "number"
      ? { ruleVersion: row["ruleVersion"] }
      : {}),
    ...(typeof dueOn === "string"
      ? { dueOn: plainDateOf(dueOn, "dueOn") }
      : {}),
    ...(satisfiedAt === undefined ? {} : { satisfiedAt }),
    ...(satisfiedBy === undefined ? {} : { satisfiedBy }),
    ...(satisfiedAction === undefined ? {} : { satisfiedAction }),
  };
}

/**
 * Deadlines: rule sets owned by the platform, versioned and approved once, and
 * the deadlines computed from a subject's facts. A rule whose facts are not all
 * known yields `unknown` with the facts it waits for, never a guess.
 */
export function createDeadlines(options: DeadlinesOptions): Deadlines {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResultType<string> => requireTenant(options.tenant);

  const client: Deadlines = {
    saveRules: (input) =>
      call(
        "save_rule_version",
        {
          jurisdiction: input.jurisdiction,
          kind: input.kind,
          rules: input.rules,
          ...(input.effectiveFrom === undefined
            ? {}
            : { effective_from: input.effectiveFrom.toString() }),
          ...(input.title === undefined ? {} : { title: input.title }),
        },
        (value) => versionOf(value, "save_rule_version"),
      ),
    approveRules: (input) =>
      call(
        "approve_rule_version",
        {
          version_id: input.versionId,
          ...(input.approvalId === undefined
            ? {}
            : { approval_id: input.approvalId }),
          ...(input.effectiveFrom === undefined
            ? {}
            : { effective_from: input.effectiveFrom.toString() }),
        },
        (value) => versionOf(value, "approve_rule_version"),
      ),
    rulesAt: ({ jurisdiction, kind, date }) =>
      call(
        "rule_version_at",
        {
          jurisdiction,
          kind,
          ...(date === undefined ? {} : { on_date: date.toString() }),
        },
        (value) =>
          value === null || value === undefined
            ? undefined
            : versionOf(value, "rule_version_at"),
      ),
    compute: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "compute_deadline",
          {
            tenant: organizationId,
            subject_type: input.subjectType,
            subject_id: input.subjectId,
            jurisdiction: input.jurisdiction,
            kind: input.kind,
            rule_key: input.ruleKey,
            facts: input.facts,
            ...(input.asOf === undefined
              ? {}
              : { as_of: input.asOf.toString() }),
          },
          (value) => deadlineOf(value, "compute_deadline"),
        ),
      ),
    recompute: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "recompute_deadlines",
          {
            tenant: organizationId,
            subject_type: input.subjectType,
            subject_id: input.subjectId,
            facts: input.facts ?? {},
          },
          Number,
        ),
      ),
    satisfy: ({ deadlineId, action }) =>
      call(
        "satisfy_deadline",
        {
          deadline_id: deadlineId,
          ...(action === undefined ? {} : { action }),
        },
        (value) => deadlineOf(value, "satisfy_deadline"),
      ),
    list: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_deadlines",
          {
            tenant: organizationId,
            filters: Object.fromEntries(
              Object.entries(list)
                .filter(([, value]) => value !== undefined)
                .map(([key, value]) => [
                  key,
                  typeof value === "object" ? String(value) : value,
                ]),
            ),
          },
          (value) =>
            recordsOf(value, "list_deadlines").map((row) =>
              deadlineOf(row, "list_deadlines"),
            ),
        ),
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "deadlines",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
