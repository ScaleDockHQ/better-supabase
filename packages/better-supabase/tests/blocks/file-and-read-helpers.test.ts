import { describe, expect, it } from "vitest";

import type { AttachmentStorage } from "../../src/blocks/attachments/index.ts";

import { createAttachments } from "../../src/blocks/attachments/index.ts";
import { createComments } from "../../src/blocks/comments/index.ts";
import { createImports } from "../../src/blocks/imports/index.ts";
import { createLeave } from "../../src/blocks/leave/index.ts";
import { createPasses } from "../../src/blocks/passes/index.ts";
import { createReactions } from "../../src/blocks/reactions/index.ts";
import { createTags } from "../../src/blocks/tags/index.ts";
import {
  createTemplates,
  defineMergeFields,
  defineTemplateType,
} from "../../src/blocks/templates/index.ts";
import { rankBetween } from "../../src/core/rank-keys.ts";
import { neighborsForIndex } from "../../src/core/rank-result.ts";

const K1 = rankBetween(null, null);
const K2 = rankBetween(K1, null);
const K3 = rankBetween(K2, null);

type Answer = (args: Record<string, unknown>) => unknown;

function transport(answers: Record<string, unknown>) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    call(_schema: string, fn: string, args: Record<string, unknown>) {
      calls.push([fn, { ...args }]);
      const answer = answers[fn];

      if (answer === undefined) {
        return Promise.reject(new Error(`unexpected ${fn}`));
      }

      return Promise.resolve(
        typeof answer === "function" ? (answer as Answer)(args) : answer,
      );
    },
  };
}

const AT = "2026-10-06T12:00:00Z";

const FILE = (id: string, over: Record<string, unknown> = {}) => ({
  id,
  organization_id: "org-1",
  subject_type: "conversation",
  subject_id: "c1",
  bucket: "attachments",
  object_path: `org-1/${id}`,
  name: "a.txt",
  mime_type: "text/plain",
  size: "3",
  status: "pending",
  uploaded_by: "u1",
  created_at: AT,
  uploaded_at: null,
  ...over,
});

function storage(failUpload = false) {
  const calls: string[] = [];

  const store = {
    from: () => ({
      createSignedUploadUrl: (path: string) =>
        Promise.resolve({
          data: { signedUrl: `https://s/${path}`, token: "tok" },
          error: null,
        }),
      createSignedUrl: () => Promise.resolve({ data: null, error: null }),
      download: () => Promise.resolve({ data: null, error: null }),
      remove: (paths: string[]) => {
        calls.push(`remove:${paths.join(",")}`);

        return Promise.resolve({ data: [], error: null });
      },
      uploadToSignedUrl: (path: string, token: string) => {
        calls.push(`upload:${path}:${token}`);

        return Promise.resolve(
          failUpload
            ? { data: null, error: { message: "denied", statusCode: "403" } }
            : { data: { path }, error: null },
        );
      },
    }),
    // SAFETY: the fake has the structural methods the block calls.
  } as unknown as AttachmentStorage;

  return { calls, store };
}

describe("attachments.uploadFile", () => {
  it("creates, uploads to the signed URL, confirms and reports start and end", async () => {
    const t = transport({
      create_attachment: FILE("a1"),
      confirm_attachment: FILE("a1", { status: "clean", uploaded_at: AT }),
      get_attachment: FILE("a1", { uploaded_at: AT, status: "clean" }),
    });

    const s = storage();
    const progress: number[] = [];

    const attachments = createAttachments({
      transport: t,
      storage: s.store,
      tenant: "org-1",
    });

    const saved = await attachments
      .uploadFile({
        subject: { type: "project", id: "p1" },
        file: new File(["abc"], "a.txt", { type: "text/plain" }),
        onProgress: ({ loaded }) => void progress.push(loaded),
      })
      .orThrow();

    expect(saved.id).toBe("a1");
    expect(progress).toEqual([0, 3]);
    expect(s.calls).toEqual(["upload:org-1/a1:tok"]);
    expect(t.calls[0]?.[1]).toMatchObject({
      name: "a.txt",
      mime_type: "text/plain",
      size: 3,
    });
  });

  it("deletes the record again when Storage refuses the file", async () => {
    const t = transport({
      create_attachment: FILE("a1"),
      delete_attachment: true,
      remove_attachment: true,
    });

    const attachments = createAttachments({
      transport: t,
      storage: storage(true).store,
      tenant: "org-1",
    });

    const result = await attachments.uploadFile({
      subject: null,
      file: new File(["abc"], "a.txt"),
    });

    expect(result.ok).toBe(false);
    expect(t.calls.length).toBeGreaterThan(1);
  });
});

