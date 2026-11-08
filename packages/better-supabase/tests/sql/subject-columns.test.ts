import { describe, expect, it } from "vitest";

import { subjectColumns } from "../../src/sql/subject-registry.ts";

describe("subjectColumns", () => {
  it("names the id and tenant columns by default", () => {
    expect(subjectColumns({ table: "notes" })).toEqual([
      ["id", "id"],
      ["tenant", "organization_id"],
    ]);
    expect(subjectColumns({ table: "notes", tenant: false })).toEqual([
      ["id", "id"],
    ]);
    expect(subjectColumns({ table: "notes" }, "workspace")).toContainEqual([
      "tenant",
      "workspace_id",
    ]);
  });

  it("lists every column the entry names, by config path", () => {
    const columns = subjectColumns({
      table: "notes",
      title: "name",
      deletedAt: "removed_at",
      template: { column: "template_id" },
      url: "/notes/{slug}/{id}",
      rank: { column: "position", group: "list_id" },
      search: {
        title: "name",
        body: ["text"],
        description: "summary",
        exclude: "hidden",
        watch: [
          { table: "comments", key: "note_id", via: "parent_id" },
          { table: "likes", key: "note_id" },
        ],
      },
      permissions: { write: { owner: "author_id" }, read: "notes.read" },
    });

    expect(columns).toEqual(
      expect.arrayContaining([
        ["title", "name"],
        ["deletedAt", "removed_at"],
        ["template.column", "template_id"],
        ["url {slug}", "slug"],
        ["url {id}", "id"],
        ["rank.column", "position"],
        ["rank.group", "list_id"],
        ["search.title", "name"],
        ["search.body", "text"],
        ["search.description", "summary"],
        ["search.exclude", "hidden"],
        ["search.watch.via", "parent_id"],
        ["permissions.write.owner", "author_id"],
      ]),
    );
  });

  it("names a string template column and skips the search columns it borrows", () => {
    const columns = subjectColumns({
      table: "notes",
      template: "is_template",
      search: { from: { view: "note_search", key: "note_id" }, title: "name" },
    });

    expect(columns).toContainEqual(["template", "is_template"]);
    expect(columns.map(([path]) => path)).not.toContain("search.title");
  });
});
