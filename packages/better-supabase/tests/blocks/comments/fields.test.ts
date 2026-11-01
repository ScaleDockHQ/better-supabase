import * as v from "valibot";
import { describe, expect, expectTypeOf, it } from "vitest";

import { createComments } from "../../../src/blocks/comments/index.ts";
import { fieldsTransport } from "../fields-transport.ts";

const PROJECT = { type: "project", id: "p1" };

const ROW = {
  id: "c1",
  tenant_id: "org-1",
  conversation_id: "conv-1",
  subject_type: "project",
  subject_id: "p1",
  author_id: null,
  body: "Hello",
  mentions: [],
  parent_id: null,
  sent_at: "2026-10-06T12:00:00Z",
  created_at: "2026-10-06T12:00:00Z",
  edited_at: null,
  deleted_at: null,
  fields: { visibility: "internal" },
};

const attrsOf = (
  call: readonly [string, Readonly<Record<string, unknown>>] | undefined,
): Readonly<Record<string, unknown>> => {
  const attrs = call?.[1]["attrs"];

  return typeof attrs === "object" && attrs !== null
    ? Object.fromEntries(Object.entries(attrs))
    : {};
};

const Fields = v.object({ visibility: v.picklist(["internal", "customer"]) });

describe("comments fields", () => {
  it("sends the extra fields under attrs.fields and parses every read", async () => {
    const t = fieldsTransport({
      create_comment: () => ROW,
      edit_message: () => ({}),
      get_comment: () => ROW,
      list_comments: () => [ROW, ROW],
    });

    const comments = createComments({
      transport: t,
      fields: Fields,
      tenant: "org-1",
    });

    const created = await comments
      .create({
        subject: PROJECT,
        comment: { body: "Hello", fields: { visibility: "internal" } },
      })
      .orThrow();

    expectTypeOf(created.fields.visibility).toEqualTypeOf<
      "internal" | "customer"
    >();
    expect(created.fields).toEqual({ visibility: "internal" });
    expect(attrsOf(t.calls[0])["fields"]).toEqual({ visibility: "internal" });
    await comments
      .edit({
        id: "c1",
        edit: { body: "Changed", fields: { visibility: "customer" } },
      })
      .orThrow();
    expect(attrsOf(t.calls[1])["fields"]).toEqual({ visibility: "customer" });
    const list = await comments.list({ subject: PROJECT }).orThrow();
    expect(list.map((comment) => comment.fields.visibility)).toEqual([
      "internal",
      "internal",
    ]);
  });

  it("leaves fields out of a write that sets none", async () => {
    const t = fieldsTransport({ create_comment: () => ROW });
    await createComments({ transport: t, tenant: "org-1" })
      .create({ subject: PROJECT, comment: { body: "Hello" } })
      .orThrow();
    expect(attrsOf(t.calls[0])["fields"]).toBeUndefined();
  });

  it("refuses a bad field before the call and a bad row after it", async () => {
    const t = fieldsTransport({
      list_comments: () => [{ ...ROW, fields: { visibility: "public" } }],
    });

    const comments = createComments({
      transport: t,
      fields: Fields,
      tenant: "org-1",
    });

    const edited = await comments.edit({
      id: "c1",
      edit: { body: "Changed", fields: { visibility: "public" as never } },
    });

    expect(edited.ok ? undefined : edited.error.kind).toBe("validation");
    expect(t.calls).toEqual([]);
    const listed = await comments.list({ subject: PROJECT });
    expect(listed.ok ? undefined : listed.error.kind).toBe("validation");
  });
});
