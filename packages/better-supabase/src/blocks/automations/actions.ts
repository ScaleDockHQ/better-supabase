import type {
  Action,
  ActionCall,
  ActionContext,
  ActionOrigin,
} from "../../core/automation.ts";
import type { AsyncResult, Result } from "../../core/result.ts";
import type { RecordRef } from "../../schema/types.ts";
import type { ApprovalRequestInput } from "../approvals/approvals.ts";
import type { NotifierInput } from "../ports.ts";

import { defineAction } from "../../core/automation.ts";
import { dbError } from "../../core/errors.ts";
import { err, ok } from "../../core/result.ts";

/** The record and event an action runs for. */
export type RuleSubjectContext = ActionContext;

/**
 * The part of the approvals client the action calls. Its tenant must be the
 * context's `organizationId`.
 */
export interface RuleApprovals {
  request(
    subject: RecordRef,
    input: ApprovalRequestInput,
  ): AsyncResult<unknown>;
}

function invalid(call: ActionCall, problem: string): Result<never> {
  return err(
    dbError(
      "invalid_request",
      `The ${call.origin.type} "${call.origin.name}" has a ${call.action.kind} action ${problem}`,
      { hint: "ACTION_CONFIG_INVALID" },
    ),
  );
}

function originLabel(origin: ActionOrigin): string {
  switch (origin.type) {
    case "automation": {
      return "Rule";
    }

    case "workflow": {
      return "Workflow";
    }

    case "sequence": {
      return "Sequence";
    }

    default: {
      const never: never = origin.type;

      return never;
    }
  }
}

function textConfig(
  config: Readonly<Record<string, unknown>> | undefined,
  key: string,
): string | undefined {
  const value = config?.[key];

  return typeof value === "string" && value !== "" ? value : undefined;
}

/**
 * The `approvals.request` action: starts an approval of the subject for the
 * action in `config.action`, such as `{ kind: "approvals.request", config: {
 * action: "manager_review" } }`.
 */
export function approvalsAction(approvals: RuleApprovals): Action {
  return defineAction({
    kind: "approvals.request",
    title: "Request an approval",
    run: (call) => {
      const { action, context, origin } = call;
      const name = textConfig(action.config, "action");

      if (name === undefined) {
        return invalid(call, "without config.action");
      }

      const reason = textConfig(action.config, "reason");

      return approvals.request(
        { type: context.subjectType, id: context.subjectId },
        {
          action: name,
          reason: reason ?? `${originLabel(origin)}: ${origin.name}`,
          ...(context.payload === undefined
            ? {}
            : { payload: context.payload }),
        },
      );
    },
  });
}

/** The part of a `notifier` port (the notifications block) the action calls. */
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
 * The `notify` action: sends the notification type in `config.type` to the user
 * ids in `config.recipients` and in the payload column that
 * `config.recipientField` names, with `config.data` and the payload as its
 * data: `{ kind: "notify", config: { type: "task.assigned", recipientField:
 * "assignee_id" } }`.
 */
export function notifyAction(notifier: RuleNotifier): Action {
  return defineAction({
    kind: "notify",
    title: "Send a notification",
    run: async (call) => {
      const { action, context, origin } = call;
      const type = textConfig(action.config, "type");

      if (type === undefined) {
        return invalid(call, "without config.type");
      }

      const recipients = recipientsOf(action.config, context.payload);

      if (recipients.length === 0) {
        return invalid(
          call,
          "without recipients (config.recipients or a filled config.recipientField)",
        );
      }

      const data = action.config?.["data"];

      const sent = await notifier.send(type, {
        recipients,
        tenant: context.organizationId,
        key: call.key,
        subject: { type: context.subjectType, id: context.subjectId },
        data: {
          ...context.payload,
          ...(typeof data === "object" && data !== null ? data : {}),
          [origin.type === "automation" ? "rule" : origin.type]: origin.name,
        },
      });

      return ok(sent);
    },
  });
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
 * The `set_field` action: writes `config.value` to the subject's
 * `config.field`: `{ kind: "set_field", config: { field: "status", value:
 * "review" } }`. The setter decides which fields it accepts.
 */
export function setFieldAction(setField: RuleFieldSetter): Action {
  return defineAction({
    kind: "set_field",
    title: "Set a field",
    run: (call) => {
      const { action, context } = call;
      const field = textConfig(action.config, "field");

      if (field === undefined) {
        return invalid(call, "without config.field");
      }

      if (
        action.config === undefined ||
        !Object.hasOwn(action.config, "value")
      ) {
        return invalid(call, "without config.value");
      }

      return setField({
        organizationId: context.organizationId,
        subjectType: context.subjectType,
        subjectId: context.subjectId,
        field,
        value: action.config["value"],
      });
    },
  });
}

/** The part of the outgoing webhooks client the action calls. */
export interface RuleWebhooks {
  dispatch(input: {
    readonly endpointId: string;
    readonly type: string;
    readonly data: unknown;
    readonly eventId?: string;
  }): AsyncResult<string>;
}

/**
 * The `webhook` action: queues a delivery to the endpoint in
 * `config.endpointId`, typed `config.type` or the trigger, with the payload as
 * its data: `{ kind: "webhook", config: { endpointId: "..." } }`.
 */
export function webhookAction(webhooks: RuleWebhooks): Action {
  return defineAction({
    kind: "webhook",
    title: "Send a webhook",
    run: (call) => {
      const { action, context, origin } = call;
      const endpointId = textConfig(action.config, "endpointId");

      if (endpointId === undefined) {
        return invalid(call, "without config.endpointId");
      }

      const type = textConfig(action.config, "type") ?? origin.trigger;

      if (type === undefined) {
        return invalid(call, "without config.type");
      }

      return webhooks.dispatch({
        endpointId,
        type,
        data: {
          subjectType: context.subjectType,
          subjectId: context.subjectId,
          ...context.payload,
        },
        ...(context.eventId === undefined ? {} : { eventId: context.eventId }),
      });
    },
  });
}

/** The part of the workflow editor client the action calls. */
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
 * The `workflow` action: starts the workflow definition in `config.definition`
 * on the subject, with the payload as its input: `{ kind: "workflow", config: {
 * definition: "..." } }`. Workflows start only this way, so a retried event
 * starts no second run.
 */
export function workflowAction(workflows: RuleWorkflows): Action {
  return defineAction({
    kind: "workflow",
    title: "Start a workflow",
    run: (call) => {
      const { action, context } = call;
      const definition = textConfig(action.config, "definition");

      if (definition === undefined) {
        return invalid(call, "without config.definition");
      }

      return workflows.run({
        definition,
        input: context.payload ?? {},
        idempotencyKey: call.key,
        subject: { type: context.subjectType, id: context.subjectId },
        tenant: context.organizationId,
      });
    },
  });
}
