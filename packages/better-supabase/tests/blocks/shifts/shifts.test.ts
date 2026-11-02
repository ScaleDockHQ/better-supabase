import * as v from "valibot";
import { describe, expect, it } from "vitest";

import {
  createShifts,
  shiftAvailabilityInputSchema,
  shiftInputSchema,
  shiftsBlock,
  shiftTemplateInputSchema,
} from "../../../src/blocks/shifts/index.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-22T10:00:00Z";
const START = "2026-11-02T06:00:00Z";
const END = "2026-11-02T14:00:00Z";

const TEMPLATE = {
  id: "t1",
  organizationId: "org-1",
  name: "Early",
  teamId: "team-1",
  locationId: "loc-1",
  startsTime: "06:00",
  endsTime: "14:00",
  breakMinutes: 30,
  headcount: 2,
  requiredQualifications: ["first_aid"],
  weekdays: [1, 2, 3, 4, 5],
  archivedAt: null,
  createdAt: AT,
  updatedAt: AT,
};

const SHIFT = {
  id: "s1",
  organizationId: "org-1",
  templateId: "t1",
  teamId: "team-1",
  locationId: null,
  startsAt: START,
  endsAt: END,
  breakMinutes: 30,
  headcount: 2,
  requiredQualifications: [],
  status: "published",
  note: "Bring keys",
  publishedAt: AT,
  canceledAt: null,
  createdBy: "u9",
  createdAt: AT,
  updatedAt: AT,
  fields: { station: "A" },
};

const BARE_SHIFT = {
  id: "s2",
  organizationId: "org-1",
  startsAt: START,
  endsAt: END,
  breakMinutes: "0",
  headcount: null,
  status: "draft",
};

const ASSIGNMENT = {
  id: "a1",
  organizationId: "org-1",
  shiftId: "s1",
  userId: "u1",
  status: "assigned",
  startsAt: START,
  endsAt: END,
  assignedBy: "u9",
  createdAt: AT,
  updatedAt: AT,
};

const SWAP = {
  id: "w1",
  organizationId: "org-1",
  assignmentId: "a1",
  fromUserId: "u1",
  toUserId: "u2",
  status: "approved",
  approvalId: "ap1",
  note: "Dentist",
  decidedBy: "u9",
  decidedAt: AT,
  createdAt: AT,
};

const AVAILABILITY = {
  id: "v1",
  organizationId: "org-1",
  userId: "u1",
  onDate: "2026-11-02",
  fromTime: "08:00",
  untilTime: "12:00",
  kind: "unavailable",
  note: "School run",
  createdAt: AT,
};

const Fields = v.object({ station: v.optional(v.string()) });

const validate = (
  schema: { "~standard": { validate: (value: unknown) => unknown } },
  value: unknown,
) => schema["~standard"].validate(value) as { issues?: unknown[] };

const day = (value: string): Temporal.PlainDate =>
  Temporal.PlainDate.from(value);

