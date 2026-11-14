import type {
  Count,
  FacetResult,
  ListPage,
  PageOptions,
} from "../../core/block-helpers.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { CountOptions, FacetOptions } from "../../core/entity-list.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult as AsyncResultType } from "../../core/result.ts";
import type {
  DeadlineBasis,
  DeadlineCitation,
  DeadlineCounting,
  DeadlineExceptionResult,
  DeadlineFacts,
  DeadlineGroup,
  DeadlineGroupResult,
  DeadlineReview,
  DeadlineRule,
  DeadlineSpec,
  RuleVersionContent,
} from "../../sql/modules/deadlines-values.ts";
import type { BlockOptions } from "../shared.ts";

import { plainDateOf } from "../../core/block-helpers.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { entityList } from "../../core/entity-list.ts";
import { temporal } from "../../core/temporal-required.ts";
import { evaluateVersion as evaluateRuleVersion } from "../../sql/modules/deadlines-evaluate.ts";
import { validateRuleVersion as validateContent } from "../../sql/modules/deadlines-validate.ts";
import {
  DEADLINE_RESULTS,
  DEADLINE_STATES,
  RULE_VERSION_STATUSES,
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
import { deadlineListSurface } from "./lists.ts";

/** A version of a rule set: draft until approved, then frozen. */
export interface RuleVersion {
  readonly id: string;
  readonly jurisdiction: string;
  readonly kind: string;
  readonly version: number;
  readonly status: (typeof RULE_VERSION_STATUSES)[number];
  readonly rules: readonly DeadlineRule[];
  readonly groups: readonly DeadlineGroup[];
  readonly counting?: DeadlineCounting;
  /** Opaque data the block keeps and never reads. */
  readonly meta?: Readonly<Record<string, unknown>>;
  /** SHA-256 of the content, set when the version is approved. */
  readonly contentHash?: string;
  /** The first day the version applies. */
  readonly effectiveFrom?: Temporal.PlainDate;
  readonly approvedBy?: string;
  readonly approvedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
}

/** The deadline of one group (one month of a periodic rule) for one subject. */
export interface Deadline {
  readonly id: string;
  readonly organizationId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly jurisdiction: string;
  readonly kind: string;
  readonly groupKey: string;
  /** The rule that applied; absent when none did. */
  readonly ruleKey?: string;
  /** `YYYY-MM` for one month of a periodic rule. */
  readonly period?: string;
  readonly ruleVersionId: string;
  readonly ruleVersion?: number;
  readonly facts: DeadlineFacts;
  readonly result: (typeof DEADLINE_RESULTS)[number];
  /** Set when the result is `due`. */
  readonly dueOn?: Temporal.PlainDate;
  /** A date or result a missing answer could still change. */
  readonly provisional: boolean;
  /** The facts the deadline still asks, sorted. */
  readonly missing: readonly string[];
  /** The exception that decided a refusal. */
  readonly exception?: DeadlineExceptionResult;
  /** What needs a person's review; it never changes the result. */
  readonly review: readonly DeadlineReview[];
  /** What a due date rests on. */
  readonly basis?: DeadlineBasis;
  /** The applied rule's deadline as authored. */
  readonly deadline?: DeadlineSpec;
  readonly citation: DeadlineCitation;
  /** The date the deadline was evaluated on. */
  readonly asOf: Temporal.PlainDate;
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
  readonly groupKey?: string;
  readonly period?: string;
  readonly state?: Deadline["state"];
  readonly result?: Deadline["result"];
  readonly provisional?: boolean;
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
   * Saves a version's content as a draft version of a rule set, creating the
   * set on first use. Service role only.
   */
  saveRules(input: {
    readonly jurisdiction: string;
    readonly kind: string;
    readonly content: RuleVersionContent;
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
  /**
   * Computes and stores a subject's deadlines from its facts: one per group of
   * the version that applies on `asOf` (today by default), or only `group`'s,
   * and one per month for a periodic rule. A missing fact is unknown and `null`
   * does not exist or has not happened.
   */
  compute(
    input: DeadlineSubject & {
      readonly jurisdiction: string;
      readonly kind: string;
      readonly facts: DeadlineFacts;
      readonly asOf?: Temporal.PlainDate;
      readonly group?: string;
    },
  ): AsyncResultType<readonly Deadline[]>;
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
  /** One deadline by id, when the caller's read policy shows it. */
  get(deadlineId: string): AsyncResultType<Deadline>;
  /**
   * One keyset page of the organization's deadlines, soonest first. Sort by
   * `dueOn` or `createdAt`; filter by `subjectType`, `subjectId`, `groupKey`,
   * `period`, `state`, `result`, `provisional` and `dueBefore`.
   */
  page(options?: PageOptions): AsyncResultType<ListPage<Deadline>>;
  /**
   * The values of each facet (`state`, `result`, `groupKey`) and how many
   * deadlines hold each.
   */
  facets(options?: FacetOptions): AsyncResultType<readonly FacetResult[]>;
  /** How many deadlines match the page's filters. */
  count(options?: CountOptions): AsyncResultType<Count>;
}

/**
 * Evaluates a rule set version against facts in TypeScript, with the same
 * results as the database: one per group (one per month for a periodic rule),
 * or only `group`'s. Use it to preview a draft or to show dates without a round
 * trip. `asOf` is an ISO date, today by default.
 */
export function evaluateVersion(
  content: RuleVersionContent,
  facts: DeadlineFacts,
  asOf?: Temporal.PlainDate | string,
  group?: string,
): readonly DeadlineGroupResult[] {
  return evaluateRuleVersion(
    content,
    facts,
    asOf === undefined ? undefined : asOf.toString(),
    group,
  );
}

/** The problems of a version's content, or an empty array when it can be saved. */
export function validateRuleVersion(content: unknown): readonly string[] {
  return validateContent(content);
}

function objectOf(value: unknown): Readonly<Record<string, unknown>> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? Object.fromEntries(Object.entries(value))
    : {};
}

function optionalText(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}

function isKeyed<T extends { readonly key: string }>(
  value: unknown,
): value is T {
  return typeof value === "object" && value !== null && "key" in value;
}

function isObject<T>(value: unknown): value is T {
  return typeof value === "object" && value !== null && !Array.isArray(value);
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
    rules: Array.isArray(row["rules"])
      ? row["rules"].filter((rule) => isKeyed<DeadlineRule>(rule))
      : [],
    groups: Array.isArray(row["groups"])
      ? row["groups"].filter((group) => isKeyed<DeadlineGroup>(group))
      : [],
    createdAt: temporal().Instant.from(textOf(row["createdAt"])),
    ...(isObject<DeadlineCounting>(row["counting"])
      ? { counting: row["counting"] }
      : {}),
    ...(isObject<Readonly<Record<string, unknown>>>(row["meta"])
      ? { meta: row["meta"] }
      : {}),
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
  const ruleKey = optionalText(row["ruleKey"]);
  const period = optionalText(row["period"]);
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
    groupKey: textOf(row["groupKey"]),
    ruleVersionId: textOf(row["ruleVersionId"]),
    facts: objectOf(row["facts"]),
    result: enumOrThrow(row["result"], DEADLINE_RESULTS, "deadline result"),
    provisional: row["provisional"] === true,
    missing: Array.isArray(row["missing"])
      ? row["missing"].map((item) => textOf(item))
      : [],
    review: Array.isArray(row["review"])
      ? row["review"].filter((mark) => isObject<DeadlineReview>(mark))
      : [],
    asOf: plainDateOf(textOf(row["asOf"]), "asOf"),
    ...(ruleKey === undefined ? {} : { ruleKey }),
    ...(period === undefined ? {} : { period }),
    ...(isObject<DeadlineExceptionResult>(row["exception"])
      ? { exception: row["exception"] }
      : {}),
    ...(isObject<DeadlineBasis>(row["basis"]) ? { basis: row["basis"] } : {}),
    ...(row["deadline"] === "none" || isObject<DeadlineSpec>(row["deadline"])
      ? { deadline: row["deadline"] }
      : {}),
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
 * the deadlines computed from a subject's facts. A deadline whose facts are not
 * all known is `unknown` with the facts it waits for, never a guess.
 */
export function createDeadlines(options: DeadlinesOptions): Deadlines {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResultType<string> => requireTenant(options.tenant);

  const registry = entityList({
    entity: "deadline",
    surface: deadlineListSurface,
    call,
    tenant,
    fn: "page_deadlines",
    rowOf: deadlineOf,
  });

  const client: Deadlines = {
    saveRules: (input) =>
      call(
        "save_rule_version",
        {
          jurisdiction: input.jurisdiction,
          kind: input.kind,
          content: input.content,
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
          "compute_deadlines",
          {
            tenant: organizationId,
            subject_type: input.subjectType,
            subject_id: input.subjectId,
            jurisdiction: input.jurisdiction,
            kind: input.kind,
            facts: input.facts,
            ...(input.asOf === undefined
              ? {}
              : { as_of: input.asOf.toString() }),
            ...(input.group === undefined ? {} : { group_key: input.group }),
          },
          (value) =>
            recordsOf(value, "compute_deadlines").map((row) =>
              deadlineOf(row, "compute_deadlines"),
            ),
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
    get: (deadlineId) =>
      call("get_deadline", { deadline_id: deadlineId }, (value) =>
        deadlineOf(value, "get_deadline"),
      ),
    page: registry.page,
    facets: registry.facets,
    count: registry.count,
  };

  return withBlockHooks(client, options.hooks, {
    block: "deadlines",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
