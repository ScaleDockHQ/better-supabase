import { describe, expect, test } from "vitest";

import {
  eventsColumnsEdited,
  subjectColumns,
  subjectColumnsEdited,
  subjectTypeError,
} from "../../src/create/design-subject.ts";

describe("subjectColumns", () => {
  test("adds nothing without a subject", () => {
    expect(subjectColumns(undefined)).toEqual([]);
    expect(subjectColumns({ type: "post" })).toEqual([]);
  });

  test("adds rank and deleted_at when asked for", () => {
    expect(
      subjectColumns({ type: "post", rank: true, softDelete: true }).map(
        (column) => column.name,
      ),
    ).toEqual(["rank", "deleted_at"]);
  });
});

describe("subjectColumnsEdited", () => {
  const upper = (columns: readonly string[]): readonly string[] =>
    columns.map((column) => column.toUpperCase());

  test("renames the title, search columns and rank group", () => {
    expect(
      subjectColumnsEdited(
        {
          type: "post",
          title: "title",
          search: { title: "title", body: ["body"] },
          rank: { group: "status" },
        },
        upper,
      ),
    ).toEqual({
      type: "post",
      title: "TITLE",
      search: { title: "TITLE", body: ["BODY"] },
      rank: { group: "STATUS" },
    });
  });

  test("drops what the edit removes", () => {
    expect(
      subjectColumnsEdited(
        {
          type: "post",
          title: "title",
          search: { title: "title", body: ["body"] },
          rank: { group: "status" },
        },
        () => [],
      ),
    ).toEqual({ type: "post", search: {}, rank: true });
  });

  test("keeps a plain rank", () => {
    expect(subjectColumnsEdited({ type: "post", rank: true }, upper)).toEqual({
      type: "post",
      rank: true,
    });
  });
});

describe("subjectColumnsEdited versions and rank", () => {
  const upper = (columns: readonly string[]): readonly string[] =>
    columns.map((column) => column.toUpperCase());

  test("edits version columns and drops an emptied list", () => {
    expect(
      subjectColumnsEdited(
        { type: "post", versions: { columns: ["a"] } },
        upper,
      ).versions,
    ).toEqual({ columns: ["A"] });
    expect(
      subjectColumnsEdited(
        { type: "post", versions: { columns: ["a"] } },
        () => [],
      ).versions,
    ).toEqual({});
    expect(
      subjectColumnsEdited({ type: "post", versions: true }, upper).versions,
    ).toBe(true);
  });

  test("keeps rank, renames its group, and falls back to plain rank", () => {
    expect(
      subjectColumnsEdited({ type: "post", rank: { group: "g" } }, upper).rank,
    ).toEqual({ group: "G" });
    expect(
      subjectColumnsEdited({ type: "post", rank: { group: "g" } }, () => [])
        .rank,
    ).toBe(true);
    expect(subjectColumnsEdited({ type: "post", rank: true }, upper).rank).toBe(
      true,
    );
  });
});

describe("subjectTypeError", () => {
  const design = {
    appTables: {
      posts: { columns: {}, subject: { type: "post" } },
      notes: { columns: {} },
    },
  };

  test("accepts a free type and refuses a taken or malformed one", () => {
    expect(subjectTypeError(design, "notes", "note")).toBeUndefined();
    expect(subjectTypeError(design, "posts", "post")).toBeUndefined();
    expect(subjectTypeError(design, "notes", "post")).toMatch(/posts/u);
    expect(subjectTypeError(design, "notes", "Bad")).toBeDefined();
  });
});

describe("eventsColumnsEdited", () => {
  test("renames the payload columns and drops an emptied list", () => {
    expect(eventsColumnsEdited(true, () => [])).toBe(true);
    expect(
      eventsColumnsEdited({ include: ["a"] }, (c) => c.map((x) => `${x}2`)),
    ).toEqual({ include: ["a2"] });
    expect(eventsColumnsEdited({ include: ["a"] }, () => [])).toEqual({});
  });
});