describe("comments.createWithFiles", () => {
  const comment = (id: string) => ({
    id,
    tenant_id: "org-1",
    conversation_id: "conv-1",
    subject_type: "project",
    subject_id: "p1",
    author_id: "u1",
    body: "hi",
    mentions: [],
    parent_id: null,
    thread_id: null,
    anchor: null,
    sent_at: AT,
    created_at: AT,
    edited_at: null,
    deleted_at: null,
    task_id: null,
  });

  it("needs the attachments port", async () => {
    const comments = createComments({ transport: transport({}), tenant: "o" });

    const result = await comments.createWithFiles({
      subject: { type: "project", id: "p1" },
      comment: { body: "hi" },
      files: [new File(["a"], "a.txt")],
    });

    expect(!result.ok && result.error).toMatchObject({
      hint: "COMMENTS_ATTACHMENTS_MISSING",
    });
  });

  it("uploads to the conversation, then posts with the ids, and undoes on failure", async () => {
    const uploads: string[] = [];
    const removed: string[] = [];
    let n = 0;

    const attachments = {
      uploadFile: (input: { subject: { type: string; id: string } | null }) => {
        uploads.push(`${input.subject?.type}:${input.subject?.id}`);
        n += 1;

        return Promise.resolve({ ok: true as const, data: { id: `f${n}` } });
      },
      remove: (id: string) => {
        removed.push(id);

        return Promise.resolve({ ok: true as const, data: true });
      },
    };

    const t = transport({
      open_conversation: { id: "c1" },
      create_comment: (args: Record<string, unknown>) =>
        args["attachments"] ? comment("m1") : comment("m0"),
    });

    const comments = createComments({
      transport: t,
      tenant: "o",
      // SAFETY: the test passes the two methods createWithFiles calls.
      attachments: attachments as never,
    });

    const posted = await comments
      .createWithFiles({
        subject: { type: "project", id: "p1" },
        comment: { body: "hi" },
        files: [new File(["a"], "a.txt"), new File(["b"], "b.txt")],
      })
      .orThrow();

    expect(posted.id).toBe("m1");
    expect(uploads).toEqual(["conversation:c1", "conversation:c1"]);
    expect(t.calls.at(-1)?.[1]["attachments"]).toEqual(["f1", "f2"]);

    const failing = createComments({
      transport: transport({
        open_conversation: { id: "c1" },
        create_comment: () => Promise.reject(new Error("boom")),
      }),
      tenant: "o",
      // SAFETY: as above.
      attachments: attachments as never,
    });

    const failed = await failing.createWithFiles({
      subject: { type: "project", id: "p1" },
      comment: { body: "hi" },
      files: [new File(["a"], "a.txt")],
    });

    expect(failed.ok).toBe(false);
    expect(removed).toEqual(["f3"]);
  });
});

describe("reactions.who", () => {
  it("lists the actors by emoji and counts the hidden ones", async () => {
    const reactions = createReactions({
      transport: transport({
        reaction_summary: {
          t1: [
            { emoji: "👍", count: 12, reacted: true, actors: ["a", "b"] },
            { emoji: "🎉", count: 1, reacted: false, actors: ["c"] },
          ],
        },
      }),
      tenant: "o",
    });

    expect(
      await reactions
        .who({ subject: { type: "t", id: "t1" }, emoji: "👍" })
        .orThrow(),
    ).toEqual({
      "👍": { count: 12, actors: ["a", "b"], hidden: 10, reacted: true },
    });
  });
});

describe("templates.variables and templates.preview", () => {
  const catalog = defineMergeFields("invoice", {
    "customer.name": { example: "Ada" },
    total: { example: "10" },
  });

  const template = (body: unknown) => ({
    id: "t1",
    scope: "tenant",
    type: "invoice",
    name: "Invoice",
    language: "en",
    isDefault: false,
    settings: {},
    behind: false,
    createdAt: AT,
    updatedAt: AT,
    published: {
      id: "v1",
      template: "t1",
      version: 2,
      hash: "h",
      createdAt: AT,
      publishedAt: AT,
      body,
    },
  });

  it("lists the catalog and renders a body with examples and values", async () => {
    const templates = createTemplates({
      transport: transport({
        template_get: template({
          title: "Hi {{ customer.name }}",
          lines: ["{{ total }}", "{{ nope }}"],
        }),
      }),
      types: { invoice: defineTemplateType({ mergeFields: catalog }) },
    });

    expect(
      (await templates.variables({ type: "invoice" }).orThrow()).map(
        (v) => v.name,
      ),
    ).toEqual(["customer.name", "total"]);

    const unknown = await templates.variables({ type: "nope" });
    expect(!unknown.ok && unknown.error.kind).toBe("not_found");

    const preview = await templates
      .preview({ template: "t1", values: { total: "99" } })
      .orThrow();

    expect(preview).toMatchObject({
      version: 2,
      body: { title: "Hi Ada", lines: ["99", ""] },
      unknownFields: ["nope"],
    });
  });
});

