import type { EntitySchema } from "../entity-schema.ts";
import type {
  MeetingAgendaItemInput,
  MeetingDecisionInput,
  MeetingInput,
} from "./meetings.ts";

import { entitySchema } from "../entity-schema.ts";

/** What `create` takes, with the bounds the SQL checks. */
export const meetingInputSchema: EntitySchema<MeetingInput> =
  entitySchema<MeetingInput>({
    title: "MeetingInput",
    fields: {
      kind: {
        kind: "string",
        optional: true,
        minLength: 1,
        maxLength: 63,
        description: "One of `options.kinds`. Default: the first one.",
      },
      title: { kind: "string", minLength: 1, maxLength: 300 },
      location: {
        kind: "string",
        optional: true,
        nullable: true,
        maxLength: 500,
      },
      startsAt: { kind: "instant" },
      endsAt: {
        kind: "instant",
        optional: true,
        nullable: true,
        description: "On or after startsAt.",
      },
      attendees: {
        kind: "json",
        array: true,
        optional: true,
        description: "The invited users: `{ userId, role, attendance }`.",
      },
      agenda: {
        kind: "json",
        array: true,
        optional: true,
        description: "The agenda, in order: `{ title, notes, presenterId }`.",
      },
    },
  });

/** What `saveAgendaItem` takes. */
export const meetingAgendaItemInputSchema: EntitySchema<MeetingAgendaItemInput> =
  entitySchema<MeetingAgendaItemInput>({
    title: "MeetingAgendaItemInput",
    fields: {
      id: { kind: "uuid", optional: true },
      title: { kind: "string", optional: true, minLength: 1, maxLength: 300 },
      notes: {
        kind: "string",
        optional: true,
        nullable: true,
        maxLength: 10_000,
      },
      presenterId: { kind: "uuid", optional: true, nullable: true },
      minutes: {
        kind: "string",
        optional: true,
        nullable: true,
        maxLength: 50_000,
      },
      status: {
        kind: "enum",
        optional: true,
        values: ["open", "covered", "skipped"],
      },
      outcome: {
        kind: "string",
        optional: true,
        nullable: true,
        maxLength: 2000,
      },
      ordinal: { kind: "integer", optional: true, minimum: 1 },
    },
  });

/** What `recordDecision` takes. */
export const meetingDecisionInputSchema: EntitySchema<MeetingDecisionInput> =
  entitySchema<MeetingDecisionInput>({
    title: "MeetingDecisionInput",
    fields: {
      title: { kind: "string", minLength: 1, maxLength: 300 },
      body: {
        kind: "string",
        optional: true,
        nullable: true,
        maxLength: 10_000,
      },
      agendaItemId: { kind: "uuid", optional: true, nullable: true },
      status: {
        kind: "enum",
        optional: true,
        values: ["proposed", "passed", "rejected", "deferred"],
      },
    },
  });
