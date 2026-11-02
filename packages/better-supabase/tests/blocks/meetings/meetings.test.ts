import * as v from "valibot";
import { describe, expect, it } from "vitest";

import {
  createMeetings,
  meetingDecisionInputSchema,
  meetingInputSchema,
  meetingsBlock,
} from "../../../src/blocks/meetings/index.ts";
import { temporal } from "../../../src/core/temporal-required.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-29T10:00:00Z";

const MEETING = {
  id: "m1",
  organizationId: "org-1",
  kind: "board",
  title: "Quarterly board",
  location: "Room 1",
  startsAt: AT,
  status: "planned",
  createdAt: AT,
  updatedAt: AT,
};

const DECISION = {
  id: "d1",
  organizationId: "org-1",
  meetingId: "m1",
  title: "Approve the budget",
  status: "proposed",
  createdAt: AT,
};

const Fields = v.object({ room_code: v.optional(v.string()) });

const validate = (
  schema: { "~standard": { validate: (value: unknown) => unknown } },
  value: unknown,
) => schema["~standard"].validate(value) as { issues?: unknown[] };

describe("createMeetings", () => {
  it("creates, starts and holds a meeting", async () => {
    const t = fieldsTransport({
      create_meeting: () => MEETING,
      start_meeting: () => ({ ...MEETING, status: "in_progress" }),
      hold_meeting: () => ({ ...MEETING, status: "held", summary: "Done" }),
    });

    const meetings = createMeetings({ transport: t, tenant: "org-1" });

    const created = await meetings
      .create({
        title: "Quarterly board",
        startsAt: temporal().Instant.from(AT),
        attendees: [{ userId: "u1", role: "chair" }],
      })
      .orThrow();

    const started = await meetings.start("m1").orThrow();

    const held = await meetings
      .hold({ meetingId: "m1", summary: "Done" })
      .orThrow();

    expect(created.startsAt.toString()).toBe("2026-10-29T10:00:00Z");
    expect(created.endsAt).toBeUndefined();
    expect(started.status).toBe("in_progress");
    expect(held).toMatchObject({ status: "held", summary: "Done" });
    expect(t.calls).toEqual([
      [
        "create_meeting",
        {
          tenant: "org-1",
          input: {
            title: "Quarterly board",
            startsAt: "2026-10-29T10:00:00Z",
            attendees: [{ userId: "u1", role: "chair" }],
          },
        },
      ],
      ["start_meeting", { meeting_id: "m1" }],
      ["hold_meeting", { meeting_id: "m1", summary: "Done" }],
    ]);
  });

  it("validates, sends and parses custom fields", async () => {
    const t = fieldsTransport({
      create_meeting: () => ({ ...MEETING, fields: { room_code: "B-12" } }),
      update_meeting: () => ({ ...MEETING, fields: { room_code: "C-3" } }),
      get_meeting: () => ({ ...MEETING, fields: { room_code: 7 } }),
      list_meetings: () => [{ ...MEETING, fields: { room_code: "B-12" } }],
    });

    const meetings = createMeetings({
      transport: t,
      tenant: "org-1",
      fields: Fields,
    });

    const created = await meetings
      .create({
        title: "Quarterly board",
        startsAt: temporal().Instant.from(AT),
        fields: { room_code: "B-12" },
      })
      .orThrow();

    const updated = await meetings
      .update({ meetingId: "m1", change: { fields: { room_code: "C-3" } } })
      .orThrow();

    const refused = await meetings.update({
      meetingId: "m1",
      change: {
        // SAFETY: a value the schema refuses, to prove the client checks it.
        fields: { room_code: 1 } as unknown as { room_code: string },
      },
    });

    const listed = await meetings.list().orThrow();

    expect(created.fields.room_code).toBe("B-12");
    expect(updated.fields.room_code).toBe("C-3");
    expect(refused.ok).toBe(false);
    expect(listed[0]?.fields.room_code).toBe("B-12");
    expect((await meetings.get("m1")).ok).toBe(false);
    expect(t.calls[0]).toEqual([
      "create_meeting",
      {
        tenant: "org-1",
        input: {
          title: "Quarterly board",
          startsAt: "2026-10-29T10:00:00Z",
          fields: { room_code: "B-12" },
        },
      },
    ]);
    expect(t.calls[1]).toEqual([
      "update_meeting",
      { meeting_id: "m1", changes: { fields: { room_code: "C-3" } } },
    ]);
    expect(t.calls.filter(([fn]) => fn === "update_meeting")).toHaveLength(1);
  });

  it("records a decision and lets the votes decide it", async () => {
    const t = fieldsTransport({
      record_meeting_decision: () => DECISION,
      decide_meeting_decision: () => ({
        ...DECISION,
        status: "passed",
        decidedAt: AT,
      }),
    });

    const meetings = createMeetings({ transport: t, tenant: "org-1" });

    await meetings
      .recordDecision({
        meetingId: "m1",
        input: { title: "Approve the budget" },
      })
      .orThrow();
    const passed = await meetings.decide({ decisionId: "d1" }).orThrow();

    expect(passed.status).toBe("passed");
    expect(passed.decidedAt?.toString()).toBe("2026-10-29T10:00:00Z");
    expect(t.calls[1]).toEqual([
      "decide_meeting_decision",
      { decision_id: "d1", status: null },
    ]);
  });

  it("reads a meeting with its agenda, decision votes and action items", async () => {
    const t = fieldsTransport({
      get_meeting: () => ({
        ...MEETING,
        attendees: [{ userId: "u1", role: "chair", attendance: "present" }],
        agenda: [
          {
            id: "a1",
            meetingId: "m1",
            ordinal: 1,
            title: "Budget",
            minutes: "Discussed",
            status: "covered",
          },
        ],
        decisions: [
          { ...DECISION, votes: { score: 1, up: 2, down: 1, vote: 1 } },
        ],
        actionItems: [
          { workItemId: "t1", title: "Send the budget", state: "open" },
        ],
      }),
    });

    const meetings = createMeetings({ transport: t, tenant: "org-1" });

    const detail = await meetings.get("m1").orThrow();

    expect(detail.attendees[0]).toEqual({
      userId: "u1",
      role: "chair",
      attendance: "present",
    });
    expect(detail.agenda[0]).toMatchObject({
      ordinal: 1,
      minutes: "Discussed",
    });
    expect(detail.decisions[0]?.votes).toEqual({
      score: 1,
      up: 2,
      down: 1,
      vote: 1,
    });
    expect(detail.actionItems[0]?.workItemId).toBe("t1");
  });

  it("opens an action item as a task", async () => {
    const t = fieldsTransport({
      add_meeting_action_item: () => ({ id: "t1", title: "Send it" }),
      list_meetings: () => [MEETING],
    });

    const meetings = createMeetings({ transport: t, tenant: "org-1" });

    await meetings
      .addActionItem({
        meetingId: "m1",
        input: {
          task: { title: "Send it" },
          assignees: ["u2"],
          decisionId: "d1",
        },
      })
      .orThrow();

    const listed = await meetings
      .list({ status: "planned", limit: 10 })
      .orThrow();

    expect(listed).toHaveLength(1);
    expect(t.calls).toEqual([
      [
        "add_meeting_action_item",
        {
          meeting_id: "m1",
          task: { title: "Send it" },
          assignees: ["u2"],
          agenda_item_id: null,
          decision_id: "d1",
        },
      ],
      [
        "list_meetings",
        { tenant: "org-1", filters: { status: "planned", limit: 10 } },
      ],
    ]);
  });

  it("passes the optional arguments through", async () => {
    const t = fieldsTransport({
      update_meeting: () => MEETING,
      cancel_meeting: () => ({ ...MEETING, status: "cancelled" }),
      set_meeting_attendee: () => ({
        userId: "u1",
        role: "guest",
        attendance: "absent",
      }),
      decide_meeting_decision: () => ({ ...DECISION, status: "rejected" }),
      add_meeting_action_item: () => ({ id: "t2", title: "Call" }),
    });

    const meetings = createMeetings({ transport: t, tenant: "org-1" });

    await meetings
      .update({
        meetingId: "m1",
        change: {
          title: "Moved",
          endsAt: temporal().Instant.from(AT),
          location: null,
        },
      })
      .orThrow();
    await meetings.cancel({ meetingId: "m1", reason: "No quorum" }).orThrow();
    await meetings
      .setAttendee({
        meetingId: "m1",
        userId: "u1",
        attendee: { role: "guest", attendance: "absent" },
      })
      .orThrow();
    await meetings.decide({ decisionId: "d1", status: "rejected" }).orThrow();
    await meetings
      .addActionItem({
        meetingId: "m1",
        input: { task: { title: "Call" }, agendaItemId: "a1" },
      })
      .orThrow();

    expect(t.calls.map(([name]) => name)).toEqual([
      "update_meeting",
      "cancel_meeting",
      "set_meeting_attendee",
      "decide_meeting_decision",
      "add_meeting_action_item",
    ]);
    expect(t.calls[1]?.[1]).toEqual({ meeting_id: "m1", reason: "No quorum" });
    expect(t.calls[3]?.[1]).toEqual({ decision_id: "d1", status: "rejected" });
  });

  it("returns an error result for an unknown status", async () => {
    const t = fieldsTransport({
      start_meeting: () => ({ ...MEETING, status: "adjourned" }),
    });

    const meetings = createMeetings({ transport: t, tenant: "org-1" });

    const result = await meetings.start("m1");

    expect(result.ok).toBe(false);
  });
});

describe("meetings schemas", () => {
  it("validates the inputs", () => {
    expect(
      validate(meetingInputSchema, {
        title: "Board",
        startsAt: temporal().Instant.from(AT),
      }).issues,
    ).toBeUndefined();
    expect(validate(meetingInputSchema, { startsAt: AT }).issues).toBeDefined();
    expect(
      validate(meetingDecisionInputSchema, {
        title: "Approve",
        status: "maybe",
      }).issues,
    ).toBeDefined();
  });

  it("declares its schemas and events on the manifest", () => {
    expect(meetingsBlock.name).toBe("meetings");
    expect(Object.keys(meetingsBlock.schemas)).toContain("meeting");
  });
});