describe("createShifts", () => {
  it("saves, lists and archives templates and generates shifts", async () => {
    const t = fieldsTransport({
      save_shift_template: () => TEMPLATE,
      archive_shift_template: () => ({ ...TEMPLATE, archivedAt: AT }),
      list_shift_templates: () => [
        TEMPLATE,
        { ...TEMPLATE, id: "t2", teamId: null, weekdays: null },
      ],
      generate_shifts: () => [SHIFT, BARE_SHIFT],
    });

    const shifts = createShifts({ transport: t, fields: Fields });

    const saved = await shifts
      .saveTemplate({
        organizationId: "org-1",
        input: {
          name: "Early",
          startsTime: "06:00",
          endsTime: "14:00",
          weekdays: [1, 2, 3, 4, 5],
          teamId: "team-1",
          locationId: "loc-1",
          breakMinutes: 30,
          headcount: 2,
          requiredQualifications: ["first_aid"],
          templateId: "t1",
        },
      })
      .orThrow();

    await shifts
      .saveTemplate({
        organizationId: "org-1",
        input: { name: "Late", startsTime: "14:00", endsTime: "22:00" },
      })
      .orThrow();

    const archived = await shifts.archiveTemplate("t1").orThrow();

    const [, bare] = await shifts
      .templates({ organizationId: "org-1" })
      .orThrow();

    await shifts
      .templates({ organizationId: "org-1", includeArchived: true })
      .orThrow();

    const generated = await shifts
      .generate({
        organizationId: "org-1",
        templateId: "t1",
        from: day("2026-11-02"),
        until: day("2026-11-06"),
      })
      .orThrow();

    expect(saved).toMatchObject({
      weekdays: [1, 2, 3, 4, 5],
      requiredQualifications: ["first_aid"],
      locationId: "loc-1",
    });
    expect(archived.archivedAt?.toString()).toBe(AT);
    expect(bare?.teamId).toBeUndefined();
    expect(bare?.weekdays).toEqual([]);
    expect(generated[0]?.fields.station).toBe("A");
    expect(generated[1]).toMatchObject({
      breakMinutes: 0,
      headcount: 0,
      requiredQualifications: [],
      fields: {},
    });
    expect(generated[1]?.startsAt.toString()).toBe(START);
    expect(t.calls).toEqual([
      [
        "save_shift_template",
        {
          tenant: "org-1",
          name: "Early",
          starts_time: "06:00",
          ends_time: "14:00",
          weekdays: [1, 2, 3, 4, 5],
          team_id: "team-1",
          location_id: "loc-1",
          break_minutes: 30,
          headcount: 2,
          required_qualifications: ["first_aid"],
          template_id: "t1",
        },
      ],
      [
        "save_shift_template",
        {
          tenant: "org-1",
          name: "Late",
          starts_time: "14:00",
          ends_time: "22:00",
          team_id: null,
          location_id: null,
          break_minutes: 0,
          headcount: 1,
          required_qualifications: [],
          template_id: null,
        },
      ],
      ["archive_shift_template", { template_id: "t1" }],
      ["list_shift_templates", { tenant: "org-1", include_archived: false }],
      ["list_shift_templates", { tenant: "org-1", include_archived: true }],
      [
        "generate_shifts",
        {
          tenant: "org-1",
          template_id: "t1",
          from_date: "2026-11-02",
          until_date: "2026-11-06",
        },
      ],
    ]);
  });

  it("upserts with extra fields, cancels and publishes shifts", async () => {
    const t = fieldsTransport({
      save_shift: () => SHIFT,
      cancel_shift: () => ({ ...SHIFT, status: "canceled", canceledAt: AT }),
      publish_shifts: () => 4,
    });

    const shifts = createShifts({ transport: t, fields: Fields });

    const saved = await shifts
      .upsert({
        organizationId: "org-1",
        input: {
          startsAt: Temporal.Instant.from(START),
          endsAt: Temporal.Instant.from(END),
          teamId: "team-1",
          locationId: "loc-1",
          breakMinutes: 30,
          headcount: 2,
          requiredQualifications: ["first_aid"],
          note: "Bring keys",
          shiftId: "s1",
          fields: { station: "A" },
        },
      })
      .orThrow();

    await shifts
      .upsert({
        organizationId: "org-1",
        input: {
          startsAt: Temporal.Instant.from(START),
          endsAt: Temporal.Instant.from(END),
        },
      })
      .orThrow();

    const refused = await shifts.upsert({
      organizationId: "org-1",
      input: {
        startsAt: Temporal.Instant.from(START),
        endsAt: Temporal.Instant.from(END),
        // SAFETY: a value the schema refuses, to prove the client checks it.
        fields: { station: 1 } as unknown as { station: string },
      },
    });

    const canceled = await shifts
      .cancel({ shiftId: "s1", reason: "Storm" })
      .orThrow();

    await shifts.cancel({ shiftId: "s1" }).orThrow();

    const published = await shifts
      .publish({
        organizationId: "org-1",
        from: day("2026-11-02"),
        until: day("2026-11-08"),
        teamId: "team-1",
      })
      .orThrow();

    await shifts
      .publish({
        organizationId: "org-1",
        from: day("2026-11-02"),
        until: day("2026-11-08"),
      })
      .orThrow();

    expect(saved).toMatchObject({ status: "published", note: "Bring keys" });
    expect(saved.publishedAt?.toString()).toBe(AT);
    expect(refused.ok ? undefined : refused.error.kind).toBe("validation");
    expect(canceled.status).toBe("canceled");
    expect(published).toBe(4);
    expect(t.calls).toEqual([
      [
        "save_shift",
        {
          tenant: "org-1",
          starts_at: START,
          ends_at: END,
          team_id: "team-1",
          location_id: "loc-1",
          break_minutes: 30,
          headcount: 2,
          required_qualifications: ["first_aid"],
          note: "Bring keys",
          shift_id: "s1",
          fields: { station: "A" },
        },
      ],
      [
        "save_shift",
        {
          tenant: "org-1",
          starts_at: START,
          ends_at: END,
          team_id: null,
          location_id: null,
          break_minutes: 0,
          headcount: 1,
          required_qualifications: [],
          note: null,
          shift_id: null,
        },
      ],
      ["cancel_shift", { shift_id: "s1", reason: "Storm" }],
      ["cancel_shift", { shift_id: "s1", reason: null }],
      [
        "publish_shifts",
        {
          tenant: "org-1",
          from_date: "2026-11-02",
          until_date: "2026-11-08",
          team_id: "team-1",
        },
      ],
      [
        "publish_shifts",
        {
          tenant: "org-1",
          from_date: "2026-11-02",
          until_date: "2026-11-08",
          team_id: null,
        },
      ],
    ]);
  });

  it("assigns, requests and swaps", async () => {
    const t = fieldsTransport({
      assign_shift: () => ({
        ...ASSIGNMENT,
        warnings: [
          { code: "SHIFT_ASSIGNMENT_UNQUALIFIED", qualification: "first_aid" },
          "odd",
        ],
      }),
      unassign_shift: () => ({ ...ASSIGNMENT, status: "released" }),
      request_open_shift: () => ({
        id: "a2",
        organizationId: "org-1",
        shiftId: "s1",
        userId: "u2",
        status: "requested",
        startsAt: START,
        endsAt: END,
      }),
      decide_shift_request: () => ASSIGNMENT,
      request_shift_swap: () => ({
        ...SWAP,
        status: "pending",
        approvalId: null,
        decidedBy: null,
        decidedAt: null,
      }),
      decide_shift_swap: () => SWAP,
    });

    const shifts = createShifts({ transport: t });

    const assigned = await shifts
      .assign({ shiftId: "s1", userId: "u1" })
      .orThrow();

    const released = await shifts
      .unassign({ assignmentId: "a1", reason: "Sick" })
      .orThrow();

    await shifts.unassign({ assignmentId: "a1" }).orThrow();
    const requested = await shifts.requestOpenShift("s1").orThrow();

    const decided = await shifts
      .decideRequest({ assignmentId: "a2", approve: true })
      .orThrow();

    const swap = await shifts
      .requestSwap({ assignmentId: "a1", toUserId: "u2", note: "Dentist" })
      .orThrow();

    await shifts.requestSwap({ assignmentId: "a1", toUserId: "u2" }).orThrow();

    const approved = await shifts
      .decideSwap({ swapId: "w1", approve: true, approvalId: "ap1" })
      .orThrow();

    await shifts.decideSwap({ swapId: "w1", approve: false }).orThrow();

    expect(assigned.warnings).toEqual([
      { code: "SHIFT_ASSIGNMENT_UNQUALIFIED", qualification: "first_aid" },
    ]);
    expect(released.status).toBe("released");
    expect(requested).not.toHaveProperty("assignedBy");
    expect(decided.warnings).toBeUndefined();
    expect(swap).toMatchObject({ status: "pending", note: "Dentist" });
    expect(swap).not.toHaveProperty("decidedAt");
    expect(approved.decidedAt?.toString()).toBe(AT);
    expect(t.calls).toEqual([
      ["assign_shift", { shift_id: "s1", user_id: "u1" }],
      ["unassign_shift", { assignment_id: "a1", reason: "Sick" }],
      ["unassign_shift", { assignment_id: "a1", reason: null }],
      ["request_open_shift", { shift_id: "s1" }],
      ["decide_shift_request", { assignment_id: "a2", approve: true }],
      [
        "request_shift_swap",
        { assignment_id: "a1", to_user_id: "u2", note: "Dentist" },
      ],
      [
        "request_shift_swap",
        { assignment_id: "a1", to_user_id: "u2", note: null },
      ],
      [
        "decide_shift_swap",
        { swap_id: "w1", approve: true, approval_id: "ap1" },
      ],
      [
        "decide_shift_swap",
        { swap_id: "w1", approve: false, approval_id: null },
      ],
    ]);
  });

  it("sets, clears and lists availability", async () => {
    const t = fieldsTransport({
      set_shift_availability: (args) =>
        args["kind"] === null
          ? null
          : { ...AVAILABILITY, fromTime: null, untilTime: null, note: null },
      list_shift_availability: () => [AVAILABILITY],
    });

    const shifts = createShifts({ transport: t });

    const set = await shifts
      .setAvailability({
        organizationId: "org-1",
        input: {
          onDate: day("2026-11-02"),
          kind: "unavailable",
          fromTime: "08:00",
          untilTime: "12:00",
          note: "School run",
          userId: "u1",
        },
      })
      .orThrow();

    await shifts
      .setAvailability({
        organizationId: "org-1",
        input: { onDate: day("2026-11-03"), kind: "preferred" },
      })
      .orThrow();

    const cleared = await shifts.clearAvailability({
      organizationId: "org-1",
      onDate: day("2026-11-02"),
      userId: "u1",
    });

    await shifts
      .clearAvailability({ organizationId: "org-1", onDate: day("2026-11-03") })
      .orThrow();

    const listed = await shifts
      .availability({
        organizationId: "org-1",
        from: day("2026-11-01"),
        until: day("2026-11-07"),
        userId: "u1",
      })
      .orThrow();

    await shifts
      .availability({
        organizationId: "org-1",
        from: day("2026-11-01"),
        until: day("2026-11-07"),
      })
      .orThrow();

    expect(set).not.toHaveProperty("fromTime");
    expect(cleared.ok).toBe(true);
    expect(listed[0]?.onDate.toString()).toBe("2026-11-02");
    expect(listed[0]).toMatchObject({ fromTime: "08:00", kind: "unavailable" });
    expect(t.calls).toEqual([
      [
        "set_shift_availability",
        {
          tenant: "org-1",
          on_date: "2026-11-02",
          kind: "unavailable",
          from_time: "08:00",
          until_time: "12:00",
          note: "School run",
          user_id: "u1",
        },
      ],
      [
        "set_shift_availability",
        {
          tenant: "org-1",
          on_date: "2026-11-03",
          kind: "preferred",
          from_time: null,
          until_time: null,
          note: null,
          user_id: null,
        },
      ],
      [
        "set_shift_availability",
        { tenant: "org-1", on_date: "2026-11-02", kind: null, user_id: "u1" },
      ],
      [
        "set_shift_availability",
        { tenant: "org-1", on_date: "2026-11-03", kind: null, user_id: null },
      ],
      [
        "list_shift_availability",
        {
          tenant: "org-1",
          from_date: "2026-11-01",
          until_date: "2026-11-07",
          user_id: "u1",
        },
      ],
      [
        "list_shift_availability",
        {
          tenant: "org-1",
          from_date: "2026-11-01",
          until_date: "2026-11-07",
          user_id: null,
        },
      ],
    ]);
  });

  it("reads the roster, my shifts and hours, and books time entries", async () => {
    const t = fieldsTransport({
      roster: () => [
        { ...SHIFT, assignments: [ASSIGNMENT] },
        { ...BARE_SHIFT, assignments: null },
      ],
      my_shifts: () => [{ ...SHIFT, assignment: ASSIGNMENT }],
      shift_hours: () => [
        {
          userId: "u1",
          shifts: 5,
          plannedHours: 37.5,
          contractHours: 40,
          differenceHours: -2.5,
        },
        { userId: "u2", shifts: "1", plannedHours: "8" },
      ],
      shifts_to_time_entries: () => "3",
    });

    const shifts = createShifts({ transport: t, fields: Fields });

    const roster = await shifts
      .roster({
        organizationId: "org-1",
        from: day("2026-11-02"),
        until: day("2026-11-08"),
        teamId: "team-1",
      })
      .orThrow();

    await shifts
      .roster({
        organizationId: "org-1",
        from: day("2026-11-02"),
        until: day("2026-11-08"),
      })
      .orThrow();

    const mine = await shifts
      .myShifts({
        since: Temporal.Instant.from(AT),
        until: Temporal.Instant.from(END),
      })
      .orThrow();

    await shifts.myShifts().orThrow();

    const hours = await shifts
      .hours({ organizationId: "org-1", weekStart: day("2026-11-02") })
      .orThrow();

    const booked = await shifts
      .toTimeEntries({
        organizationId: "org-1",
        until: Temporal.Instant.from(AT),
      })
      .orThrow();

    await shifts.toTimeEntries({ organizationId: "org-1" }).orThrow();

    expect(roster[0]?.assignments).toHaveLength(1);
    expect(roster[0]?.fields.station).toBe("A");
    expect(roster[1]?.assignments).toEqual([]);
    expect(mine[0]?.assignment.userId).toBe("u1");
    expect(hours).toEqual([
      {
        userId: "u1",
        shifts: 5,
        plannedHours: 37.5,
        contractHours: 40,
        differenceHours: -2.5,
      },
      { userId: "u2", shifts: 1, plannedHours: 8 },
    ]);
    expect(booked).toBe(3);
    expect(t.calls).toEqual([
      [
        "roster",
        {
          tenant: "org-1",
          from_date: "2026-11-02",
          until_date: "2026-11-08",
          team_id: "team-1",
        },
      ],
      [
        "roster",
        {
          tenant: "org-1",
          from_date: "2026-11-02",
          until_date: "2026-11-08",
          team_id: null,
        },
      ],
      ["my_shifts", { since: AT, until: END }],
      ["my_shifts", {}],
      ["shift_hours", { tenant: "org-1", week_start: "2026-11-02" }],
      ["shifts_to_time_entries", { tenant: "org-1", until: AT }],
      ["shifts_to_time_entries", { tenant: "org-1" }],
    ]);
  });

  it("rejects malformed rows and stored fields the schema refuses", async () => {
    const t = fieldsTransport({
      generate_shifts: () => [{ ...SHIFT, status: "open" }],
      assign_shift: () => ({ ...ASSIGNMENT, status: "maybe" }),
      decide_shift_swap: () => ({ ...SWAP, status: "later" }),
      list_shift_availability: () => [{ ...AVAILABILITY, kind: "busy" }],
      cancel_shift: () => ({ ...SHIFT, fields: { station: 1 } }),
      roster: () => "nope",
    });

    const shifts = createShifts({ transport: t, fields: Fields });

    expect(
      (
        await shifts.generate({
          organizationId: "org-1",
          templateId: "t1",
          from: day("2026-11-02"),
          until: day("2026-11-03"),
        })
      ).ok,
    ).toBe(false);
    expect((await shifts.assign({ shiftId: "s1", userId: "u1" })).ok).toBe(
      false,
    );
    expect((await shifts.decideSwap({ swapId: "w1", approve: true })).ok).toBe(
      false,
    );
    expect(
      (
        await shifts.availability({
          organizationId: "org-1",
          from: day("2026-11-02"),
          until: day("2026-11-03"),
        })
      ).ok,
    ).toBe(false);
    expect((await shifts.cancel({ shiftId: "s1" })).ok).toBe(false);
    expect(
      (
        await shifts.roster({
          organizationId: "org-1",
          from: day("2026-11-02"),
          until: day("2026-11-03"),
        })
      ).ok,
    ).toBe(false);
  });
});

