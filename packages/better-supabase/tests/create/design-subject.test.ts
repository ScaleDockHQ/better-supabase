import { describe, expect, test } from "vitest";

import {
  subjectColumns,
  subjectColumnsEdited,
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
