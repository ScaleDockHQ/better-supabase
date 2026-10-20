import {
  addTable,
  type Design,
  designIssues,
  duplicateTable,
  EMPTY_DESIGN,
  renameColumn,
  setColumn,
} from "better-supabase/create";
import { describe, expect, test } from "vitest";

import {
  featureBlocker,
  installedBlocks,
  RECORD_FEATURES,
  setEvents,
  setFeature,
  tableFeatures,
} from "../../lib/record-features";
import { presetSchema } from "./schema-fixture";

const projects = setColumn(
  addTable(EMPTY_DESIGN, "projects"),
  "projects",
  "name",
  {
    type: "text",
    nullable: false,
  },
);

const { preset: saas, data } = presetSchema("saas");

function info(feature: string) {
  const found = RECORD_FEATURES.find((each) => each.feature === feature);

  if (found === undefined) {
    throw new Error(feature);
  }

  return found;
}

describe("record features", () => {
  test("versions are per table and follow a column rename", () => {
    const on = setFeature(projects, [], "projects", "versions", true);

    expect(on.design.appTables?.["projects"]?.subject?.versions).toBe(true);
    expect(on.blocks).toEqual(["versions"]);

    const listed: Design = {
      ...on.design,
      appTables: {
        projects: {
          ...on.design.appTables?.["projects"],
          subject: { type: "project", versions: { columns: ["name"] } },
        },
      },
    };

    expect(
      renameColumn(listed, "projects", "name", "title").appTables?.["projects"]
        ?.subject?.versions,
    ).toEqual({ columns: ["title"] });

    const off = setFeature(on.design, on.blocks, "projects", "versions", false);

    expect(
      off.design.appTables?.["projects"]?.subject?.versions,
    ).toBeUndefined();
    expect(off.blocks).toEqual(["versions"]);
  });

  test("comments make the table a subject and add the block", () => {
    const next = setFeature(
      projects,
      ["profiles"],
      "projects",
      "comments",
      true,
    );

    expect(next.design.appTables?.["projects"]?.subject).toEqual({
      type: "project",
      title: "name",
    });
    expect(next.blocks).toEqual(["profiles", "comments"]);
  });

  test("search, order and trash set the table's subject keys", () => {
    let design: Design = projects;
    let blocks: readonly string[] = [];

    for (const feature of ["search", "order", "trash"] as const) {
      ({ design, blocks } = setFeature(
        design,
        blocks,
        "projects",
        feature,
        true,
      ));
    }

    expect(design.appTables?.["projects"]?.subject).toEqual({
      type: "project",
      title: "name",
      search: {},
      rank: true,
      softDelete: true,
    });
    expect(blocks).toEqual(["search", "rank", "trash"]);

    const off = setFeature(design, blocks, "projects", "order", false);

    expect(off.design.appTables?.["projects"]?.subject?.rank).toBeUndefined();
    expect(off.blocks).toBe(blocks);
  });

  test("turning a shared feature off removes its block", () => {
    const on = setFeature(projects, ["comments"], "projects", "comments", true);

    expect(
      setFeature(on.design, on.blocks, "projects", "comments", false).blocks,
    ).toEqual([]);
  });

  test("a table has a feature only with its block installed", () => {
    const { design } = setFeature(projects, [], "projects", "search", true);
    const table = design.appTables?.["projects"];

    if (table === undefined) {
      throw new Error("projects");
    }

    expect(tableFeatures(table, new Set())).toEqual([]);
    expect(
      tableFeatures(table, new Set(["search", "comments"])).map(
        (each) => each.feature,
      ),
    ).toEqual(["comments", "search"]);
  });

  test("installedBlocks has the blocks the selected ones require", () => {
    const installed = installedBlocks({ ...saas, blocks: ["search"] });

    expect(installed.has("search")).toBe(true);
    expect(installed.has("subjects")).toBe(true);
  });

  test("a column named like the added one blocks the feature and is an issue", () => {
    const ranked = setColumn(projects, "projects", "rank", { type: "integer" });
    const table = ranked.appTables?.["projects"];

    if (table === undefined) {
      throw new Error("projects");
    }

    expect(featureBlocker(table, info("order"))).toMatch(/Rename the rank/u);
    expect(featureBlocker(table, info("comments"))).toBeUndefined();

    const { design } = setFeature(ranked, [], "projects", "order", true);

    expect(
      designIssues(design, data, saas).map((issue) => issue.message),
    ).toContain(
      "projects.rank clashes with the column its record features add. Rename it.",
    );
  });

  test("renaming the title column follows it, and a copy gets its own type", () => {
    const { design } = setFeature(projects, [], "projects", "search", true);
    const renamed = renameColumn(design, "projects", "name", "label");

    expect(renamed.appTables?.["projects"]?.subject?.title).toBe("label");

    const copy = duplicateTable(renamed, "projects", new Set(["projects"]));

    expect(copy.design.appTables?.[copy.name]?.subject?.type).toBe(
      "projects_copy",
    );
  });

  test("events set the table key and add the outbox block", () => {
    const on = setEvents(projects, ["profiles"], "projects", true);

    expect(on.design.appTables?.["projects"]?.events).toBe(true);
    expect(on.blocks).toEqual(["profiles", "outbox"]);

    const off = setEvents(on.design, on.blocks, "projects", false);

    expect(off.design.appTables?.["projects"]).not.toHaveProperty("events");
    expect(off.blocks).toEqual(["profiles", "outbox"]);
    expect(setEvents(projects, [], "missing", true).design).toBe(projects);
  });

  test("a column rename keeps the events payload columns in step", () => {
    const design: Design = {
      appTables: {
        projects: {
          columns: { name: { type: "text" } },
          events: { include: ["name"] },
        },
      },
    };

    expect(
      renameColumn(design, "projects", "name", "title").appTables?.["projects"]
        ?.events,
    ).toEqual({ include: ["title"] });
  });
});
