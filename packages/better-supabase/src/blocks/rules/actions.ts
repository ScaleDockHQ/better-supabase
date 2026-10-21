import type { AsyncResult, Result } from "../../core/result.ts";
import type { ApprovalRequestInput } from "../approvals/approvals.ts";
import type { NotifierInput } from "../ports.ts";
import type { Rule, RuleActionHandler } from "./rules.ts";

import { dbError } from "../../core/errors.ts";
import { err, ok } from "../../core/result.ts";

/**
 * The context `dispatch` passes when rules start approvals or other subject
 * work.
 */
export interface RuleSubjectContext {
  readonly organizationId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  /** Passed on to the approval request, such as the expense amount. */
  readonly payload?: Readonly<Record<string, unknown>>;
  /** The outbox event the rules ran for; it keys retries of the same action. */
  readonly eventId?: string;
}

/** The part of the approvals client the handler calls. */
export interface RuleApprovals {
  request(input: ApprovalRequestInput): AsyncResult<unknown>;
}

function invalid(rule: Rule, kind: string, problem: string): Result<never> {
  return err(
    dbError(
      "invalid_request",
      `The rule "${rule.name}" has a ${kind} action ${problem}`,
      { hint: "RULE_ACTION_INVALID" },
    ),
  );
}

function textConfig(
  config: Readonly<Record<string, unknown>> | undefined,
  key: string,
): string | undefined {
  const value = config?.[key];

  return typeof value === "string" && value !== "" ? value : undefined;
}

/** A key that stays the same when the outbox retries the event. */
function actionKey(
  rule: Rule,
  kind: string,
  context: RuleSubjectContext,
): string {
  return `rule:${rule.id}:${kind}:${context.eventId ?? `${context.subjectType}/${context.subjectId}`}`;
}

/**
 * The `approvals.request` handler: starts an approval of the subject for the
 * action in the rule's `config.action`, such as `{ kind: "approvals.request",
 * config: { action: "manager_review" } }`.
 */
export function approvalsAction(
  approvals: RuleApprovals,
): RuleActionHandler<RuleSubjectContext> {
  return ({ action, rule, context }) => {
    const name = action.config?.["action"];

    if (typeof name !== "string" || name === "") {
      return err(
        dbError(
          "invalid_request",
          `The rule "${rule.name}" has an approvals.request action without config.action`,
          { hint: "RULE_ACTION_INVALID" },
        ),
      );
    }

    const reason = action.config?.["reason"];

    return approvals.request({
      organizationId: context.organizationId,
      subjectType: context.subjectType,
      subjectId: context.subjectId,
      action: name,
      reason: typeof reason === "string" ? reason : `Rule: ${rule.name}`,
      ...(context.payload === undefined ? {} : { payload: context.payload }),
    });
  };
}

/** The part of a `notifier` port (the notifications block) the handler calls. */
export interface RuleNotifier {
  send(type: string, input: NotifierInput): unknown;
}

function recipientsOf(
  config: Readonly<Record<string, unknown>> | undefined,
  payload: Readonly<Record<string, unknown>> | undefined,
): readonly string[] {
  const listed = config?.["recipients"];
  const field = textConfig(config, "recipientField");
  const read = field === undefined ? undefined : payload?.[field];

  return [listed, read]
    .flat()
    .filter(
      (value): value is string => typeof value === "string" && value !== "",
    );
}

/**
 * The `notify` handler: sends the notification type in `config.type` to the
 * user ids in `config.recipients` and in the payload column that
 * `config.recipientField` names, with `config.data` and the payload as its
 * data: `{ kind: "notify", config: { type: "task.assigned", recipientField:
 * "assignee_id" } }`.
 */