describe("shift input schemas", () => {
  it("validate the inputs and convert to JSON Schema", () => {
    expect(
      validate(shiftTemplateInputSchema, {
        name: "Early",
        startsTime: "06:00",
        endsTime: "14:00",
        weekdays: [1, 7],
      }).issues,
    ).toBeUndefined();
    expect(
      validate(shiftTemplateInputSchema, {
        name: "Early",
        startsTime: "06:00",
        endsTime: "14:00",
        weekdays: [8],
      }).issues,
    ).toBeDefined();
    expect(
      validate(shiftInputSchema, {
        startsAt: Temporal.Instant.from(START),
        endsAt: Temporal.Instant.from(END),
      }).issues,
    ).toBeUndefined();
    expect(
      validate(shiftAvailabilityInputSchema, {
        onDate: "2026-11-02",
        kind: "busy",
      }).issues,
    ).toBeDefined();
  });
});

describe("shiftsBlock", () => {
  it("names its module, schemas and recipe", () => {
    expect(shiftsBlock.name).toBe("shifts");
    expect(shiftsBlock.sql).toEqual(["shifts"]);
    expect(Object.keys(shiftsBlock.schemas)).toEqual([
      "shift",
      "shift_template",
      "shift_availability",
    ]);
    expect(shiftsBlock.recipes).toEqual(["roster-board"]);
  });
});
