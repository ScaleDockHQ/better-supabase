import { describe, expect, it } from "vitest";

import type { Attachment } from "../../src/blocks/attachments/attachments.ts";
import type { Comment } from "../../src/blocks/comments/comments.ts";
import type { Tag } from "../../src/blocks/tags/tags.ts";

import {
  attachmentsBlock,
  attachmentsOptimistic,
} from "../../src/blocks/attachments/index.ts";
import {
  commentsBlock,
  commentsOptimistic,
} from "../../src/blocks/comments/index.ts";
import { defineBlock } from "../../src/blocks/define-block.ts";
import {
  defineRecordBinding,
  recordEventMatches,
} from "../../src/blocks/record-bindings.ts";
import { renameBlock } from "../../src/blocks/rename-block.ts";
import { tagsBlock, tagsOptimistic } from "../../src/blocks/tags/index.ts";
import { AsyncResult, ok } from "../../src/core/result.ts";

const comment = (id: string, body = id): Comment =>
  ({ id, body }) as unknown as Comment;

const attachment = (id: string): Attachment =>
  ({ id }) as unknown as Attachment;

const tag = (id: string): Tag => ({ id }) as unknown as Tag;

describe("defineRecordBinding", () => {
  it("adds apiVersion 1 and empty events", () => {
    const binding = defineRecordBinding({
      permissions: { read: "read" },
      load: () => AsyncResult.from(() => Promise.resolve(ok([]))),
    });

    expect(binding.apiVersion).toBe(1);
    expect(binding.events).toEqual([]);
  });

  it("matches exact event types and prefixes ending in *", () => {
    expect(recordEventMatches("comment.created", "comment.created")).toBe(true);
    expect(recordEventMatches("attachment.*", "attachment.scanned")).toBe(true);
    expect(recordEventMatches("attachment.*", "comment.created")).toBe(false);
  });

  it("puts a record binding on the comments, attachments and tags manifests", () => {
    expect(commentsBlock.record.events).toContain("message.sent");
    expect(attachmentsBlock.record).toBeDefined();
    expect(tagsBlock.record).toBeDefined();
    expect(commentsBlock.with({}).record).toBe(commentsBlock.record);
  });

  it("leaves a block without a binding undefined", () => {
    const block = defineBlock({ name: "plain", category: "admin" });

    expect(block.record).toBeUndefined();
  });
});

describe("optimistic reducers", () => {
  it("adds, edits and removes comments", () => {
    const state = [comment("a"), comment("b")];

    expect(
      commentsOptimistic(state, { type: "add", comment: comment("c") }).map(
        (each) => each.id,
      ),
    ).toEqual(["a", "b", "c"]);
    expect(
      commentsOptimistic(state, { type: "add", comment: comment("a", "new") }),
    ).toEqual([comment("b"), comment("a", "new")]);
    expect(
      commentsOptimistic(state, { type: "edit", id: "b", body: "edited" }),
    ).toEqual([comment("a"), comment("b", "edited")]);
    expect(commentsOptimistic(state, { type: "remove", id: "a" })).toEqual([
      comment("b"),
    ]);
  });

  it("adds and removes attachments, newest first", () => {
    const state = [attachment("a")];

    expect(
      attachmentsOptimistic(state, {
        type: "add",
        attachment: attachment("b"),
      }).map((each) => each.id),
    ).toEqual(["b", "a"]);
    expect(attachmentsOptimistic(state, { type: "remove", id: "a" })).toEqual(
      [],
    );
  });

  it("tags once and untags", () => {
    const state = [tag("a")];

    expect(tagsOptimistic(state, { type: "tag", tag: tag("a") })).toBe(state);
    expect(
      tagsOptimistic(state, { type: "tag", tag: tag("b") }).map(
        (each) => each.id,
      ),
    ).toEqual(["a", "b"]);
    expect(tagsOptimistic(state, { type: "untag", id: "a" })).toEqual([]);
  });

  it("runs from the manifest's binding", () => {
    const reduce = commentsBlock.record.optimistic;

    expect(reduce?.([], { type: "add", comment: comment("x") })).toEqual([
      comment("x"),
    ]);
  });
});

interface WorkNotes {
  list: (subject: {
    type: string;
    id: string;
  }) => AsyncResult<readonly { workItemId: string }[]>;
  counts: () => AsyncResult<Readonly<Record<string, number>>>;
}

describe("bindings of a renamed block", () => {
  const block = defineBlock({
    name: "notes",
    category: "work",
    create: (): WorkNotes => ({
      list: (subject: { type: string; id: string }) =>
        AsyncResult.from(() =>
          Promise.resolve(ok([{ workItemId: subject.id }])),
        ),
      counts: () =>
        AsyncResult.from(() => Promise.resolve(ok({ "task:1": 2 }))),
    }),
    record: defineRecordBinding({
      permissions: { read: "read" },
      load: (client: WorkNotes, subject) => client.list(subject),
      count: (client: WorkNotes) => client.counts(),
      events: ["task.created"],
      optimistic: (
        state: readonly { workItemId: string }[],
        action: { workItemId: string },
      ) => [...state, action],
    }),
  });

  const names = {
    entities: [
      {
        from: { singular: "work_item", plural: "work_items" },
        to: { singular: "task", plural: "tasks" },
      },
    ],
  } as const;

  const renamed = renameBlock(block, names);

  it("reads through the original client and renames the rows", async () => {
    const binding = renamed.record;
    const client = renamed.create?.({} as never);

    expect(binding.events).toEqual(["task.created"]);

    const loaded = await (
      binding.load as (
        client: unknown,
        subject: unknown,
        options: unknown,
      ) => AsyncResult<unknown>
    )(client, { type: "task", id: "1" }, undefined);

    expect(loaded.ok && loaded.data).toEqual([{ taskId: "1" }]);

    const counted = await (
      binding.count as (
        client: unknown,
        subjects: unknown,
      ) => AsyncResult<unknown>
    )(client, []);

    expect(counted.ok && counted.data).toEqual({ "task:1": 2 });
    expect(
      (binding.optimistic as (state: unknown, action: unknown) => unknown)([], {
        taskId: "2",
      }),
    ).toEqual([{ taskId: "2" }]);
  });

  it("keeps a binding without count or optimistic as it is", () => {
    const bare = renameBlock(
      defineBlock({
        name: "bare",
        category: "work",
        record: defineRecordBinding({
          permissions: { read: "read" },
          load: () => AsyncResult.from(() => Promise.resolve(ok(1))),
        }),
      }),
      names,
    );

    expect(bare.record.count).toBeUndefined();
    expect(bare.record.optimistic).toBeUndefined();
  });
});
