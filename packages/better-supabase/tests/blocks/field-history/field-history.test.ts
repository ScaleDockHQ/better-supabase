import { describe, expect, it } from "vitest";

import {
  createFieldHistory,
  fieldHistoryBlock,
} from "../../../src/blocks/field-history/index.ts";
import { fakeTransport } from "../inbox/fixtures.ts";

const AT = "2026-01-01T00:00:00Z";

const change = (extra: Record<string, unknown> = {}) => ({
  id: "12",
  organizationId: "org",
  subjectType: "deal",
  subjectId: "d1",
  field: "amount",
  before: 1000,
  after: 2000,
  changedBy: "u1",
  changedAt: AT,
  ...extra,
});

describe("createFieldHistory", () => {
  it("reads a record's changes", async () => {
    const { transport, call } = fakeTransport({
      field_history: [
        change(),
        change({ id: "11", before: undefined, after: null, changedBy: null }),
      ],
    });

    const changes = await createFieldHistory({ transport })
      .of({ subject: { type: "deal", id: "d1" } })
      .orThrow();

    expect(call).toHaveBeenCalledWith("better_supabase", "field_history", {
      subject_type: "deal",
      subject_id: "d1",
      field: null,
      before: null,
      max_count: null,
    });
    expect(changes[0]).toMatchObject({
      id: "12",
      field: "amount",
      before: 1000,
      after: 2000,
      changedBy: "u1",
    });
    expect(changes[0]?.changedAt.toString()).toBe(AT);
    expect(changes[1]).toMatchObject({
      before: null,
      after: null,
      changedBy: undefined,
    });
  });

  it("pages through one field", async () => {
    const { transport, call } = fakeTransport({ field_history: [] });
    const logger = { debug() {}, info() {}, warn() {}, error() {} };

    await createFieldHistory({ transport, logger })
      .of({
        subject: { type: "deal", id: "d1" },
        field: "stage_id",
        before: "12",
        limit: 10,
      })
      .orThrow();

    expect(call.mock.lastCall?.[2]).toEqual({
      subject_type: "deal",
      subject_id: "d1",
      field: "stage_id",
      before: "12",
      max_count: 10,
    });
  });

  it("is the field-history block", () => {
    expect(fieldHistoryBlock.name).toBe("field-history");
    expect(fieldHistoryBlock.sql).toEqual(["field-history"]);
  });
});
