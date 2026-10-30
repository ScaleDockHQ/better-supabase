import { describe, expect, it } from "vitest";

import { createSubjects } from "../../../src/blocks/subjects/index.ts";

const MEMBER = {
  id: "m1",
  organizationId: "org",
  subjectType: "patient",
  subjectId: "p1",
  userId: "u1",
  teamId: null,
  role: "lead",
  startsOn: "2026-10-01",
  endsOn: null,
  emergency: false,
  reason: null,
  active: true,
  createdBy: "u0",
  createdAt: "2026-10-01T08:00:00+00:00",
};

function fakeTransport(results: Readonly<Record<string, unknown>>) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];

  return {
    calls,
    transport: {
      call(
        _schema: string,
        fn: string,
        args: Readonly<Record<string, unknown>>,
      ) {
        calls.push({ fn, args: { ...args } });

        return Promise.resolve(results[fn]);
      },
    },
  };
}

describe("subjects members", () => {
  it("adds a user with dates and reads the row back", async () => {
    const fake = fakeTransport({ add_subject_member: MEMBER });
    const { members } = createSubjects({ transport: fake.transport });

    const member = await members
      .add(
        { type: "patient", id: "p1" },
        {
          userId: "u1",
          role: "lead",
          startsOn: Temporal.PlainDate.from("2026-10-01"),
        },
      )
      .orThrow();

    expect(fake.calls).toEqual([
      {
        fn: "add_subject_member",
        args: {
          subject_type: "patient",
          subject_id: "p1",
          user_id: "u1",
          team_id: null,
          role: "lead",
          starts_on: "2026-10-01",
          ends_on: null,
        },
      },
    ]);
    expect(member.subject).toEqual({ type: "patient", id: "p1" });
    expect(member.startsOn?.toString()).toBe("2026-10-01");
    expect(member.endsOn).toBeUndefined();
    expect(member.teamId).toBeUndefined();
    expect(member.active).toBe(true);
  });

  it("ends a membership on a given day, or today without one", async () => {
    const fake = fakeTransport({
      end_subject_member: { ...MEMBER, endsOn: "2026-10-28", active: false },
    });

    const { members } = createSubjects({ transport: fake.transport });

    const ended = await members
      .end("m1", { endsOn: Temporal.PlainDate.from("2026-10-28") })
      .orThrow();

    await members.end("m1").orThrow();

    expect(ended.endsOn?.toString()).toBe("2026-10-28");
    expect(fake.calls.map((call) => call.args)).toEqual([
      { member_id: "m1", ends_on: "2026-10-28" },
      { member_id: "m1" },
    ]);
  });

  it("lists a record's team", async () => {
    const fake = fakeTransport({ list_subject_members: [MEMBER] });
    const { members } = createSubjects({ transport: fake.transport });

    const list = await members.list({ type: "patient", id: "p1" }).orThrow();

    expect(list.map((member) => member.id)).toEqual(["m1"]);
  });

  it("pages the caller's records with a cursor", async () => {
    const fake = fakeTransport({
      my_subjects: {
        items: [
          {
            subjectType: "patient",
            subjectId: "p1",
            organizationId: "org",
            roles: ["lead"],
            endsOn: null,
            emergency: false,
            title: "Ada",
            url: null,
          },
          { subjectType: "patient" },
        ],
        nextCursor: "patient:p1",
      },
    });

    const { members } = createSubjects({ transport: fake.transport });

    const page = await members
      .mine("org", { subjectType: "patient", limit: 1 })
      .orThrow();

    expect(fake.calls[0]?.args).toEqual({
      tenant: "org",
      subject_type: "patient",
      page_size: 1,
      cursor: null,
    });
    expect(page).toEqual({
      items: [
        {
          subject: { type: "patient", id: "p1" },
          organizationId: "org",
          roles: ["lead"],
          emergency: false,
          title: "Ada",
        },
      ],
      nextCursor: "patient:p1",
    });
  });
});
