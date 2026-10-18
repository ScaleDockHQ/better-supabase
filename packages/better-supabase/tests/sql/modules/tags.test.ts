import { describe, expect, it } from "vitest";

import { renderModules } from "../../../src/sql/render.ts";
import { upgradePlan } from "../../../src/sql/upgrade.ts";

const sqlOf = (layout: Parameters<typeof renderModules>[1] = {}): string =>
  renderModules(["tags"], layout)
    .filter((file) => file.module === "tags")
    .map((file) => file.contents)
    .join("\n");

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

  it("appends a rank key per tenant and kind, and sets one with rank_tag", () => {
    const sql = sqlOf();
    expect(sql).toContain(`"rank" text collate "C" not null default 'V',`);
    expect(sql).toContain(
      `where t."tenant_id" = create_tag.tenant and t."kind" = create_tag.kind;`,
    );
    expect(sql).toContain("'rank', v_rank");
    expect(sql).toContain(
      `if rank_tag.rank is null or rank_tag.rank !~ '^[0-9A-Za-z]*[1-9A-Za-z]$' then`,
    );
    expect(sql).not.toContain("position");
  });

  it("leaves rank out when an adopted table maps no rank column", () => {
    const sql = sqlOf({
      modules: {
        tags: {
          mode: "adopt",
          tables: { tags: "public.labels", taggings: null },
          columns: { tags: { rank: null } },
        },
      },
    });

    expect(sql).not.toContain("rank_tag");
    expect(sql).not.toContain(`"rank"`);
  });

  it("backfills rank keys in position order when upgrading from version 1", () => {
    const [plan] = upgradePlan([{ module: "tags", version: 1 }]);
    expect(plan).toMatchObject({ module: "tags", from: 1, to: 2 });
    const sql = plan!.steps[0]!.sql;
    expect(sql).toContain(
      `alter table "better_supabase"."tags" add column if not exists "rank" text collate "C";`,
    );
    expect(sql).toContain(
      `row_number() over (partition by "tenant_id", "kind" order by position, "name", "id") as nth`,
    );
    expect(sql).toContain(
      `alter table "better_supabase"."tags" drop column if exists position;`,
    );
  });

  it("limits a subject to its kinds and links rows with tenant and time", () => {
    const sql = sqlOf({
      modules: {
        tags: {
          mode: "adopt",
          tables: { tags: "public.labels", taggings: null },
          columns: { tags: { rank: null } },
          options: {
            subjects: {
              task: {
                table: "public.tasks",
                kinds: ["label", "topic"],
                links: {
                  table: "public.task_labels",
                  subject: "task_id",
                  tag: "label_id",
                  tenant: "org_id",
                  createdAt: "linked_at",
                },
              },
            },
          },
        },
      },
    });

    expect(sql).toContain(`v_kind = any ('{label,topic}'::text[])`);
    expect(sql).toContain(
      `insert into "public"."task_labels" ("task_id", "label_id", "org_id", "linked_at")`,
    );
    expect(sql).toContain("values (tag.subject_id");
    expect(sql).toContain(", tag.tag_id, tag.tenant, now())");
    expect(sql).toContain("TAG_SUBJECT_UNKNOWN");
  });

  it.each([
    ["a string", "label"],
    ["an empty kind", [""]],
    ["a non-string kind", [1]],
  ])("rejects kinds given as %s", (_name, kinds) => {
    expect(() =>
      sqlOf({
        modules: {
          tags: {
            options: { subjects: { task: { table: "public.tasks", kinds } } },
          },
        },
      }),
    ).toThrow("kinds must be a list of strings");
  });

  it("checks tags.apply in the tenant before tag and untag touch a subject", () => {
    const sql = sqlOf();

    const check = (tenant: string): string =>
      `if not (auth.role() = 'service_role' or coalesce(better_supabase.can('tenant', ${tenant}, 'tags.apply'), false) or coalesce(better_supabase.can('tenant', ${tenant}, 'tags.manage'), false)) then`;

    for (const fn of ["tag", "untag"]) {
      const body = sql.slice(sql.indexOf(`"better_supabase"."${fn}"(`));
      const applied = body.indexOf(check(`${fn}.tenant`));

      expect(applied).toBeGreaterThan(-1);
      expect(applied).toBeLessThan(body.indexOf("TAG_SUBJECT_FORBIDDEN"));
    }
  });

  it("indexes taggings by tenant and subject", () => {
    expect(sqlOf()).toContain(
      `create index if not exists "taggings_subject_idx" on "better_supabase"."taggings" ("tenant_id", "subject_type", "subject_id");`,
    );
  });

  it("renders nothing in custom mode", () => {
    expect(sqlOf({ modules: { tags: { mode: "custom" } } })).not.toContain(
      "create_tag",
    );
  });

  it("skips the rank upgrade on an adopted table", () => {
    const [plan] = upgradePlan([{ module: "tags", version: 1 }], {
      modules: {
        tags: {
          mode: "adopt",
          tables: { tags: "public.labels", taggings: null },
        },
      },
    });

    expect(plan?.steps.map((step) => step.sql).join("")).toBe("");
  });
});
