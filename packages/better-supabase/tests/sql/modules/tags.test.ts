import { describe, expect, it } from "vitest";

import { renderModules } from "../../../src/sql/render.ts";

describe("tags module", () => {
  it("deletes a per-subject link row in adopt mode", () => {
    const sql = renderModules(["tags"], {
      modules: {
        tags: {
          mode: "adopt",
          tables: { tags: "public.organization_tags", taggings: null },
          options: {
            subjects: {
              task: {
                table: "public.tasks",
                links: {
                  table: "public.task_tags",
                  subject: "task_id",
                  tag: "tag_id",
                },
              },
            },
          },
        },
      },
    })
      .map((file) => file.contents)
      .join("\n");
    expect(sql).toContain('delete from "public"."task_tags"');
    expect(sql).not.toContain('delete from "better_supabase"."taggings"');
  });
});
