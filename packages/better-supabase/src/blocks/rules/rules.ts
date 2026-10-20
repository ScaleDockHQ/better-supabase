/// <reference lib="esnext.temporal" />

import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { DbError, ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type {
  FilterEvaluation,
  FilterRecordField,
} from "../../list/filter-evaluate.ts";
import type {
  FilterClock,
  FilterFieldType,
  FilterQuery,
  FilterRule,
} from "../../list/filter-query.ts";
import type { RuleField, RuleFieldCatalog } from "./fields.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok, type Result } from "../../core/result.ts";
import { evaluateFilterQuery } from "../../list/filter-evaluate.ts";
import { FILTER_OPERATORS } from "../../list/filter-query.ts";
import {
  applyTemporal,
  blockCall,
  type BlockTemporalOptions,
  errorText,
  instantArg,
  isRecord,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
  toInstant,
} from "../shared.ts";
import { ruleFilterFieldInfo } from "./fields.ts";

/** What a rule runs when it matches: a kind the app handles and its settings. */
export interface RuleAction {
  /** Such as `approvals.request` or `notifications.send`. */
  readonly kind: string;
  readonly config?: Readonly<Record<string, unknown>>;
}

export interface Rule {
  readonly id: string;
  readonly organizationId: string;
  readonly subjectType: string;
  /** The event type the rule is tested on, such as `expense.submitted`. */
  readonly trigger: string;
  readonly name: string;
  readonly description: string | undefined;
  readonly conditions: FilterQuery;
  readonly actions: readonly RuleAction[];
  readonly enabled: boolean;
  /** A match ends the evaluation, so later rules for the trigger don't run. */
  readonly stopProcessing: boolean;
  /** The rank key rules are tested in. */
  readonly rank: string;
  readonly version: number;
  readonly createdBy: string | undefined;
  readonly updatedBy: string | undefined;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** `save`'s input: left-out keys keep their value on an existing rule. */
export interface RuleInput {
  readonly id?: string;
  /** The version the editor read; a newer stored one fails with `RULE_CONFLICT`. */
  readonly version?: number;
  /** Required for a new rule; it can't change later. */
  readonly subjectType?: string;
  readonly trigger?: string;
  readonly name?: string;
  readonly description?: string | null;
  readonly conditions?: FilterQuery;
  readonly actions?: readonly RuleAction[];
  /** Turning a rule on takes `rules.publish`. */
  readonly enabled?: boolean;
  readonly stopProcessing?: boolean;
}

export interface RuleVersion {
  readonly ruleId: string;
  readonly version: number;
  readonly name: string;
  readonly conditions: FilterQuery;
  readonly actions: readonly RuleAction[];
  readonly savedBy: string | undefined;
  readonly savedAt: Temporal.Instant;
}

/** A rule that matched, with the truth of every condition and group by node id. */
export interface RuleMatch {
  readonly rule: Rule;
  readonly results: Readonly<Record<string, boolean | null>>;
}

/** One entry of a rule's evaluation log. */
export interface RuleEvaluationEntry {
  readonly id: string;
  readonly organizationId: string;
  readonly ruleId: string;
  readonly version: number;
  readonly subjectType: string;
  readonly subjectId: string | undefined;
  readonly trigger: string;
  readonly matched: boolean;
  readonly results: Readonly<Record<string, boolean | null>>;
  readonly mode: "live" | "test";
  readonly evaluatedBy: string | undefined;
  readonly evaluatedAt: Temporal.Instant;
}

export interface RuleListOptions {
  readonly subjectType?: string;
  readonly trigger?: string;
  readonly enabled?: boolean;
}

/** What `matching` and `run` test: one subject, as the trigger event saw it. */
export interface RuleSubject {
  readonly subjectType: string;
  readonly trigger: string;
  /** The record the field catalog's columns read, such as the expense row with its submitter. */
  readonly subject: Readonly<Record<string, unknown>>;
  /** The IANA zone relative dates ("today") resolve in. Default `UTC`. */
  readonly timeZone?: string;
}

export interface RulesOptions extends BlockTemporalOptions {
  /** The caller's transport (`rpcTransport(supabase)`). */
  readonly transport: BlockTransport;
  /** The module schema, or its API schema. Default `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: BlockHooks<Rules>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

export interface Rules {
  /** The field catalog, for one subject type or all of them. */
  fields(subjectType?: string): AsyncResult<readonly RuleField[]>;
  /** The organization's rules in evaluation order (needs `rules.read`). */
  list(
    organizationId: string,
    options?: RuleListOptions,
  ): AsyncResult<readonly Rule[]>;
  /** `undefined` when the caller can't read a rule with this id. */
  get(id: string): AsyncResult<Rule | undefined>;
  /**
   * Creates or changes a rule. `rules.edit` covers disabled rules;
   * enabling a rule or changing an enabled one takes `rules.publish`.
   */
  save(organizationId: string, input: RuleInput): AsyncResult<Rule>;
  /** Turns a rule on or off (needs `rules.publish`). */
  setEnabled(id: string, enabled: boolean): AsyncResult<Rule>;
  /** Moves a rule to a rank key from `rankBetween` over its neighbours. */
  move(id: string, rank: string): AsyncResult<Rule>;
  /** Removes a rule with its history (needs `rules.admin`); `false` when there is none to remove. */
  remove(id: string): AsyncResult<boolean>;
  /** Saved versions, newest first. */
  versions(id: string): AsyncResult<readonly RuleVersion[]>;
  /** The evaluation log, newest first. */
  evaluations(
    id: string,
    options?: {
      readonly before?: Temporal.Instant;
      readonly pageSize?: number;
    },
  ): AsyncResult<readonly RuleEvaluationEntry[]>;
  /** The enabled rules for the trigger that match, evaluated in the database. */
  matching(
    organizationId: string,
    input: RuleSubject,
  ): AsyncResult<readonly RuleMatch[]>;
  /**
   * Runs a rule's stored conditions on a sample record and logs it as a test
   * (needs `rules.edit`). Nothing runs; the result says what would match.
   */
  test(
    rule: Rule,
    subject: Readonly<Record<string, unknown>>,
    options?: {
      readonly fields?: readonly RuleField[];
      readonly subjectId?: string;
      readonly clock?: FilterClock;
    },
  ): AsyncResult<FilterEvaluation>;
}

const FIELD_TYPES = Object.keys(FILTER_OPERATORS);

function isFieldType(value: unknown): value is FilterFieldType {
  return typeof value === "string" && FIELD_TYPES.includes(value);
}

function isFilterNode(value: unknown): value is FilterQuery | FilterRule {
  if (!isRecord(value) || typeof value["id"] !== "string") {
    return false;
  }

  if (value["type"] === "rule") {
    return Array.isArray(value["path"]);
  }

  const rules = value["rules"];

  return (
    value["type"] === "group" &&
    (value["combinator"] === "and" || value["combinator"] === "or") &&
    Array.isArray(rules) &&
    rules.every(isFilterNode)
  );
}

function conditionsOf(value: unknown): FilterQuery {
  if (!isFilterNode(value) || value.type !== "group") {
    throw new TypeError(`a rule's conditions are ${JSON.stringify(value)}`);
  }

  return value;
}

function actionsOf(value: unknown): readonly RuleAction[] {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.filter(isRecord).map((action) => ({
    kind: textOf(action["kind"]),
    ...(isRecord(action["config"]) ? { config: action["config"] } : {}),
  }));
}

function resultsOf(value: unknown): Readonly<Record<string, boolean | null>> {
  if (!isRecord(value)) {
    return {};
  }

  return Object.fromEntries(
    Object.entries(value).map(([key, truth]) => [
      key,
      typeof truth === "boolean" ? truth : null,
    ]),
  );
}

/** A rule row from the module's functions. */
export function ruleOf(value: unknown): Rule {
  const row = recordOf(value, "rule");

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    subjectType: textOf(row["subjectType"]),
    trigger: textOf(row["trigger"]),
    name: textOf(row["name"]),
    description: optionalText(row["description"]),
    conditions: conditionsOf(row["conditions"]),
    actions: actionsOf(row["actions"]),
    enabled: row["enabled"] === true,
    stopProcessing: row["stopProcessing"] === true,
    rank: textOf(row["rank"]),
    version: Number(row["version"]),
    createdBy: optionalText(row["createdBy"]),
    updatedBy: optionalText(row["updatedBy"]),
    createdAt: toInstant(textOf(row["createdAt"])),
    updatedAt: toInstant(textOf(row["updatedAt"])),
  };
}

function fieldOf(value: Record<string, unknown>): RuleField {
  const type = value["type"];

  if (!isFieldType(type)) {
    throw new TypeError(`rule field type ${JSON.stringify(type)}`);
  }

  const options = value["options"];
  const operators = value["operators"];

  return {
    subjectType: textOf(value["subjectType"]),
    id: textOf(value["id"]),
    label: textOf(value["label"]),
    description: optionalText(value["description"]),
    type,
    column: textOf(value["column"]),
    columnType: textOf(value["columnType"]),
    nullable: value["nullable"] !== false,
    options: Array.isArray(options)
      ? options.filter(isRecord).map((option) => ({
          value: textOf(option["value"]),
          label: textOf(option["label"] ?? option["value"]),
        }))
      : undefined,
    operators: Array.isArray(operators) ? operators.map(textOf) : undefined,
  };
}

function versionOf(value: Record<string, unknown>): RuleVersion {
  return {
    ruleId: textOf(value["ruleId"]),
    version: Number(value["version"]),
    name: textOf(value["name"]),
    conditions: conditionsOf(value["conditions"]),
    actions: actionsOf(value["actions"]),
    savedBy: optionalText(value["savedBy"]),
    savedAt: toInstant(textOf(value["savedAt"])),
  };
}

function evaluationOf(value: unknown): RuleEvaluationEntry {
  const row = recordOf(value, "rule evaluation");

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    ruleId: textOf(row["ruleId"]),
    version: Number(row["version"]),
    subjectType: textOf(row["subjectType"]),
    subjectId: optionalText(row["subjectId"]),
    trigger: textOf(row["trigger"]),
    matched: row["matched"] === true,
    results: resultsOf(row["results"]),
    mode: row["mode"] === "test" ? "test" : "live",
    evaluatedBy: optionalText(row["evaluatedBy"]),
    evaluatedAt: toInstant(textOf(row["evaluatedAt"])),
  };
}

