import { describe, expect, it } from "vitest";

import {
  subjectAccessPlan,
  subjectAccessRequest,
} from "../../../src/blocks/data-lifecycle/index.ts";
import { BLOCK_MANIFESTS } from "../../../src/blocks/registry.ts";

const blocks = [
  {
    name: "notes",
    entities: {
      note: {
        mutability: "editable",
        personalData: ["author", "body"],
        subjectColumn: "authorId",
      },
      log: {
        mutability: "append-only",
        personalData: ["actor"],
        subjectColumn: "actorId",
        erase: "anonymize",
        retention: "audit",
        legalHold: true,
      },
      invoice: {
        mutability: "state-machine",
        personalData: ["name"],
        subjectColumn: "customerId",
        erase: "keep",
      },
      plain: { mutability: "editable" },
    },
  },
  {
    name: "broken",
    entities: {
      trail: {
        mutability: "append-only",
        personalData: ["who"],
        subjectColumn: "whoId",
      },
      loose: { mutability: "editable", personalData: ["email"] },
    },
  },
] as const;

describe("subjectAccessPlan", () => {
  it("collects the entities that declare personal data", () => {
    const plan = subjectAccessPlan(blocks);

    expect(
      plan.access.map((step) => `${step.block}.${step.entity}`),
    ).toStrictEqual(["notes.note", "notes.log", "notes.invoice"]);
  });

  it("groups the erasure by what it does to the rows", () => {
    const { erasure } = subjectAccessPlan(blocks);

    expect(erasure.delete.map((step) => step.entity)).toStrictEqual(["note"]);
    expect(erasure.anonymize.map((step) => step.entity)).toStrictEqual(["log"]);
    expect(erasure.keep.map((step) => step.entity)).toStrictEqual(["invoice"]);
  });

  it("carries the retention class and the legal hold", () => {
    const log = subjectAccessPlan(blocks).access.find(
      (step) => step.entity === "log",
    );

    expect(log).toMatchObject({ retention: "audit", legalHold: true });
  });

  it("reports an append-only delete and a missing subject column as gaps", () => {
    expect(subjectAccessPlan(blocks).gaps).toStrictEqual([
      { block: "broken", entity: "trail", reason: "append-only-delete" },
      { block: "broken", entity: "loose", reason: "no-subject-column" },
    ]);
  });

  it("limits the plan to the named blocks", () => {
    expect(
      subjectAccessPlan(blocks, { blocks: ["broken"] }).access,
    ).toStrictEqual([]);
  });

  it("has no gaps across the shipped manifests", () => {
    const plan = subjectAccessPlan(BLOCK_MANIFESTS);

    expect(plan.gaps).toStrictEqual([]);
    expect(plan.erasure.delete.map((step) => step.entity)).not.toContain(
      "field_history",
    );
    expect(plan.erasure.anonymize.map((step) => step.entity)).toContain(
      "field_history",
    );
  });
});

describe("subjectAccessRequest", () => {
  it("opens the request and lists the planned entities in its details", async () => {
    const seen: Record<string, unknown>[] = [];

    const lifecycle = {
      openDataSubjectRequest(request: Record<string, unknown>) {
        seen.push(request);

        return Promise.resolve({ ok: true, data: { id: "r1" } });
      },
    };

    const result = await subjectAccessRequest(lifecycle as never, {
      organizationId: "org-1",
      kind: "erasure",
      requester: "ada@example.com",
      subject: { type: "contact", id: "c1" },
      blocks,
      details: "Please erase.",
    });

    expect(result.ok).toBe(true);
    expect(seen[0]?.["details"]).toBe(
      "Please erase.\nCovers: notes.note, notes.log, notes.invoice",
    );
  });
});
