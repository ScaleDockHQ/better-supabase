import type { SubjectEventData } from "./block-events.ts";

/** Events from the parties module: a company, a person, or a link between them. */
export interface PartyEventData {
  readonly organizationId: string;
  readonly companyId?: string;
  readonly personId?: string;
  readonly name?: string;
  /** For `*.merged`: the record merged into this one, now archived. */
  readonly mergedId?: string;
  /** For `company.person_*`: the person's role at the company. */
  readonly role?: string | null;
}

/**
 * Events from the engagements module. `subjectType` and `subjectId` name the
 * engagement's main record; `subjects` lists every record it is on.
 */
export interface EngagementEventData extends SubjectEventData {
  readonly organizationId: string;
  readonly engagementId: string;
  /** `call`, `email`, `meeting`, `note`, `task` or a configured type. */
  readonly type: string;
  readonly subjects: readonly { readonly type: string; readonly id: string }[];
}

/** `mail_account.connected` and `mail_account.disconnected`: a synced mailbox. */
export interface MailAccountEventData {
  readonly organizationId: string;
  readonly accountId: string;
  /** The member whose mailbox it is. */
  readonly userId: string;
  /** `gmail`, `outlook` or a custom provider name. */
  readonly provider: string;
  readonly address: string;
}

/**
 * `mail_message.received` and `mail_message.sent`: a message stored on a
 * thread. `subjects` lists the records the thread is linked to.
 */
export interface MailMessageEventData {
  readonly organizationId: string;
  readonly accountId: string;
  readonly userId: string;
  readonly threadId: string;
  readonly messageId: string;
  readonly direction: "inbound" | "outbound";
  readonly fromAddress: string | null;
  readonly subjects: readonly { readonly type: string; readonly id: string }[];
}

/**
 * `mail_message.opened` (the first open) and `mail_message.clicked` (each
 * click): a tracked message its recipient opened, or a link in it they followed
 * (`url`, null for an open).
 */
export interface MailTrackingEventData {
  readonly organizationId: string;
  readonly accountId: string;
  readonly userId: string;
  readonly threadId: string;
  readonly messageId: string;
  /** The template version the message was sent from, when it had one. */
  readonly templateVersionId: string | null;
  readonly url: string | null;
  readonly subjects: readonly { readonly type: string; readonly id: string }[];
}

/**
 * `segment.saved` and `segment.removed`: a tenant's filter over one subject
 * type.
 */
export interface SegmentEventData {
  readonly organizationId: string;
  readonly segmentId: string;
  readonly subjectType: string;
  readonly name: string;
}

/**
 * `segment.entered` and `segment.left`: a record started or stopped matching a
 * segment's conditions when the segment was refreshed.
 */
export interface SegmentMemberEventData {
  readonly organizationId: string;
  readonly segmentId: string;
  readonly subjectType: string;
  readonly subjectId: string;
}

/** `subject.assigned`: an assignment queue picked an owner for a record. */
export interface AssignmentEventData {
  readonly organizationId: string;
  readonly queueId: string;
  readonly subjectType: string;
  readonly subjectId: string;
  /** The member the queue picked. */
  readonly userId: string;
  readonly strategy: "round_robin" | "weighted";
}

/** `collection.created` and `collection.archived`: a list of one subject type. */
export interface CollectionEventData {
  readonly organizationId: string;
  readonly collectionId: string;
  /** The type of the records the collection holds. */
  readonly subjectType: string;
  readonly name: string;
  /** For `collection.created`: `user`, `team` or `tenant`. */
  readonly scope?: string;
}

/** `collection.entry_added` and `collection.entry_removed`: a record in a list. */
export interface CollectionEntryEventData extends SubjectEventData {
  readonly organizationId: string;
  readonly collectionId: string;
}

/** Events from the deals module. Amounts are minor units as text. */
export interface DealEventData extends SubjectEventData {
  readonly organizationId: string;
  readonly dealId: string;
  readonly name: string;
  readonly amount?: string;
  readonly currency?: string;
  /** For `deal.closed`: `won` or `lost`. */
  readonly outcome?: string;
  /** For `deal.closed` as lost: why. */
  readonly reason?: string | null;
  /** For `deal.updated`: the fields the batch changed. */
  readonly fields?: readonly string[];
}

/** Events from the work-items module. */
export interface WorkItemEventData extends SubjectEventData {
  readonly organizationId: string;
  readonly workItemId: string;
  readonly title: string;
  /** For `work_item.updated`: the fields the batch changed. */
  readonly fields?: readonly string[];
  /** For `work_item.assigned`: everyone assigned now. */
  readonly assigneeIds?: readonly string[];
  /** For `work_item.closed`: `completed` or `canceled`, and why. */
  readonly state?: string;
  readonly closeReason?: string;
}

