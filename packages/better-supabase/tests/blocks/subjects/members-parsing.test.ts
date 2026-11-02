import { describe, expect, it } from "vitest";

import { createSubjects } from "../../../src/blocks/subjects/index.ts";

function setup(results: Readonly<Record<string, unknown>>) {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];

  const { members } = createSubjects({
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
  });

  return { calls, members };
}

const SUBJECT = { type: "patient", id: "p1" };

describe("subjects members parsing defaults", () => {
  it("fills empty defaults when a row has no optional columns", async () => {
    const { members } = setup({ add_subject_member: {} });

    const member = await members
      .add({ subject: SUBJECT, member: { teamId: "t1" } })
      .orThrow();

    expect(member).toEqual({
      id: "",
      organizationId: "",
      subject: { type: "", id: "" },
      role: "",
      emergency: false,
      active: false,
    });
  });

  it("sends a team, the default role and null dates", async () => {
    const { calls, members } = setup({ add_subject_member: {} });

    await members.add({ subject: SUBJECT, member: { teamId: "t1" } }).orThrow();

    expect(calls[0]?.args).toEqual({
      subject_type: "patient",
      subject_id: "p1",
      user_id: null,
      team_id: "t1",
      role: "member",
      starts_on: null,
      ends_on: null,
    });
  });

  it("parses every optional column of a full row", async () => {
    const { members } = setup({
      add_subject_member: {
        id: "m1",
        organizationId: "org",
        subjectType: "patient",
        subjectId: "p1",
        userId: "u1",
        teamId: "t1",
        role: "lead",
        startsOn: "2026-10-01",
        endsOn: "2026-10-31T00:00:00Z",
        endsAt: "2026-10-31T12:00:00+00:00",
        emergency: true,
        reason: "on call",
        active: true,
        createdBy: "u0",
        createdAt: "2026-10-01T08:00:00+00:00",
      },
    });

    const member = await members
      .add({
        subject: SUBJECT,
        member: { userId: "u1", endsOn: Temporal.PlainDate.from("2026-10-31") },
      })
      .orThrow();

    expect(member.userId).toBe("u1");
    expect(member.teamId).toBe("t1");
    expect(member.endsOn?.toString()).toBe("2026-10-31");
    expect(member.endsAt?.toString()).toBe("2026-10-31T12:00:00Z");
    expect(member.emergency).toBe(true);
    expect(member.reason).toBe("on call");
    expect(member.createdBy).toBe("u0");
    expect(member.createdAt).toBeDefined();
  });

  it("sends the end date as an argument only when one is given", async () => {
    const { calls, members } = setup({ end_subject_member: {} });

    await members
      .end({ memberId: "m1", endsOn: Temporal.PlainDate.from("2026-11-01") })
      .orThrow();
    await members.end({ memberId: "m2" }).orThrow();

    expect(calls.map((call) => call.args)).toEqual([
      { member_id: "m1", ends_on: "2026-11-01" },
      { member_id: "m2" },
    ]);
  });

  it("treats a missing list result as an empty team", async () => {
    const { members } = setup({ list_subject_members: null });

    expect(await members.list(SUBJECT).orThrow()).toEqual([]);
  });

  it("skips malformed items and fills defaults when paging mine", async () => {
    const { calls, members } = setup({
      my_subjects: {
        items: [
          "nope",
          { subjectType: "patient" },
          {
            subjectType: "patient",
            subjectId: "p2",
            organizationId: "org",
            roles: ["lead", 3, "nurse"],
            endsOn: "2026-12-01",
            emergency: true,
            title: "Pat",
            url: "/p/2",
          },
          { subjectType: "patient", subjectId: "p3", roles: "x" },
        ],
      },
    });

    const page = await members.mine({ tenant: "org" }).orThrow();

    expect(calls[0]?.args).toEqual({
      tenant: "org",
      subject_type: null,
      page_size: 100,
      cursor: null,
    });
    expect(page.nextCursor).toBeNull();
    expect(page.items).toHaveLength(2);
    expect(page.items[0]).toMatchObject({
      subject: { type: "patient", id: "p2" },
      roles: ["lead", "nurse"],
      emergency: true,
      title: "Pat",
      url: "/p/2",
    });
    expect(page.items[0]?.endsOn?.toString()).toBe("2026-12-01");
    expect(page.items[1]).toEqual({
      subject: { type: "patient", id: "p3" },
      organizationId: "",
      roles: [],
      emergency: false,
    });
  });

  it("returns no items when the page has none", async () => {
    const { members } = setup({ my_subjects: { nextCursor: "c2" } });

    expect(await members.mine({ tenant: "org" }).orThrow()).toEqual({
      items: [],
      nextCursor: "c2",
    });
  });
});
