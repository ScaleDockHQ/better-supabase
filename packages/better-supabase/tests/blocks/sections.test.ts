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
import { renameBlock } from "../../src/blocks/rename-block.ts";
import {
  defineSection,
  sectionEventMatches,
} from "../../src/blocks/sections.ts";
import { tagsBlock, tagsOptimistic } from "../../src/blocks/tags/index.ts";
import { AsyncResult, ok } from "../../src/core/result.ts";

const comment = (id: string, body = id): Comment =>
  ({ id, body }) as unknown as Comment;

const attachment = (id: string): Attachment =>
  ({ id }) as unknown as Attachment;

const tag = (id: string): Tag => ({ id }) as unknown as Tag;

describe("defineSection", () => {
  it("adds apiVersion 1 and empty events", () => {
    const section = defineSection({
      permissions: { read: "read" },
      load: () => AsyncResult.from(() => Promise.resolve(ok([]))),
    });

    expect(section.apiVersion).toBe(1);
    expect(section.events).toEqual([]);
  });

  it("matches exact event types and prefixes ending in *", () => {
    expect(sectionEventMatches("comment.created", "comment.created")).toBe(
      true,
    );
    expect(sectionEventMatches("attachment.*", "attachment.scanned")).toBe(
      true,
    );
    expect(sectionEventMatches("attachment.*", "comment.created")).toBe(false);
  });

  it("puts sections on the comments, attachments and tags manifests", () => {
    expect(Object.keys(commentsBlock.sections)).toEqual(["comments"]);
    expect(Object.keys(attachmentsBlock.sections)).toEqual(["attachments"]);
    expect(Object.keys(tagsBlock.sections)).toEqual(["tags"]);
    expect(commentsBlock.with({}).sections).toBe(commentsBlock.sections);
  });

  it("gives a block without sections an empty map", () => {
    const block = defineBlock({ name: "plain", category: "admin" });

    expect(block.sections).toEqual({});
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

  it("runs from the manifest's section", () => {
    const reduce = commentsBlock.sections.comments.optimistic;

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

describe("sections of a renamed block", () => {
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
    sections: {
      notes: defineSection({
        permissions: { read: "read" },
        load: (client: WorkNotes, subject) => client.list(subject),
        count: (client: WorkNotes) => client.counts(),
        events: ["work_item.created"],
        optimistic: (
          state: readonly { workItemId: string }[],
          action: { workItemId: string },
        ) => [...state, action],
      }),
    },
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
    const section = renamed.sections.notes;
    const client = renamed.create?.({} as never);

    expect(section.events).toEqual(["task.created"]);

    const loaded = await (
      section.load as (
        client: unknown,
        subject: unknown,
        options: unknown,
      ) => AsyncResult<unknown>
    )(client, { type: "task", id: "1" }, undefined);

    expect(loaded.ok && loaded.data).toEqual([{ taskId: "1" }]);

    const counted = await (
      section.count as (
        client: unknown,
        subjects: unknown,
      ) => AsyncResult<unknown>
    )(client, []);

    expect(counted.ok && counted.data).toEqual({ "task:1": 2 });
    expect(
      (section.optimistic as (state: unknown, action: unknown) => unknown)([], {
        taskId: "2",
      }),
    ).toEqual([{ taskId: "2" }]);
  });

  it("keeps a section without count or optimistic as it is", () => {
    const bare = renameBlock(
      defineBlock({
        name: "bare",
        category: "work",
        sections: {
          bare: defineSection({
            permissions: { read: "read" },
            load: () => AsyncResult.from(() => Promise.resolve(ok(1))),
          }),
        },
      }),
      names,
    );

    expect(bare.sections.bare.count).toBeUndefined();
    expect(bare.sections.bare.optimistic).toBeUndefined();
  });
});
