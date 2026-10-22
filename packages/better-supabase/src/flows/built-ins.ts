import type {
  Engagement,
  EngagementInput,
  EngagementSubject,
} from "../blocks/activities/activities.ts";
import type { Employee, EmployeeInput } from "../blocks/employees/employees.ts";
import type { Conversation } from "../blocks/inbox/types.ts";
import type { WorkItem, WorkItemInput } from "../blocks/tasks/tasks.ts";
import type {
  ApplicationEventData,
  InboxEventData,
  QuoteEventData,
  SchedulingEventData,
} from "../core/block-events.ts";
import type { Result } from "../core/result.ts";
import type { Flow, FlowClients, FlowContext } from "./flow.ts";

import { workItemInputSchema } from "../blocks/tasks/schemas.ts";
import { dbError } from "../core/errors.ts";
import { err, ok } from "../core/result.ts";
import { defineFlow } from "./flow.ts";

type Created = PromiseLike<Result<{ readonly id: string }>>;

/** The subject types a built-in reads and writes, when the app renamed them. */
export interface BuiltInFlowOptions {
  /** The event that starts the flow. */
  readonly on?: string;
  /** The subject type of the record the event is about. */
  readonly sourceType?: string;
  /** The subject type the flow creates. */
  readonly targetType?: string;
}

/** `blocks.inbox` and `blocks.workItems`, for `conversationToWorkItem`. */
export interface ConversationToWorkItemClients extends FlowClients {
  readonly inbox: {
    readonly conversations: {
      get(conversationId: string): PromiseLike<Result<Conversation | null>>;
    };
  };
  readonly workItems: {
    create(
      organizationId: string,
      input: WorkItemInput,
      assigneeIds?: readonly string[],
    ): PromiseLike<Result<WorkItem>>;
  };
}

export interface ConversationToWorkItemOptions extends BuiltInFlowOptions {
  /**
   * The work item for a conversation. Default: its subject or preview as the
   * title.
   */
  readonly map?: (
    conversation: Conversation,
    context: FlowContext<ConversationToWorkItemClients, InboxEventData>,
  ) => WorkItemInput;
  /** Assigns the work item to the conversation's assignee. Default: true. */
  readonly assign?: boolean;
}

function conversationTitle(conversation: Conversation): string {
  const title = conversation.subject ?? conversation.preview ?? "";

  return title.trim() === ""
    ? `Conversation ${conversation.id}`
    : title.slice(0, 500);
}

/**
 * A work item for each conversation the inbox opens, linked `created_from` the
 * conversation. The mapped input passes the work item input schema.
 */
export function conversationToWorkItem(
  options: ConversationToWorkItemOptions = {},
): Flow<
  ConversationToWorkItemClients,
  InboxEventData,
  Conversation,
  WorkItemInput
> {
  return defineFlow({
    name: "conversationToWorkItem",
    on: options.on ?? "inbox_conversation.opened",
    target: options.targetType ?? "work_item",
    source: (event) => ({
      type: options.sourceType ?? "inbox_conversation",
      id: event.payload.conversationId,
    }),
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
    create: (input, { clients, tenant, event }) =>
      thenId(
        clients.workItems.create(
          tenant,
          input,
          options.assign !== false &&
            typeof event.payload.assigneeId === "string"
            ? [event.payload.assigneeId]
            : undefined,
        ),
      ),
  });
}

/** `blocks.employees`, for `applicationToEmployee`. */
export interface ApplicationToEmployeeClients extends FlowClients {
  readonly employees: {
    fromApplication(
      applicationId: string,
      overrides?: Partial<EmployeeInput>,
    ): PromiseLike<Result<Employee>>;
  };
}

export interface ApplicationToEmployeeOptions extends BuiltInFlowOptions {
  /** Overrides what the employee takes from the candidate and the job. */
  readonly map?: (
    context: FlowContext<ApplicationToEmployeeClients, ApplicationEventData>,
  ) => Partial<EmployeeInput>;
}

/**
 * An employee in preboarding for each hired application, through
 * `employees.fromApplication`, which records the `created_from` link itself.
 */
