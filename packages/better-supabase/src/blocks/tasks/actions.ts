import type { Action, ActionFactory } from "../../core/automation.ts";
import type { Result } from "../../core/result.ts";
import type {
  ConversionClients,
  ConversionContext,
} from "../automations/conversion.ts";
import type { Conversation } from "../inbox/types.ts";
import type { WorkItem, WorkItemInput } from "./tasks.ts";

import { dbError } from "../../core/errors.ts";
import { err, ok } from "../../core/result.ts";
import {
  defineConversionAction,
  narrowClients,
} from "../automations/conversion.ts";
import { workItemInputSchema } from "./schemas.ts";

/** `blocks.inbox`, `blocks.tasks` and `blocks.relations` for one organization. */
export interface TaskFromConversationClients extends ConversionClients {
  readonly inbox: {
    readonly conversations: {
      get(conversationId: string): PromiseLike<Result<Conversation | null>>;
    };
  };
  readonly tasks: {
    create(
      organizationId: string,
      input: WorkItemInput,
      assigneeIds?: readonly string[],
    ): PromiseLike<Result<WorkItem>>;
  };
}

export interface TaskFromConversationOptions {
  /** The clients for one organization, over a service connection. */
  readonly clients: (
    tenant: string,
  ) => TaskFromConversationClients | PromiseLike<TaskFromConversationClients>;
  /** The task for a conversation. Default: its subject or preview as the title. */
  readonly map?: (
    conversation: Conversation,
    context: ConversionContext<TaskFromConversationClients>,
  ) => WorkItemInput;
  /** Assigns the task to the conversation's assignee. Default: true. */
  readonly assign?: boolean;
}

function conversationTitle(conversation: Conversation): string {
  const title = conversation.subject ?? conversation.preview ?? "";

  return title.trim() === ""
    ? `Conversation ${conversation.id}`
    : title.slice(0, 500);
}

/**
 * The `tasks.from_conversation` action, which the inbox block's default
 * automation runs on `inbox_conversation.opened`: a task from the conversation,
 * linked `created_from` it.
 */
export function taskFromConversationAction(
  options: TaskFromConversationOptions,
): Action {
  return defineConversionAction<
    TaskFromConversationClients,
    Conversation,
    WorkItemInput
  >({
    kind: "tasks.from_conversation",
    title: "Create a task from the conversation",
    targetType: "task",
    clients: options.clients,
    load: async ({ clients, source }) => {
      const found = await clients.inbox.conversations.get(source.id);

      if (!found.ok) {
        return found;
      }

      return found.data === null
        ? err(dbError("not_found", `No conversation ${source.id}`))
        : ok(found.data);
    },
    input: workItemInputSchema,
    map: (conversation, context) =>
      options.map?.(conversation, context) ?? {
        title: conversationTitle(conversation),
        ...(conversation.preview === null
          ? {}
          : { body: conversation.preview }),
      },
    create: async (input, { call, clients, tenant }) => {
      const assignee = call.context.payload?.["assigneeId"];

      const created = await clients.tasks.create(
        tenant,
        input,
        options.assign !== false && typeof assignee === "string"
          ? [assignee]
          : undefined,
      );

      return created.ok ? ok({ id: created.data.id }) : created;
    },
  });
}

/** The `tasks.from_conversation` factory for the action registry. */
export const taskFromConversationFactory: ActionFactory = ({ clients }) =>
  taskFromConversationAction({
    clients: narrowClients<TaskFromConversationClients>(
      "tasks.from_conversation",
      [
        "relations.link",
        "relations.convertedInto",
        "inbox.conversations.get",
        "tasks.create",
      ],
      clients,
    ),
  });
