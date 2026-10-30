import { describe, expect, it } from "vitest";

import { createAcknowledgements } from "../../../src/blocks/acknowledgements/index.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-01T00:00:00Z";
const POLICY = { type: "policy", id: "p1" };

const ASSIGNMENT = {
  id: "a1",
  organizationId: "o",
  subjectType: "policy",
  subjectId: "p1",
  principalType: "role",
  principalId: "member",
  dueInDays: 14,
  createdBy: "u0",
  createdAt: AT,
};

const ACK = {
  id: "k1",
  organizationId: "o",
  subjectType: "policy",
  subjectId: "p1",
  versionId: "v1",
  userId: "u1",
  method: "signature",
  signatureId: "s1",
  acknowledgedAt: AT,
};

describe("acknowledgements client", () => {
  it("assigns, acknowledges and reads who is pending", async () => {
    const fake = fieldsTransport({
      assign_acknowledgement: () => ASSIGNMENT,
      unassign_acknowledgement: () => ({
        ...ASSIGNMENT,
        dueInDays: null,
        createdBy: null,
        createdAt: null,
      }),
      list_acknowledgement_assignments: () => [ASSIGNMENT],
      acknowledge: () => ACK,
      list_my_acknowledgements: () => [
        {
          organizationId: "o",
          subjectType: "policy",
          subjectId: "p1",
          subjectTitle: "Security policy",
          versionId: "v1",
          dueOn: "2026-10-15",
          overdue: false,
          acknowledgedAt: null,
        },
      ],
      acknowledgement_status: () => ({
        versionId: "v1",
        required: 2,
        acknowledged: 1,
        pending: [{ userId: "u2", dueOn: "2026-10-15", overdue: true }],
      }),
      acknowledgements_of: () => [{ ...ACK, method: null, signatureId: null }],
      notify_due_acknowledgements: () => 3,
    });

    const acks = createAcknowledgements({ transport: fake });

    const assigned = await acks
      .assign("o", POLICY, { type: "role", id: "member" }, { dueInDays: 14 })
      .orThrow();

    expect(assigned).toEqual({
      id: "a1",
      organizationId: "o",
      record: POLICY,
      principal: { type: "role", id: "member" },
      dueInDays: 14,
      createdBy: "u0",
      createdAt: Temporal.Instant.from(AT),
    });

    const removed = await acks.unassign("a1").orThrow();
    expect(removed.dueInDays).toBeUndefined();
    expect(removed.createdAt).toBeUndefined();
    expect(await acks.assignments(POLICY).orThrow()).toHaveLength(1);

    const ack = await acks
      .acknowledge(POLICY, { versionId: "v1", signatureId: "s1" })
      .orThrow();

    expect(ack).toMatchObject({
      versionId: "v1",
      method: "signature",
      signatureId: "s1",
    });
    await acks.acknowledge(POLICY);

    const [mine] = await acks.mine("o").orThrow();
    expect(mine?.title).toBe("Security policy");
    expect(mine?.dueOn?.toString()).toBe("2026-10-15");
    expect(mine?.acknowledgedAt).toBeUndefined();
    await acks.mine("o", { pendingOnly: false });

    const status = await acks.status(POLICY).orThrow();
    expect(status.required).toBe(2);
    expect(status.pending[0]?.overdue).toBe(true);

    const [plain] = await acks.of(POLICY, "v1").orThrow();
    expect(plain?.method).toBeUndefined();
    expect(await acks.notifyDue().orThrow()).toBe(3);

    expect(fake.calls).toEqual([
      [
        "assign_acknowledgement",
        {
          tenant: "o",
          subject_type: "policy",
          subject_id: "p1",
          principal_type: "role",
          principal_id: "member",
          due_in_days: 14,
        },
      ],
      ["unassign_acknowledgement", { assignment_id: "a1" }],
      [
        "list_acknowledgement_assignments",
        { subject_type: "policy", subject_id: "p1" },
      ],
      [
        "acknowledge",
        {
          subject_type: "policy",
          subject_id: "p1",
          version_id: "v1",
          signature_id: "s1",
        },
      ],
      [
        "acknowledge",
        {
          subject_type: "policy",
          subject_id: "p1",
          version_id: null,
          signature_id: null,
        },
      ],
      ["list_my_acknowledgements", { tenant: "o", pending_only: true }],
      ["list_my_acknowledgements", { tenant: "o", pending_only: false }],
      ["acknowledgement_status", { subject_type: "policy", subject_id: "p1" }],
      [
        "acknowledgements_of",
        { subject_type: "policy", subject_id: "p1", version_id: "v1" },
      ],
      ["notify_due_acknowledgements", {}],
    ]);
  });

  it("fails on a principal type the database shouldn't return", async () => {
    const acks = createAcknowledgements({
      transport: fieldsTransport({
        list_acknowledgement_assignments: () => [
          { ...ASSIGNMENT, principalType: "group" },
        ],
      }),
    });

    expect((await acks.assignments(POLICY)).ok).toBe(false);
  });
});
