import { describe, expect, it } from "vitest";

import { createAcknowledgements } from "../../../src/blocks/acknowledgements/index.ts";

const RECORD = { type: "compliance_policy", id: "p1" };
const PRINCIPAL = { type: "role" as const, id: "member" };

function fakeTransport(results: Record<string, unknown>) {
  const calls: [string, unknown][] = [];

  return {
    calls,
    call(schema: string, fn: string, args?: unknown) {
      expect(schema).toBe("app");
      calls.push([fn, args]);

      return Promise.resolve(results[fn]);
    },
  };
}

const ASSIGNMENT = {
  id: "a1",
  organizationId: "org",
  subjectType: "compliance_policy",
  subjectId: "p1",
  principalType: "role",
  principalId: "member",
  dueInDays: 14,
  dueOn: "2026-11-12",
  createdBy: "u1",
  createdAt: "2026-10-29T00:00:00Z",
};

describe("createAcknowledgements", () => {
  it("assigns, acknowledges and lists", async () => {
    const transport = fakeTransport({
      assign_acknowledgement: ASSIGNMENT,
      unassign_acknowledgement: ASSIGNMENT,
      list_acknowledgement_assignments: [ASSIGNMENT],
      acknowledge: {
        id: "k1",
        organizationId: "org",
        subjectType: "compliance_policy",
        subjectId: "p1",
        versionId: "v1",
        userId: "u1",
        method: "click",
        acknowledgedAt: "2026-10-29T00:00:00Z",
      },
      list_my_acknowledgements: [
        {
          subjectType: "compliance_policy",
          subjectId: "p1",
          assignmentId: "a1",
          versionId: "v1",
          dueOn: "2026-11-12",
          overdue: false,
          acknowledgedAt: "2026-10-29T00:00:00Z",
        },
      ],
      acknowledgement_status: {
        versionId: "v1",
        required: 1,
        acknowledged: 1,
        pending: [],
      },
      acknowledgements_of: [],
      notify_due_acknowledgements: 2,
    });

    const client = createAcknowledgements({ transport, schema: "app" });

    expect(
      await client.assign("org", RECORD, PRINCIPAL, { dueInDays: 14 }).orThrow(),
    ).toMatchObject({ id: "a1", principal: PRINCIPAL, dueInDays: 14 });
    expect((await client.unassign("a1").orThrow()).id).toBe("a1");
    expect(await client.assignments(RECORD).orThrow()).toHaveLength(1);
    expect(
      (await client.acknowledge(RECORD, { versionId: "v1" }).orThrow()).method,
    ).toBe("click");
    expect(await client.mine("org").orThrow()).toHaveLength(1);
    expect((await client.status(RECORD).orThrow()).required).toBe(1);
    expect(await client.of(RECORD).orThrow()).toEqual([]);
    expect(await client.notifyDue().orThrow()).toBe(2);

    expect(transport.calls).toContainEqual([
      "assign_acknowledgement",
      {
        tenant: "org",
        subject_type: "compliance_policy",
        subject_id: "p1",
        principal_type: "role",
        principal_id: "member",
        due_in_days: 14,
      },
    ]);
  });

  it("rejects a malformed assignment", async () => {
    const transport = fakeTransport({
      assign_acknowledgement: { ...ASSIGNMENT, principalType: "everyone" },
    });

    const client = createAcknowledgements({ transport, schema: "app" });

    const result = await client.assign("org", RECORD, PRINCIPAL);

    expect(result.ok).toBe(false);
  });

  it("checks the manifest and the input schema", async () => {
    const { acknowledgementsBlock } = await import(
      "../../../src/blocks/acknowledgements/manifest.ts"
    );

    const { acknowledgementAssignmentInputSchema } = await import(
      "../../../src/blocks/acknowledgements/schemas.ts"
    );

    expect(acknowledgementsBlock.name).toBe("acknowledgements");

    expect(
      (await acknowledgementAssignmentInputSchema["~standard"].validate({
        dueInDays: 14,
      })).issues,
    ).toBeUndefined();
    expect(
      (await acknowledgementAssignmentInputSchema["~standard"].validate({
        dueInDays: 0,
      })).issues?.length,
    ).toBe(1);
  });
});
