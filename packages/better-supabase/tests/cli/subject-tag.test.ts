import { describe, expect, it } from "vitest";

import { subjectFromTag, subjectTagArgs } from "../../src/cli/subject-tag.ts";
import { parseBsbComment } from "../../src/sql/index.ts";

function args(source: string): Record<string, string | true> {
  const tag = parseBsbComment(`@bsb ${source}`).tags[0];

  if (tag === undefined) {
    throw new Error("No tag.");
  }

  return { ...tag.args };
}

describe("subjectFromTag", () => {
  it("reads every option a tag can carry", () => {
    expect(
      subjectFromTag(
        args(
          'subject id=pk id-type=bigint tenant=false title=name url=/p/{id} scope=project cascade deleted-at=gone search-title=name search-body="a, b" search-description=d search-exclude=hidden rank=pos rank-group=stage versions="name,budget" versions-auto=false can-read=p.read can-write=p.write',
        ),
        "projects",
      ),
    ).toEqual({
      table: "projects",
      id: "pk",
      idType: "bigint",
      tenant: false,
      title: "name",
      url: "/p/{id}",
      scope: "project",
      cascade: true,
      deletedAt: "gone",
      permissions: { read: "p.read", write: "p.write" },
      search: {
        title: "name",
        body: ["a", "b"],
        description: "d",
        exclude: "hidden",
      },
      rank: { column: "pos", group: "stage" },
      versions: { columns: ["name", "budget"], auto: false },
    });
  });

  it("keeps a tenant column, a bare search and a default rank column", () => {
    expect(
      subjectFromTag(
        args("subject tenant=org_id search rank-group=status versions=a"),
        "t",
      ),
    ).toEqual({
      table: "t",
      tenant: "org_id",
      search: {},
      rank: { column: "rank", group: "status" },
      versions: { columns: ["a"], auto: true },
    });
  });

  it("returns only the table for a bare tag", () => {
    expect(subjectFromTag(args("subject"), "t")).toEqual({ table: "t" });
  });
});

describe("subjectTagArgs", () => {
  it("round-trips what a tag can carry", () => {
    const subject = subjectFromTag(
      args(
        'subject type=x tenant=false title=name search-title=name search-body="a,b" rank-group=s versions="a,b" versions-auto=false can-read=k deleted-at=gone cascade id=pk id-type=uuid scope=sc search-description=d search-exclude=e url=/u',
      ),
      "t",
    );

    expect(
      subjectFromTag(subjectTagArgs("t", subject, "t") ?? {}, "t"),
    ).toEqual(subject);
  });

  it("writes a bare search and names a type that differs from the table", () => {
    expect(
      subjectTagArgs("project", { table: "projects", search: {} }, "projects"),
    ).toEqual({ type: "project", search: true });
  });

  it("refuses options a tag has no word for", () => {
    expect(
      subjectTagArgs(
        "t",
        { table: "t", permissions: { read: { owner: "user_id" } } },
        "t",
      ),
    ).toBeUndefined();

    expect(
      subjectTagArgs(
        "t",
        { table: "t", search: { watch: [{ table: "x", key: "k" }] } },
        "t",
      ),
    ).toBeUndefined();

    expect(
      subjectTagArgs(
        "t",
        { table: "t", search: { from: { view: "v", key: "k" } } },
        "t",
      ),
    ).toBeUndefined();
  });
});
