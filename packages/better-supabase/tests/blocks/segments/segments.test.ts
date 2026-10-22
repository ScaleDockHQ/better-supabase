import { describe, expect, it, vi } from "vitest";

import {
  createSegments,
  segmentInputSchema,
  segmentsBlock,
} from "../../../src/blocks/segments/index.ts";
import { fakeTransport } from "../inbox/fixtures.ts";

const AT = "2026-01-01T00:00:00Z";

const conditions = {
  id: "root",
  type: "group",
  combinator: "and",
  rules: [
    {
      id: "r1",
      type: "rule",
      path: ["industry"],
      operator: "eq",
      value: "saas",
    },
  ],
};

const segmentRow = {
  id: "s1",
  organizationId: "org",
  name: "SaaS",
  description: null,
  subjectType: "company",
  conditions,
  memberCount: 3,
  refreshedAt: null,
  createdBy: "u1",
  createdAt: AT,
  updatedAt: AT,
};

const answers = {
  save_segment: segmentRow,
  remove_segment: true,
  segments_list: [segmentRow],
  segment_get: { ...segmentRow, refreshedAt: AT, description: "Software" },
  list_segment_members: [{ subjectId: "c1", enteredAt: AT }],
  segments_of: [{ id: "s1", name: "SaaS", enteredAt: AT }],
  refresh_segment: { entered: 2, left: 1, memberCount: 3 },
  refresh_due_segments: { segments: 4, entered: 5, left: 6 },
};

describe("createSegments", () => {
  it("saves, reads and refreshes segments", async () => {
    const { transport, call } = fakeTransport(answers);
    const segments = createSegments({ transport });

    const saved = await segments
      .save("org", { subjectType: "company", name: "SaaS", conditions })
      .orThrow();

    expect(saved).toMatchObject({
      id: "s1",
      organizationId: "org",
      description: undefined,
      memberCount: 3,
      refreshedAt: undefined,
      createdBy: "u1",
    });
    expect(saved.conditions).toEqual(conditions);
    expect(call).toHaveBeenCalledWith("better_supabase", "save_segment", {
      tenant: "org",
      segment: { subjectType: "company", name: "SaaS", conditions },
    });

    expect(await segments.remove("s1").orThrow()).toBe(true);
    expect(await segments.list("org").orThrow()).toHaveLength(1);
    expect(call).toHaveBeenLastCalledWith("better_supabase", "segments_list", {
      tenant: "org",
      subject_type: null,
    });
    await segments.list("org", { subjectType: "company" }).orThrow();
    expect(call).toHaveBeenLastCalledWith("better_supabase", "segments_list", {
      tenant: "org",
      subject_type: "company",
    });

    const got = await segments.get("s1").orThrow();

    expect(got?.description).toBe("Software");
    expect(got?.refreshedAt?.toString()).toBe(AT);

    const members = await segments.members("s1").orThrow();

    expect(members).toEqual([
      { subjectId: "c1", enteredAt: Temporal.Instant.from(AT) },
    ]);
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "list_segment_members",
      { segment: "s1", after: null, max_count: null },
    );
    await segments
      .members("s1", { after: Temporal.Instant.from(AT), limit: 10 })
      .orThrow();
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "list_segment_members",
      { segment: "s1", after: AT, max_count: 10 },
    );

    expect(await segments.of({ type: "company", id: "c1" }).orThrow()).toEqual([
      { segmentId: "s1", name: "SaaS", enteredAt: Temporal.Instant.from(AT) },
    ]);
    expect(await segments.refresh("s1").orThrow()).toEqual({
      entered: 2,
      left: 1,
      memberCount: 3,
    });

    expect(await segments.refreshDue().orThrow()).toEqual({
      segments: 4,
      entered: 5,
      left: 6,
    });
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "refresh_due_segments",
      { max_count: null, stale_after: null },
    );
    await segments
      .refreshDue({ segments: 2, staleAfter: "5 minutes" })
      .orThrow();
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "refresh_due_segments",
      { max_count: 2, stale_after: "5 minutes" },
    );
  });

  it("returns undefined for a missing segment", async () => {
    const { transport } = fakeTransport({ segment_get: null });
    const segments = createSegments({ transport, schema: "api" });

    expect(await segments.get("s9").orThrow()).toBeUndefined();

    const { transport: empty } = fakeTransport({ segment_get: undefined });

    expect(
      await createSegments({ transport: empty }).get("s9").orThrow(),
    ).toBeUndefined();
  });

  it("logs failed calls through the hooks", async () => {
    const { transport } = fakeTransport({});

    const logger = {
      debug: vi.fn(),
      info: vi.fn(),
      warn: vi.fn(),
      error: vi.fn(),
    };

    const result = await createSegments({ transport, logger }).refresh("s1");

    expect(result.ok).toBe(false);
  });

  it("validates input and declares the manifest", async () => {
    const validate = segmentInputSchema["~standard"].validate;

    expect(
      (await validate({ subjectType: "company", name: "SaaS" })).issues,
    ).toBeUndefined();
    expect((await validate({ name: "" })).issues).toBeDefined();
    expect(segmentsBlock.name).toBe("segments");
  });
});