export function notifyAction(
  notifier: RuleNotifier,
): RuleActionHandler<RuleSubjectContext> {
  return async ({ action, rule, context }) => {
    const type = textConfig(action.config, "type");

    if (type === undefined) {
      return invalid(rule, "notify", "without config.type");
    }

    const recipients = recipientsOf(action.config, context.payload);

    if (recipients.length === 0) {
      return invalid(
        rule,
        "notify",
        "without recipients (config.recipients or a filled config.recipientField)",
      );
    }

    const data = action.config?.["data"];

    const sent = await notifier.send(type, {
      recipients,
      tenant: context.organizationId,
      key: actionKey(rule, "notify", context),
      subject: { type: context.subjectType, id: context.subjectId },
      data: {
        ...context.payload,
        ...(typeof data === "object" && data !== null ? data : {}),
        rule: rule.name,
      },
    });

    return ok(sent);
  };
}

/** What `setFieldAction` asks the app to write: one column of the subject's row. */
export interface RuleFieldWrite {
  readonly organizationId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  readonly field: string;
  readonly value: unknown;
}

/** Writes one field, such as through an app table repository's `update`. */
export type RuleFieldSetter = (
  write: RuleFieldWrite,
) => Result<unknown> | PromiseLike<Result<unknown>>;

/**
 * The `set_field` handler: writes `config.value` to the subject's
 * `config.field`: `{ kind: "set_field", config: { field: "status", value:
 * "review" } }`. The setter decides which fields it accepts.
 */
export function setFieldAction(
  setField: RuleFieldSetter,
): RuleActionHandler<RuleSubjectContext> {
  return ({ action, rule, context }) => {
    const field = textConfig(action.config, "field");

    if (field === undefined) {
      return invalid(rule, "set_field", "without config.field");
    }

    if (action.config === undefined || !Object.hasOwn(action.config, "value")) {
      return invalid(rule, "set_field", "without config.value");
    }

    return setField({
      organizationId: context.organizationId,
      subjectType: context.subjectType,
      subjectId: context.subjectId,
      field,
      value: action.config["value"],
    });
  };
}

/** The part of the outgoing webhooks client the handler calls. */
export interface RuleWebhooks {
  dispatch(input: {
    readonly endpointId: string;
    readonly type: string;
    readonly data: unknown;
    readonly eventId?: string;
  }): AsyncResult<string>;
}

/**
 * The `webhook` handler: queues a delivery to the endpoint in
 * `config.endpointId`, typed `config.type` or the rule's trigger, with the
 * payload as its data: `{ kind: "webhook", config: { endpointId: "..." } }`.
 */
export function webhookAction(
  webhooks: RuleWebhooks,
): RuleActionHandler<RuleSubjectContext> {
  return ({ action, rule, context }) => {
    const endpointId = textConfig(action.config, "endpointId");

    if (endpointId === undefined) {
      return invalid(rule, "webhook", "without config.endpointId");
    }

    return webhooks.dispatch({
      endpointId,
      type: textConfig(action.config, "type") ?? rule.trigger,
      data: {
        subjectType: context.subjectType,
        subjectId: context.subjectId,
        ...context.payload,
      },
      ...(context.eventId === undefined ? {} : { eventId: context.eventId }),
    });
  };
}

/** The part of the workflow builder client the handler calls. */
export interface RuleWorkflows {
  run(input: {
    readonly definition: string;
    readonly input?: unknown;
    readonly idempotencyKey?: string;
    readonly subject?: { readonly type: string; readonly id: string };
    readonly tenant?: string;
  }): AsyncResult<string>;
}

/**
 * The `workflow` handler: starts the workflow definition in `config.definition`
 * on the subject, with the payload as its input: `{ kind: "workflow", config: {
 * definition: "..." } }`. A retried event starts no second run.
 */
export function workflowAction(
  workflows: RuleWorkflows,
): RuleActionHandler<RuleSubjectContext> {
  return ({ action, rule, context }) => {
    const definition = textConfig(action.config, "definition");

    if (definition === undefined) {
      return invalid(rule, "workflow", "without config.definition");
    }

    return workflows.run({
      definition,
      input: context.payload ?? {},
      idempotencyKey: actionKey(rule, "workflow", context),
      subject: { type: context.subjectType, id: context.subjectId },
      tenant: context.organizationId,
    });
  };
}