function matchesOf(value: unknown): readonly RuleMatch[] {
  return recordsOf(value, "matching_rules").map((entry) => ({
    rule: ruleOf(entry["rule"]),
    results: resultsOf(entry["results"]),
  }));
}

/** Catalog fields in the shape `evaluateFilterQuery` reads. */
export function ruleRecordFields(
  fields: readonly RuleField[],
): readonly FilterRecordField[] {
  return ruleFilterFieldInfo(fields);
}

/**
 * Tests a rule's conditions on one record in memory, the same way the
 * database's `rule_evaluate` does. `fields` is the subject type's catalog.
 */
export function evaluateRule(
  rule: Pick<Rule, "conditions">,
  subject: unknown,
  fields: readonly RuleField[],
  clock?: FilterClock,
): FilterEvaluation {
  return evaluateFilterQuery(
    rule.conditions,
    subject,
    ruleRecordFields(fields),
    clock,
  );
}

function inputArg(input: RuleInput): Record<string, unknown> {
  const out: Record<string, unknown> = {};

  for (const [key, value] of Object.entries(input)) {
    if (value !== undefined) {
      out[key] = value;
    }
  }

  return out;
}

/** Tenant rules as the caller: the catalog, the rules, their history and tests. */
export function createRules(options: RulesOptions): Rules {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const fields = (subjectType?: string): AsyncResult<readonly RuleField[]> =>
    call("rule_fields_list", { subject_type: subjectType ?? null }, (value) =>
      recordsOf(value, "rule_fields_list").map(fieldOf),
    );

  const client: Rules = {
    fields,
    list: (organizationId, filter = {}) =>
      call(
        "rules_list",
        {
          tenant: organizationId,
          subject_type: filter.subjectType ?? null,
          trigger: filter.trigger ?? null,
          enabled: filter.enabled ?? null,
        },
        (value) => recordsOf(value, "rules_list").map(ruleOf),
      ),
    get: (id) =>
      call("rule_get", { id }, (value) =>
        isRecord(value) ? ruleOf(value) : undefined,
      ),
    save: (organizationId, input) =>
      call(
        "save_rule",
        { tenant: organizationId, rule: inputArg(input) },
        ruleOf,
      ),
    setEnabled: (id, enabled) =>
      call("set_rule_enabled", { id, enabled }, ruleOf),
    move: (id, rank) => call("rank_rule", { id, rank }, ruleOf),
    remove: (id) => call("remove_rule", { id }, (value) => value === true),
    versions: (id) =>
      call("rule_versions_list", { id }, (value) =>
        recordsOf(value, "rule_versions_list").map(versionOf),
      ),
    evaluations: (id, page = {}) =>
      call(
        "rule_evaluations_list",
        {
          rule: id,
          before: instantArg(page.before) ?? null,
          page_size: page.pageSize ?? 50,
        },
        (value) => recordsOf(value, "rule_evaluations_list").map(evaluationOf),
      ),
    matching: (organizationId, input) =>
      call(
        "matching_rules",
        {
          tenant: organizationId,
          subject_type: input.subjectType,
          trigger: input.trigger,
          subject: input.subject,
          time_zone: input.timeZone ?? "UTC",
        },
        matchesOf,
      ),
    test: (rule, subject, test = {}) => {
      const catalog: AsyncResult<readonly RuleField[]> =
        test.fields === undefined
          ? fields(rule.subjectType)
          : AsyncResult.ok(test.fields);

      return catalog.andThen(async (found) => {
        let evaluation: FilterEvaluation;

        try {
          evaluation = evaluateRule(rule, subject, found, test.clock);
        } catch (cause) {
          return err(dbError("invalid_request", errorText(cause)));
        }

        const logged = await call(
          "record_rule_evaluation",
          {
            rule: rule.id,
            subject_id: test.subjectId ?? null,
            matched: evaluation.matched,
            results: evaluation.results,
            mode: "test",
          },
          evaluationOf,
        );

        return logged.ok ? ok(evaluation) : logged;
      });
    },
  };

  return withBlockHooks(client, options.hooks, {
    block: "rules",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}

export interface RulesAdminOptions extends BlockTemporalOptions {
  /** A service-role transport: `sync_rule_fields` and `run_rules` are granted to `service_role` only. */
  readonly transport: BlockTransport;
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

export interface RulesAdmin {
  /** Replaces the subject type's field catalog; returns how many fields it has. */
  syncFields(catalog: RuleFieldCatalog): AsyncResult<number>;
  /** Evaluates the enabled rules for the trigger, logs each one live and returns the matches. */
  run(
    organizationId: string,
    input: RuleSubject & { readonly subjectId?: string },
  ): AsyncResult<readonly RuleMatch[]>;
}

/** The field sync and live evaluation, with a service-role client. */
export function createRulesAdmin(options: RulesAdminOptions): RulesAdmin {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  return {
    syncFields: (catalog) =>
      call(
        "sync_rule_fields",
        {
          subject_type: catalog.subjectType,
          fields: catalog.fields.map((field) => ({
            id: field.id,
            label: field.label,
            ...(field.description === undefined
              ? {}
              : { description: field.description }),
            type: field.type,
            column: field.column,
            columnType: field.columnType,
            nullable: field.nullable,
            ...(field.options === undefined ? {} : { options: field.options }),
            ...(field.operators === undefined
              ? {}
              : { operators: field.operators }),
          })),
        },
        Number,
      ),
    run: (organizationId, input) =>
      call(
        "run_rules",
        {
          tenant: organizationId,
          subject_type: input.subjectType,
          trigger: input.trigger,
          subject_id: input.subjectId ?? null,
          subject: input.subject,
          time_zone: input.timeZone ?? "UTC",
        },
        matchesOf,
      ),
  };
}

/** What a handler receives: the action, the rule it belongs to and the dispatch context. */
export interface RuleActionCall<C = unknown> {
  readonly action: RuleAction;
  readonly rule: Rule;
  readonly results: Readonly<Record<string, boolean | null>>;
  readonly context: C;
}

/** Runs one action kind. Return a `Result`; a throw becomes an `unexpected` error. */
export type RuleActionHandler<C = unknown> = (
  call: RuleActionCall<C>,
) => Result<unknown> | PromiseLike<Result<unknown>>;

/** The outcome of one action: its value, or the error its handler returned. */
export type RuleActionOutcome =
  | {
      readonly ruleId: string;
      readonly kind: string;
      readonly ok: true;
      readonly value: unknown;
    }
  | {
      readonly ruleId: string;
      readonly kind: string;
      readonly ok: false;
      readonly error: DbError;
    };

export interface RuleDispatcherOptions<C> {
  /** A handler per action kind, such as `approvals.request`. */
  readonly handlers: Readonly<Record<string, RuleActionHandler<C>>>;
}

export interface RuleDispatcher<C = unknown> {
  /**
   * Runs the actions of `matches` in order. A failed action doesn't stop the
   * others; each one's outcome comes back. A kind without a handler is an
   * `invalid_request` outcome with the hint `RULE_ACTION_UNKNOWN`.
   */
  dispatch(
    matches: readonly RuleMatch[],
    context: C,
  ): AsyncResult<readonly RuleActionOutcome[]>;
}

/** Runs matched rules' actions with the app's handlers. */
export function createRuleDispatcher<C = unknown>(
  options: RuleDispatcherOptions<C>,
): RuleDispatcher<C> {
  const runOne = async (
    call: RuleActionCall<C>,
  ): Promise<RuleActionOutcome> => {
    const { action, rule } = call;
    const handler = options.handlers[action.kind];

    if (handler === undefined) {
      return {
        ruleId: rule.id,
        kind: action.kind,
        ok: false,
        error: dbError(
          "invalid_request",
          `No handler for the rule action "${action.kind}"`,
          { hint: "RULE_ACTION_UNKNOWN" },
        ),
      };
    }

    let result: Result<unknown>;

    try {
      result = await handler(call);
    } catch (cause) {
      result = err(dbError("unexpected", errorText(cause)));
    }

    return result.ok
      ? { ruleId: rule.id, kind: action.kind, ok: true, value: result.data }
      : { ruleId: rule.id, kind: action.kind, ok: false, error: result.error };
  };

  return {
    dispatch: (matches, context) =>
      AsyncResult.from(async () => {
        const outcomes: RuleActionOutcome[] = [];

        for (const match of matches) {
          for (const action of match.rule.actions) {
            // Actions run in rule order, one at a time.
            outcomes.push(
              await runOne({
                action,
                rule: match.rule,
                results: match.results,
                context,
              }),
            );
          }
        }

        return ok(outcomes);
      }),
  };
}

/** An outbox event as the rule sink reads it; an `OutboxEvent` fits. */
export interface RuleSinkEvent {
  readonly id: string;
  readonly type: string;
  readonly payload?: unknown;
  readonly tenant?: string | null;
}

/** What `load` returns for an event the rules should see: the subject and the dispatch context. */
export interface RuleSinkTarget<C> {
  readonly organizationId: string;
  readonly subjectType: string;
  readonly subjectId?: string;
  /** The record the field catalog's columns read. */
  readonly subject: Readonly<Record<string, unknown>>;
  readonly timeZone?: string;
  readonly context: C;
}

export interface RuleSinkOptions<C> {
  /** `rules.run` from `createRulesAdmin`, which logs each evaluation live. */
  readonly rules: Pick<RulesAdmin, "run">;
  readonly dispatcher: RuleDispatcher<C>;
  /**
   * Reads the subject an event is about, such as the app table row named by
   * `payload.id`. `undefined` skips the event.
   */
  readonly load: (
    event: RuleSinkEvent,
  ) =>
    | RuleSinkTarget<C>
    | undefined
    | PromiseLike<RuleSinkTarget<C> | undefined>;
  /** Receives each event's action outcomes, failed ones included. */
  readonly onOutcomes?: (
    event: RuleSinkEvent,
    outcomes: readonly RuleActionOutcome[],
  ) => void;
}

/**
 * An outbox consumer handler that tests the rules whose trigger is the
 * event's type and runs the actions of the ones that match, for
 * `outbox.consume("rules", createRuleSink(...))`. It throws
 * when the evaluation fails, so the outbox retries the event; a failed
 * action goes to `onOutcomes` instead, since a retry would run the others
 * again.
 */
export function createRuleSink<C = unknown>(
  options: RuleSinkOptions<C>,
): (events: readonly RuleSinkEvent[]) => Promise<void> {
  return async (events) => {
    for (const event of events) {
      const target = await options.load(event);

      if (target === undefined) {
        continue;
      }

      const matches = await options.rules
        .run(target.organizationId, {
          subjectType: target.subjectType,
          trigger: event.type,
          subject: target.subject,
          ...(target.subjectId === undefined
            ? {}
            : { subjectId: target.subjectId }),
          ...(target.timeZone === undefined
            ? {}
            : { timeZone: target.timeZone }),
        })
        .orThrow();

      if (matches.length === 0) {
        continue;
      }

      const outcomes = await options.dispatcher
        .dispatch(matches, target.context)
        .orThrow();

      options.onOutcomes?.(event, outcomes);
    }
  };
}
