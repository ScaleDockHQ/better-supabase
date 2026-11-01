import * as v from "valibot";
import { describe, expect, it } from "vitest";

import {
  createQualifications,
  qualificationGrantInputSchema,
  qualificationsBlock,
  qualificationTypeInputSchema,
} from "../../../src/blocks/qualifications/index.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-22T10:00:00Z";
const ID = "00000000-0000-4000-8000-000000000001";

const TYPE = {
  id: "t1",
  organizationId: "org-1",
  key: "forklift",
  name: "Forklift licence",
  description: "Counterbalance trucks",
  holderTypes: ["member"],
  validForMonths: 12,
  evidenceRequired: true,
  courseId: "c1",
  archivedAt: null,
  createdAt: AT,
  updatedAt: AT,
};

const BARE_TYPE = {
  id: "t2",
  organizationId: "org-1",
  key: "insurance",
  name: "Liability insurance",
  holderTypes: ["company", "asset"],
  validForMonths: null,
  evidenceRequired: false,
};

const REQUIREMENT = {
  id: "r1",
  organizationId: "org-1",
  qualificationTypeId: "t1",
  targetType: "role",
  targetValue: "member",
  createdAt: AT,
};

const HOLDING = {
  id: "q1",
  organizationId: "org-1",
  qualificationTypeId: "t1",
  typeKey: "forklift",
  typeName: "Forklift licence",
  holderType: "member",
  holderId: "u1",
  grantedOn: "2026-01-10",
  expiresOn: "2027-01-10",
  revokedAt: null,
  evidenceAttachmentId: "a1",
  evidenceNote: "Card scanned",
  source: "manual",
  sourceId: null,
  grantedBy: "u2",
  status: "valid",
  createdAt: AT,
  updatedAt: AT,
  fields: { licence: "FL-1" },
};

const BARE_HOLDING = {
  id: "q2",
  organizationId: "org-1",
  qualificationTypeId: "t2",
  typeKey: "insurance",
  typeName: "Liability insurance",
  holderType: "company",
  holderId: "co1",
  grantedOn: "2026-01-10",
  source: "course",
  sourceId: "cert-1",
  revokedAt: AT,
  revokeReason: "Policy lapsed",
  status: "revoked",
};

const GAP = {
  holderType: "member",
  holderId: "u1",
  holderTitle: "Ada Lovelace",
  typeKey: "forklift",
  typeName: "Forklift licence",
  status: "expiring",
  expiresOn: "2026-11-01",
};

const Fields = v.object({ licence: v.optional(v.string()) });

const validate = (
  schema: { "~standard": { validate: (value: unknown) => unknown } },
  value: unknown,
) => schema["~standard"].validate(value) as { issues?: unknown[] };