export function applicationToEmployee(
  options: ApplicationToEmployeeOptions = {},
): Flow<
  ApplicationToEmployeeClients,
  ApplicationEventData,
  undefined,
  Partial<EmployeeInput>
> {
  return defineFlow({
    name: "applicationToEmployee",
    on: options.on ?? "application.hired",
    target: options.targetType ?? "employee",
    source: (event) => ({
      type: options.sourceType ?? "application",
      id: event.payload.applicationId,
    }),
    map: (_, context) => options.map?.(context) ?? {},
    create: (overrides, { clients, source }) =>
      thenId(clients.employees.fromApplication(source.id, overrides)),
    linksItself: true,
  });
}

/** `blocks.activities`, for `bookingToEngagement`. */
export interface BookingToEngagementClients extends FlowClients {
  readonly engagements: {
    log(
      organizationId: string,
      input: EngagementInput & {
        readonly type: string;
        readonly title: string;
      },
      subjects: readonly EngagementSubject[],
    ): PromiseLike<Result<Engagement>>;
  };
}

/** The engagement `bookingToEngagement` logs. */
export type BookingEngagementInput = EngagementInput & {
  readonly type: string;
  readonly title: string;
};

export interface BookingToEngagementOptions extends BuiltInFlowOptions {
  /**
   * The engagement for a booking. Default: a `meeting` titled after the
   * booking.
   */
  readonly map?: (
    context: FlowContext<BookingToEngagementClients, SchedulingEventData>,
  ) => BookingEngagementInput;
  /**
   * The records the engagement is on besides the booking, such as the customer
   * who booked.
   */
  readonly subjects?: (
    context: FlowContext<BookingToEngagementClients, SchedulingEventData>,
  ) => readonly EngagementSubject[];
}

/**
 * A meeting engagement for each confirmed booking, on the booking. It logs with
 * `externalRef: booking:<id>`, so a second log updates the same engagement.
 */
export function bookingToEngagement(
  options: BookingToEngagementOptions = {},
): Flow<
  BookingToEngagementClients,
  SchedulingEventData,
  undefined,
  BookingEngagementInput
> {
  return defineFlow({
    name: "bookingToEngagement",
    on: options.on ?? "booking.confirmed",
    target: options.targetType ?? "engagement",
    source: (event) =>
      typeof event.payload.id === "string"
        ? { type: options.sourceType ?? "booking", id: event.payload.id }
        : undefined,
    map: (_, context) =>
      options.map?.(context) ?? {
        type: "meeting",
        title: context.event.payload.name ?? "Booking",
        externalRef: `booking:${context.source.id}`,
      },
    create: (input, context) =>
      thenId(
        context.clients.engagements.log(context.tenant, input, [
          context.source,
          ...(options.subjects?.(context) ?? []),
        ]),
      ),
  });
}

export interface QuoteToOrderOptions extends BuiltInFlowOptions {
  /**
   * Creates the order for an accepted quote and returns its id, such as a cart
   * of the quote's variants and `orders.checkout`. The orders block has no
   * conversion from a quote, so the app supplies it.
   */
  readonly create: (
    context: FlowContext<FlowClients, QuoteEventData>,
  ) => Created;
}

/**
 * An order for each accepted quote, linked `created_from` the quote, so the
 * quote's lineage shows the order and an accepted quote orders once.
 */
export function quoteToOrder(
  options: QuoteToOrderOptions,
): Flow<FlowClients, QuoteEventData, undefined, undefined> {
  return defineFlow({
    name: "quoteToOrder",
    on: options.on ?? "quote.accepted",
    target: options.targetType ?? "order",
    source: (event) => ({
      type: options.sourceType ?? "quote",
      id: event.payload.quoteId,
    }),
    map: () => undefined,
    create: (_, context) => options.create(context),
  });
}

async function thenId(
  created: PromiseLike<Result<{ readonly id: string }>>,
): Promise<Result<{ readonly id: string }>> {
  const result = await created;

  return result.ok ? ok({ id: result.data.id }) : result;
}