/** Events from the quotes module. Amounts are minor units as text. */
export interface QuoteEventData extends SubjectEventData {
  readonly organizationId: string;
  readonly quoteId: string;
  readonly identifier: string;
  readonly total?: string;
  readonly currency?: string;
  /** For `quote.accepted`: who accepted, by name. */
  readonly byName?: string;
  /** For `quote.rejected` and `quote.changes_requested`. */
  readonly note?: string | null;
  /** For `quote.revised`: the new revision. */
  readonly revisionId?: string;
}

/** Events from the invoices module. Amounts are minor units as text. */
export interface InvoiceEventData extends SubjectEventData {
  readonly organizationId: string;
  readonly invoiceId: string;
  /** Null while the invoice is a draft. */
  readonly identifier: string | null;
  readonly total?: string;
  readonly currency?: string;
  readonly dueOn?: string;
  readonly paymentId?: string;
  readonly amount?: string;
  readonly balance?: string;
  readonly creditNoteId?: string;
  readonly reason?: string | null;
}

/** Events from the sla module: a clock on a record warned, breached or was met. */
export interface SlaEventData extends SubjectEventData {
  readonly organizationId: string;
  readonly clockId: string;
  /** `first_response`, `next_response` or `resolution`. */
  readonly metric: string;
  readonly dueAt: string;
  /** For `sla.completed`: whether it was met after its due time. */
  readonly late?: boolean;
}

/** Events from the hiring module about a job. */
export interface JobEventData {
  readonly organizationId: string;
  readonly jobId: string;
  readonly title: string;
}

/** Events from the hiring module about an application. */
export interface ApplicationEventData extends SubjectEventData {
  readonly organizationId: string;
  readonly applicationId: string;
  readonly jobId: string;
  /** The candidate's record in config.subjects, a person by default. */
  readonly candidateType: string;
  readonly candidateId: string;
  /** For `application.rejected`. */
  readonly reason?: string | null;
  /** For `scorecard.submitted`. */
  readonly reviewerId?: string;
  readonly recommendation?: string;
  /** For `interview.scheduled`. */
  readonly interviewId?: string;
  readonly startsAt?: string;
}

/** Events from the employees module. */
export interface EmployeeEventData extends SubjectEventData {
  readonly organizationId: string;
  readonly employeeId: string;
  readonly name: string;
  /** For `employee.created`. */
  readonly userId?: string | null;
  readonly managerId?: string | null;
  readonly status?: string;
  /** For `employee.updated`: the fields the batch changed, or `contract`. */
  readonly fields?: readonly string[];
  /** For `employee.offboarded`: the last day and why. */
  readonly endDate?: string;
  readonly reason?: string | null;
  /** For `employee.manager_changed`. */
  readonly fromManagerId?: string | null;
  readonly toManagerId?: string | null;
}

/**
 * Events from the pipelines module. `pipeline.stage_changed` carries the record
 * that moved as `subjectType` and `subjectId`; the configuration events
 * (`pipeline.created`, `pipeline_stage.saved`) carry none.
 */
export interface PipelineEventData {
  readonly organizationId: string;
  readonly pipelineId: string;
  readonly subjectType?: string;
  readonly subjectId?: string;
  readonly key?: string;
  readonly stageId?: string;
  readonly fromStageId?: string | null;
  readonly toStageId?: string;
  /** The stage category, such as `won` or `started`. */
  readonly category?: string;
  /** `open`, `success` or `failure`. */
  readonly outcome?: string;
}

/** `pipeline.stage_changed`: the record that moved and its stages. */
export type PipelineStageEventData = PipelineEventData & SubjectEventData;

/** Events from the messaging module about a conversation. */
export interface ConversationEventData extends SubjectEventData {
  readonly organizationId: string;
  readonly conversationId: string;
  /** `channel`, `dm`, `group_dm`, `subject` or `inbox`. */
  readonly kind: string;
  /** For `conversation.created` of a record conversation: the record. */
  readonly recordType?: string | null;
  readonly recordId?: string | null;
  /** For `conversation.member_added` and `member_removed`. */
  readonly userId?: string;
}

/** Events from the messaging module about a message. */
export interface MessageEventData extends SubjectEventData {
  readonly organizationId: string;
  readonly conversationId: string;
  readonly messageId: string;
  readonly authorId: string | null;
  /** The thread's root message, null for a top-level message. */
  readonly threadId: string | null;
  /** The conversation's kind: `subject` for a record's comments. */
  readonly conversationKind?: string;
  /** The record a `subject` conversation discusses, null otherwise. */
  readonly recordType?: string | null;
  readonly recordId?: string | null;
  /** For `message.sent`: the users it mentions. */
  readonly mentionIds?: readonly string[];
  /** For `message.pinned` and `message.resolved`: the new state. */
  readonly pinned?: boolean;
  readonly resolved?: boolean;
}

/** Events from the channels module. */
export interface ChannelEventData extends SubjectEventData {
  readonly organizationId: string;
  /** The channel's id, which is also its conversation's id. */
  readonly channelId: string;
  readonly name: string;
  /** `public` or `private`. */
  readonly visibility: string;
  /** The record the channel is linked to. */
  readonly recordType: string | null;
  readonly recordId: string | null;
}