describe("createQualifications", () => {
  it("saves, lists and archives qualification types", async () => {
    const t = fieldsTransport({
      save_qualification_type: () => TYPE,
      list_qualification_types: () => [TYPE, BARE_TYPE],
      archive_qualification_type: () => ({ ...TYPE, archivedAt: AT }),
    });

    const qualifications = createQualifications({ transport: t });

    const saved = await qualifications
      .saveType({
        organizationId: "org-1",
        input: {
          key: "forklift",
          name: "Forklift licence",
          holderTypes: ["member"],
          validForMonths: 12,
          evidenceRequired: true,
          courseId: "c1",
          description: "Counterbalance trucks",
          typeId: "t1",
        },
      })
      .orThrow();

    await qualifications
      .saveType({
        organizationId: "org-1",
        input: {
          key: "insurance",
          name: "Liability insurance",
          holderTypes: ["company"],
        },
      })
      .orThrow();

    const [, bare] = await qualifications
      .types({ organizationId: "org-1", includeArchived: true })
      .orThrow();

    const archived = await qualifications.archiveType("t1").orThrow();

    expect(saved).toMatchObject({
      validForMonths: 12,
      evidenceRequired: true,
      courseId: "c1",
    });
    expect(saved.createdAt?.toString()).toBe(AT);
    expect(bare?.holderTypes).toEqual(["company", "asset"]);
    expect(Object.keys(bare ?? {}).toSorted()).toEqual([
      "evidenceRequired",
      "holderTypes",
      "id",
      "key",
      "name",
      "organizationId",
    ]);
    expect(archived.archivedAt?.toString()).toBe(AT);
    expect(t.calls).toEqual([
      [
        "save_qualification_type",
        {
          tenant: "org-1",
          key: "forklift",
          name: "Forklift licence",
          holder_types: ["member"],
          valid_for_months: 12,
          evidence_required: true,
          course_id: "c1",
          description: "Counterbalance trucks",
          type_id: "t1",
        },
      ],
      [
        "save_qualification_type",
        {
          tenant: "org-1",
          key: "insurance",
          name: "Liability insurance",
          holder_types: ["company"],
          valid_for_months: null,
          evidence_required: false,
          course_id: null,
          description: null,
          type_id: null,
        },
      ],
      ["list_qualification_types", { tenant: "org-1", include_archived: true }],
      ["archive_qualification_type", { type_id: "t1" }],
    ]);
  });

  it("adds, lists and removes requirements", async () => {
    const t = fieldsTransport({
      add_qualification_requirement: () => REQUIREMENT,
      list_qualification_requirements: () => [REQUIREMENT],
      remove_qualification_requirement: () => REQUIREMENT,
    });

    const qualifications = createQualifications({ transport: t });

    const added = await qualifications
      .addRequirement({
        typeId: "t1",
        targetType: "role",
        targetValue: "member",
      })
      .orThrow();

    const listed = await qualifications.requirements("t1").orThrow();
    await qualifications.removeRequirement("r1").orThrow();

    expect(added).toMatchObject({ targetType: "role", targetValue: "member" });
    expect(listed).toHaveLength(1);
    expect(t.calls).toEqual([
      [
        "add_qualification_requirement",
        { type_id: "t1", target_type: "role", target_value: "member" },
      ],
      ["list_qualification_requirements", { type_id: "t1" }],
      ["remove_qualification_requirement", { requirement_id: "r1" }],
    ]);
  });

  it("grants with extra fields, checks them, and revokes", async () => {
    const t = fieldsTransport({
      grant_qualification: () => HOLDING,
      revoke_qualification: () => BARE_HOLDING,
    });

    const qualifications = createQualifications({
      transport: t,
      fields: Fields,
    });

    const granted = await qualifications
      .grant({
        organizationId: "org-1",
        input: {
          typeKey: "forklift",
          holderType: "member",
          holderId: "u1",
          grantedOn: Temporal.PlainDate.from("2026-01-10"),
          evidenceAttachmentId: "a1",
          evidenceNote: "Card scanned",
          fields: { licence: "FL-1" },
        },
      })
      .orThrow();

    await qualifications
      .grant({
        organizationId: "org-1",
        input: { typeKey: "insurance", holderType: "company", holderId: "co1" },
      })
      .orThrow();

    const refused = await qualifications.grant({
      organizationId: "org-1",
      input: {
        typeKey: "forklift",
        holderType: "member",
        holderId: "u1",
        // SAFETY: a value the schema refuses, to prove the client checks it.
        fields: { licence: 1 } as unknown as { licence: string },
      },
    });

    const revoked = await qualifications
      .revoke({ qualificationId: "q2", reason: "Policy lapsed" })
      .orThrow();

    await qualifications.revoke({ qualificationId: "q2" }).orThrow();

    expect(granted.fields.licence).toBe("FL-1");
    expect(granted.expiresOn?.toString()).toBe("2027-01-10");
    expect(granted).toMatchObject({ status: "valid", grantedBy: "u2" });
    expect(refused.ok ? undefined : refused.error.kind).toBe("validation");
    expect(revoked).toMatchObject({
      status: "revoked",
      source: "course",
      sourceId: "cert-1",
      revokeReason: "Policy lapsed",
    });
    expect(t.calls).toEqual([
      [
        "grant_qualification",
        {
          tenant: "org-1",
          type_key: "forklift",
          holder_type: "member",
          holder_id: "u1",
          granted_on: "2026-01-10",
          evidence_attachment_id: "a1",
          evidence_note: "Card scanned",
          fields: { licence: "FL-1" },
        },
      ],
      [
        "grant_qualification",
        {
          tenant: "org-1",
          type_key: "insurance",
          holder_type: "company",
          holder_id: "co1",
          evidence_attachment_id: null,
          evidence_note: null,
        },
      ],
      [
        "revoke_qualification",
        { qualification_id: "q2", reason: "Policy lapsed" },
      ],
      ["revoke_qualification", { qualification_id: "q2", reason: null }],
    ]);
  });

  it("reads holdings, gaps and qualified holders", async () => {
    const t = fieldsTransport({
      qualifications_of: () => [HOLDING, BARE_HOLDING],
      qualification_gaps: () => [GAP, { ...GAP, status: "missing" }],
      qualified_holders: () => ["u1", "u2"],
      notify_expiring_qualifications: () => "3",
    });

    const qualifications = createQualifications({ transport: t });

    const held = await qualifications
      .of({ holderType: "member", holderId: "u1" })
      .orThrow();

    const gaps = await qualifications
      .gaps({
        organizationId: "org-1",
        holderType: "member",
        holderId: "u1",
        teamId: "team-1",
        typeKey: "forklift",
        status: "expiring",
      })
      .orThrow();

    await qualifications.gaps({ organizationId: "org-1" }).orThrow();

    const holders = await qualifications
      .qualifiedHolders({
        organizationId: "org-1",
        typeKey: "forklift",
        holderType: "member",
        on: Temporal.PlainDate.from("2026-12-01"),
      })
      .orThrow();

    await qualifications
      .qualifiedHolders({ organizationId: "org-1", typeKey: "forklift" })
      .orThrow();
    const notified = await qualifications.notifyExpiring().orThrow();

    expect(held.map((row) => row.status)).toEqual(["valid", "revoked"]);
    expect(gaps[0]?.expiresOn?.toString()).toBe("2026-11-01");
    expect(Object.keys(gaps[1] ?? {})).toContain("holderTitle");
    expect(holders).toEqual(["u1", "u2"]);
    expect(notified).toBe(3);
    expect(t.calls).toEqual([
      ["qualifications_of", { holder_type: "member", holder_id: "u1" }],
      [
        "qualification_gaps",
        {
          tenant: "org-1",
          holder_type: "member",
          filters: {
            holderId: "u1",
            teamId: "team-1",
            typeKey: "forklift",
            status: "expiring",
          },
        },
      ],
      [
        "qualification_gaps",
        { tenant: "org-1", holder_type: "member", filters: {} },
      ],
      [
        "qualified_holders",
        {
          tenant: "org-1",
          type_key: "forklift",
          holder_type: "member",
          on_date: "2026-12-01",
        },
      ],
      [
        "qualified_holders",
        { tenant: "org-1", type_key: "forklift", holder_type: "member" },
      ],
      ["notify_expiring_qualifications", {}],
    ]);
  });

  it("rejects malformed rows and stored fields the schema refuses", async () => {
    const t = fieldsTransport({
      qualifications_of: () => [{ ...HOLDING, status: "green" }],
      qualification_gaps: () => [{ ...GAP, status: "valid" }],
      list_qualification_types: () => [{ ...TYPE, holderTypes: ["robot"] }],
      revoke_qualification: () => ({ ...HOLDING, fields: { licence: 1 } }),
    });

    const qualifications = createQualifications({
      transport: t,
      fields: Fields,
    });

    expect(
      (await qualifications.of({ holderType: "member", holderId: "u1" })).ok,
    ).toBe(false);
    expect((await qualifications.gaps({ organizationId: "org-1" })).ok).toBe(
      false,
    );
    expect((await qualifications.types({ organizationId: "org-1" })).ok).toBe(
      false,
    );
    expect((await qualifications.revoke({ qualificationId: "q1" })).ok).toBe(
      false,
    );
  });

  it("runs the hooks", async () => {
    const seen: string[] = [];

    const qualifications = createQualifications({
      transport: fieldsTransport({ notify_expiring_qualifications: () => 0 }),
      hooks: {
        notifyExpiring: {
          after: () => {
            seen.push("notifyExpiring");
          },
        },
      },
    });

    await qualifications.notifyExpiring().orThrow();

    expect(seen).toEqual(["notifyExpiring"]);
  });
});

describe("qualifications block", () => {
  it("names the block and validates the inputs", () => {
    expect(qualificationsBlock.name).toBe("qualifications");
    expect(
      validate(qualificationTypeInputSchema, {
        key: "forklift",
        name: "Forklift licence",
        holderTypes: ["member"],
      }).issues,
    ).toBeUndefined();
    expect(
      validate(qualificationTypeInputSchema, {
        key: "forklift",
        name: "Forklift licence",
        holderTypes: ["robot"],
      }).issues,
    ).toBeDefined();
    expect(
      validate(qualificationTypeInputSchema, {
        key: "forklift",
        name: "Forklift licence",
        holderTypes: ["member"],
        validForMonths: 241,
      }).issues,
    ).toBeDefined();
    expect(
      validate(qualificationGrantInputSchema, {
        typeKey: "forklift",
        holderType: "member",
        holderId: ID,
        grantedOn: Temporal.PlainDate.from("2026-01-10"),
      }).issues,
    ).toBeUndefined();
    expect(
      validate(qualificationGrantInputSchema, {
        typeKey: "forklift",
        holderType: "member",
        holderId: ID,
        grantedOn: "soon",
      }).issues,
    ).toBeDefined();
  });
});
