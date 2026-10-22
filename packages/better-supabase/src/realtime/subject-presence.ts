import type { StandardSchemaV1 } from "@standard-schema/spec";

import type { SubjectRef } from "../schema/types.ts";
import type { Topic } from "./topic.ts";

import { defineTopic } from "./topic.ts";

/** The presence topic template; the subjects module's policies authorize it. */
export const SUBJECT_PRESENCE_TEMPLATE = "presence:{subjectType}:{subjectId}";

export type SubjectPresenceTopic<R extends boolean | StandardSchemaV1 = true> =
  Topic<typeof SUBJECT_PRESENCE_TEMPLATE, Record<never, never>, R>;

/**
 * The presence topic of a record, `presence:<type>:<id>`: who has it open.
 * Anyone who can read the subject (`can_subject(type, id, 'read')`) joins it,
 * so a channel uses its `conversation` subject, a comment thread its record and
 * a document its own subject. Pass a schema to validate the tracked states.
 *
 * Presence states come from the clients, so show them as hints (a name, an
 * avatar, a cursor) and never decide access on them.
 */
export function subjectPresenceTopic<S extends StandardSchemaV1>(
  schema: S,
): SubjectPresenceTopic<S>;
export function subjectPresenceTopic(): SubjectPresenceTopic;
export function subjectPresenceTopic(
  schema?: StandardSchemaV1,
): SubjectPresenceTopic<boolean | StandardSchemaV1> {
  return defineTopic(SUBJECT_PRESENCE_TEMPLATE, {
    name: "subject_presence",
    presence: schema ?? true,
    tenant: false,
    owner: false,
  });
}

/** `subjectPresenceTopic()` without a schema. */
export const subjectPresence: SubjectPresenceTopic = subjectPresenceTopic();

export interface SubjectPresenceValues {
  readonly subjectType: string;
  readonly subjectId: string;
}

/**
 * The topic values of a subject for `usePresence` and the bindings; `null` (no
 * subject yet) pauses the join.
 *
 * ```tsx
 * const { members } = usePresence(
 *   subjectPresence,
 *   subjectPresenceValues({ type: "conversation", id: conversationId }),
 *   { state: { name, avatarUrl } },
 * );
 * ```
 */
export function subjectPresenceValues(
  subject: SubjectRef | null | undefined,
): SubjectPresenceValues | null {
  return subject ? { subjectType: subject.type, subjectId: subject.id } : null;
}
