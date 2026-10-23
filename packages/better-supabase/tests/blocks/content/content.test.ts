import { describe, expect, it } from "vitest";

import {
  contentBlock,
  contentEntryInputSchema,
  contentEvents,
  createContent,
} from "../../../src/blocks/content/index.ts";
import { fakeTransport } from "../inbox/fixtures.ts";

const AT = "2026-01-01T00:00:00Z";
const LATER = "2026-02-01T09:00:00Z";

const ENTRY = {
  id: "e1",
  organizationId: "org",
  type: "post",
  locale: "en",
  slug: "hello-world",
  title: "Hello world",
  summary: "The first post",
  body: { type: "doc", content: [] },
  status: "draft",
  publishAt: null,
  publishedAt: null,
  authorId: "u1",
  translationGroupId: "g1",
  coverAttachmentId: null,
  approvalId: null,
  approvalStatus: null,
  createdBy: "u1",
  createdAt: AT,
  updatedAt: AT,
};

const PUBLIC = {
  id: "e1",
  type: "post",
  locale: "en",
  slug: "hello-world",
  title: "Hello world",
  summary: null,
  coverAttachmentId: "a1",
  translationGroupId: "g1",
  publishedAt: AT,
  updatedAt: AT,
};

describe("createContent", () => {
  it("writes and reads entries", async () => {
    const { transport, call } = fakeTransport({
      create_content_entry: ENTRY,
      update_content_entry: { ...ENTRY, title: "Hello" },
      archive_content_entry: { ...ENTRY, status: "archived" },
      get_content_entry: {
        ...ENTRY,
        summary: null,
        authorId: null,
        body: [{ text: "hi" }],
        translations: [
          { id: "e2", locale: "nl", slug: "hallo-wereld", status: "draft" },
        ],
      },
      list_content_entries: [ENTRY],
    });

    const content = createContent({ transport, tenant: "org" });

    const created = await content
      // SAFETY: an undefined key on purpose, to check that it is left out.
      .create({
        type: "post",
        slug: "hello-world",
        title: "Hello world",
        body: { type: "doc", content: [] },
        translationOf: undefined,
      } as never)
      .orThrow();

    expect(created).toMatchObject({
      id: "e1",
      status: "draft",
      summary: "The first post",
      body: { type: "doc", content: [] },
      translationGroupId: "g1",
    });
    expect(created.publishAt).toBeUndefined();
    expect(created.approvalStatus).toBeUndefined();
    expect(created.translations).toBeUndefined();
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "create_content_entry",
      {
        tenant: "org",
        attrs: {
          type: "post",
          slug: "hello-world",
          title: "Hello world",
          body: { type: "doc", content: [] },
        },
      },
    );

    expect(
      (await content.update("e1", { title: "Hello" }).orThrow()).title,
    ).toBe("Hello");
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "update_content_entry",
      { entry_id: "e1", attrs: { title: "Hello" } },
    );

    expect((await content.archive("e1").orThrow()).status).toBe("archived");

    const read = await content.get("e1").orThrow();

    expect(read?.body).toEqual([{ text: "hi" }]);
    expect(read?.summary).toBeUndefined();
    expect(read?.authorId).toBeUndefined();
    expect(read?.translations).toEqual([
      { id: "e2", locale: "nl", slug: "hallo-wereld", status: "draft" },
    ]);

    expect(
      await content.list({ type: "post", status: "draft" }).orThrow(),
    ).toHaveLength(1);
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "list_content_entries",
      { tenant: "org", filter: { type: "post", status: "draft" } },
    );
  });

  it("publishes, schedules and requests approval", async () => {
    const { transport, call } = fakeTransport({
      publish_content_entry: {
        ...ENTRY,
        approvalId: "r1",
        approvalStatus: "pending",
      },
      schedule_content_entry: (args: Record<string, unknown>) =>
        args["at"] === null
          ? ENTRY
          : { ...ENTRY, status: "scheduled", publishAt: LATER },
      publish_due_content_entries: 3,
    });

    const content = createContent({ transport, tenant: "org" });

    const requested = await content.publish("e1").orThrow();

    expect(requested.status).toBe("draft");
    expect(requested.approvalId).toBe("r1");
    expect(requested.approvalStatus).toBe("pending");

    const scheduled = await content
      .schedule("e1", Temporal.Instant.from(LATER))
      .orThrow();

    expect(scheduled.status).toBe("scheduled");
    expect(scheduled.publishAt?.toString()).toBe(LATER);
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "schedule_content_entry",
      { entry_id: "e1", at: LATER },
    );

    expect((await content.schedule("e1", null).orThrow()).status).toBe("draft");
    expect(await content.publishDue().orThrow()).toBe(3);
  });

  it("reads published entries for anyone", async () => {
    const { transport, call } = fakeTransport({
      public_content_entry: (args: Record<string, unknown>) =>
        args["slug"] === "missing"
          ? null
          : {
              ...PUBLIC,
              body: { blocks: [] },
              translations: [{ locale: "nl", slug: "hallo-wereld" }],
            },
      public_content_entries: [PUBLIC],
    });

    const content = createContent({ transport, tenant: "org" });

    const entry = await content
      .published({ type: "post", slug: "hello-world", locale: "en" })
      .orThrow();

    expect(entry).toMatchObject({
      slug: "hello-world",
      body: { blocks: [] },
      coverAttachmentId: "a1",
      translations: [{ locale: "nl", slug: "hallo-wereld" }],
    });
    expect(entry?.summary).toBeUndefined();
    expect(
      await content.published({ type: "post", slug: "missing" }).orThrow(),
    ).toBeNull();
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "public_content_entry",
      { tenant: "org", type: "post", slug: "missing", locale: null },
    );

    const [first] = await content
      .listPublished({ type: "post", before: Temporal.Instant.from(LATER) })
      .orThrow();

    expect(first?.body).toBeUndefined();
    expect(first?.publishedAt.toString()).toBe(AT);
    expect(call).toHaveBeenLastCalledWith(
      "better_supabase",
      "public_content_entries",
      {
        tenant: "org",
        type: "post",
        locale: null,
        page_size: null,
        before: LATER,
      },
    );
    await content.listPublished().orThrow();
  });

  it("returns null for an entry the caller can't read", async () => {
    const { transport } = fakeTransport({ get_content_entry: null });

    expect(await createContent({ transport }).get("e9").orThrow()).toBeNull();
  });

  it("needs a tenant for the organization's entries", async () => {
    const { transport, call } = fakeTransport({});
    const content = createContent({ transport });

    expect((await content.list()).ok).toBe(false);
    expect((await content.listPublished()).ok).toBe(false);
    expect(call).not.toHaveBeenCalled();
  });

  it("refuses a status the client doesn't know", async () => {
    const { transport } = fakeTransport({
      get_content_entry: { ...ENTRY, status: "live" },
    });

    expect((await createContent({ transport }).get("e1")).ok).toBe(false);
  });

  it("validates input and declares the block", async () => {
    expect(
      (
        await contentEntryInputSchema["~standard"].validate({
          type: "page",
          slug: "about",
          title: "About",
        })
      ).issues,
    ).toBeUndefined();
    expect(
      (await contentEntryInputSchema["~standard"].validate({ type: "page" }))
        .issues,
    ).toBeDefined();
    expect(contentBlock.name).toBe("content");
    expect(contentEvents.types).toContain("content_entry.published");
  });
});