describe("imports.run", () => {
  it("starts, writes batches in order, finishes and collects errors", async () => {
    const t = transport({
      start_import_run: { id: "r1" },
      mark_import_running: true,
      import_upsert_batch: (args: Record<string, unknown>) => ({
        inserted: (args["items"] as unknown[]).length,
        updated: 0,
        unchanged: 0,
        conflicted: 0,
        errors:
          args["entity"] === "b"
            ? [{ key: "k", code: "BAD", message: "m" }]
            : [],
      }),
      finish_import_run: { a: { inserted: 3 } },
      cancel_import_run: true,
    });

    const batches: string[] = [];

    const result = await createImports({ transport: t })
      .run({
        organizationId: "o",
        source: "s",
        batchSize: 2,
        entities: [
          {
            entity: "a",
            items: [
              { key: "1", data: {} },
              { key: "2", data: {} },
              { key: "3", data: {} },
            ],
          },
          { entity: "b", items: [{ key: "4", data: {} }] },
        ],
        onBatch: ({ entity, items }) => void batches.push(`${entity}${items}`),
      })
      .orThrow();

    expect(t.calls.map(([fn]) => fn)).toEqual([
      "start_import_run",
      "mark_import_running",
      "import_upsert_batch",
      "import_upsert_batch",
      "import_upsert_batch",
      "finish_import_run",
    ]);
    expect(batches).toEqual(["a2", "a3", "b1"]);
    expect(result.errors).toEqual([
      { entity: "b", key: "k", code: "BAD", message: "m" },
    ]);
  });

  it("cancels the run when a batch fails", async () => {
    const t = transport({
      start_import_run: { id: "r1" },
      mark_import_running: true,
      import_upsert_batch: () => Promise.reject(new Error("down")),
      cancel_import_run: true,
    });

    const result = await createImports({ transport: t }).run({
      organizationId: "o",
      source: "s",
      entities: [{ entity: "a", items: [{ key: "1", data: {} }] }],
    });

    expect(result.ok).toBe(false);
    expect(t.calls.at(-1)?.[0]).toBe("cancel_import_run");
  });
});

describe("passes.scan", () => {
  it("answers an unreadable token as a refusal instead of an error", async () => {
    const passes = createPasses({
      transport: transport({}),
      jwks: { keys: [] },
      tenant: "o",
    });

    expect(await passes.scan({ token: "nonsense" }).orThrow()).toEqual({
      admitted: false,
      reason: "invalid",
    });
  });
});

describe("leave.workingDays", () => {
  it("asks the module for the working days of a range", async () => {
    const t = transport({ leave_working_days: 4 });

    expect(
      await createLeave({ transport: t })
        .workingDays({
          from: Temporal.PlainDate.from("2026-11-02"),
          to: Temporal.PlainDate.from("2026-11-06"),
        })
        .orThrow(),
    ).toBe(4);
    expect(t.calls[0]).toEqual([
      "leave_working_days",
      { starts_on: "2026-11-02", ends_on: "2026-11-06" },
    ]);
  });
});

describe("move(id, toIndex)", () => {
  const ranked = [
    { id: "a", rank: K1 },
    { id: "b", rank: K2 },
    { id: "c", rank: K3 },
  ];

  it("derives the neighbours from the position", () => {
    expect(neighborsForIndex(ranked, "c", 0)).toMatchObject({
      ok: true,
      data: { previous: null, next: K1 },
    });
    expect(neighborsForIndex(ranked, "a", 1)).toMatchObject({
      ok: true,
      data: { previous: K2, next: K3 },
    });
    expect(neighborsForIndex(ranked, "a", 99)).toMatchObject({
      ok: true,
      data: { previous: K3, next: null },
    });
    expect(neighborsForIndex(ranked, "x", 0).ok).toBe(false);
    expect(neighborsForIndex([{ id: "a" }, { id: "b" }], "a", 1)).toMatchObject(
      { ok: false },
    );
  });

  it("tags, definitions and views read the list and rank between neighbours", async () => {
    const tag = (id: string, rank: string) => ({
      id,
      organizationId: "o",
      name: id,
      slug: id,
      rank,
    });

    const tags = transport({
      list_tags: [tag("a", K1), tag("b", K2), tag("c", K3)],
      rank_tag: true,
    });

    const key = await createTags({ transport: tags, tenant: "o" })
      .move({ id: "c", toIndex: 0 })
      .orThrow();

    expect(tags.calls.at(-1)).toEqual(["rank_tag", { tag_id: "c", rank: key }]);
    expect(key < K1).toBe(true);
  });
});
