import { describe, expect, it } from "vitest";

import { renderBlocks } from "../app-columns.ts";

const sql = renderBlocks(["projects", "tasks", "outbox"])
  .filter((file) => file.module === "projects")
  .map((file) => file.contents)
  .join("\n");

describe("projects glue module", () => {
  it("posts an update, rolls initiative health and refuses a parent cycle", () => {
    expect(sql).toContain("save_project_update");
    expect(sql).toContain("set_project_health");
    expect(sql).toContain("on_track");
    expect(sql).toContain("with recursive chain");
    expect(sql).toContain("initiative.deleted");
    expect(sql).toContain("initiatives.manage");
  });
});
