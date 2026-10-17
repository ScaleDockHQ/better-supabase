import * as v from "valibot";
import { describe, expect, expectTypeOf, it } from "vitest";

import { createComments } from "../../../src/blocks/comments/index.ts";
import { fieldsTransport } from "../fields-transport.ts";

const ROW = {
  id: "c1",
  organization_id: "org-1",
  subject_type: "project",
  subject_id: "p1",
  author_id: null,
  body: "Hello",
  mentions: [],
  parent_id: null,
  created_at: "2026-10-06T12:00:00Z",
  edited_at: null,
  deleted_at: null,
  fields: { visibility: "internal" },
};

const Fields = v.object({
  visibility: v.picklist(["internal", "customer"]),
});

describe("comments fields", () => {
  it("sends the extra fields under fields and parses every read", async () => {
    const t = fieldsTransport({
      create_comment: () => ROW,
      edit_comment: () => ROW,
      list_comments: () => [ROW, ROW],
    });

    const comments = createComments({ transport: t, fields: Fields });

    const created = await comments
      .create({
        organizationId: "org-1",
        subjectType: "project",
        subjectId: "p1",
        body: "Hello",
        fields: { visibility: "internal" },
      })
      .orThrow();

    expectTypeOf(created.fields.visibility).toEqualTypeOf<
      "internal" | "customer"
    >();
    expect(created.fields).toEqual({ visibility: "internal" });
    expect(t.calls[0]?.[1]["fields"]).toEqual({ visibility: "internal" });
    await comments
      .edit("c1", { body: "Changed", fields: { visibility: "customer" } })
      .orThrow();
    expect(t.calls[1]?.[1]["fields"]).toEqual({ visibility: "customer" });
    const list = await comments.list("org-1", "project", "p1").orThrow();
    expect(list.map((comment) => comment.fields.visibility)).toEqual([
      "internal",
      "internal",
    ]);
  });

  it("leaves fields out of a write that sets none", async () => {
    const t = fieldsTransport({ create_comment: () => ROW });
    await createComments({ transport: t })
      .create({
        organizationId: "org-1",
        subjectType: "project",
        subjectId: "p1",
        body: "Hello",
      })
      .orThrow();
    expect(t.calls[0]?.[1]["fields"]).toBeUndefined();
  });

  it("refuses a bad field before the call and a bad row after it", async () => {
    const t = fieldsTransport({
      list_comments: () => [{ ...ROW, fields: { visibility: "public" } }],
    });

    const comments = createComments({ transport: t, fields: Fields });

    const edited = await comments.edit("c1", {
      body: "Changed",
      fields: { visibility: "public" as never },
    });

    expect(edited.ok ? undefined : edited.error.kind).toBe("validation");
    expect(t.calls).toEqual([]);
    const listed = await comments.list("org-1", "project", "p1");
    expect(listed.ok ? undefined : listed.error.kind).toBe("validation");
  });
});
