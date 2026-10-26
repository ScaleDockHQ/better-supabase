import { describe, expect, it } from "vitest";

import type { AnyBlocksConfig } from "../../../src/config/blocks.ts";
import type { BlockSqlLayout } from "../../../src/sql/module-types.ts";

import { renderBlocks } from "../../../src/sql/render.ts";
import { upgradePlan } from "../../../src/sql/upgrade.ts";
import { ownTablesOf } from "../../fixtures/own-tables.ts";

const sqlOf = (layout: Parameters<typeof renderBlocks>[1] = {}): string =>
  renderBlocks(["tags"], layout)
    .filter((file) => file.module === "tags")
    .map((file) => file.contents)
    .join("\n");

const overApp = (modules: AnyBlocksConfig): BlockSqlLayout => ({
  modules,
  ownTables: ownTablesOf(modules),
});

describe("tags module", () => {
  it("deletes a per-subject link row over the app's tags table", () => {
    const sql = renderBlocks(
      ["tags"],
      overApp({
        tags: {
          tables: { tags: "public.organization_tags", taggings: null },
          on: {
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
      }),
    )
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain('delete from "public"."task_tags"');
    expect(sql).not.toContain('delete from "better_supabase"."taggings"');
    expect(sql).not.toMatch(/create table if not exists\s+\(/);
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

  it("leaves rank out when the app's tags table maps no rank column", () => {
    const sql = sqlOf(
      overApp({
        tags: {
          tables: { tags: "public.labels", taggings: null },
          columns: { tags: { rank: null } },
        },
      }),
    );

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
    const sql = sqlOf(
      overApp({
        tags: {
          tables: { tags: "public.labels", taggings: null },
          columns: { tags: { rank: null } },
          on: {
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
      }),
    );

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
        modules: { tags: { on: { task: { table: "public.tasks", kinds } } } },
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

  it("skips the rank upgrade on the app's tags table", () => {
    const [plan] = upgradePlan(
      [{ module: "tags", version: 1 }],
      overApp({ tags: { tables: { tags: "public.labels", taggings: null } } }),
    );

    expect(plan?.steps.map((step) => step.sql).join("")).toBe("");
  });

  it("checks create, update and delete with their own keys, falling back to manage", () => {
    const plain = sqlOf();
    expect(plain).not.toContain("'tags.create'");
    expect(plain.match(/'tags\.manage'/gu)?.length).toBeGreaterThan(3);

    const split = sqlOf({
      modules: {
        tags: {
          permissions: {
            create: "tag.create",
            update: "tag.update",
            delete: "tag.delete",
          },
        },
      },
    });

    expect(split).toContain("create_tag.tenant, 'tag.create'");
    expect(split).toContain("v_tenant, 'tag.update'");
    expect(split).toContain("v_tenant, 'tag.delete'");
  });

  it("takes a caller's slug and a patch that can clear nullable columns", () => {
    expect(sqlOf()).not.toContain("slug text default null");

    const sql = sqlOf({ modules: { tags: { options: { patch: true } } } });
    expect(sql).toContain("slug text default null)");
    expect(sql).toContain("v_slug text := coalesce(create_tag.slug,");
    expect(sql).toContain("hint = 'TAG_SLUG_INVALID'");
    expect(sql).toContain(
      `"color" = case when update_tag.patch ? 'color' then update_tag.patch ->> 'color' else t."color" end`,
    );
    expect(sql).toContain(
      'drop function if exists "better_supabase"."update_tag"(uuid, text, jsonb, jsonb);',
    );
  });

  it("writes a required extra column inside the insert", () => {
    const sql = sqlOf({
      modules: {
        tags: {
          options: { extraColumns: { icon: "text not null", note: "text" } },
        },
      },
    });

    expect(sql).toContain(
      `(jsonb_populate_record(null::"better_supabase"."tags", coalesce(create_tag.fields, '{}'::jsonb)))."icon")`,
    );
    expect(sql).not.toContain(`'{}'::jsonb)))."note"`);
  });

  it("checks the record's tag action when the record declares one", () => {
    const subjects = {
      task: {
        table: "public.tasks",
        permissions: {
          read: "task.read",
          tag: { key: "task.update", owner: "owner_id" },
        },
      },
    };

    const sql = renderBlocks(["subjects", "tags"], { subjects })
      .filter((file) => file.module === "tags")
      .map((file) => file.contents)
      .join("\n");

    expect(sql).toContain(
      `when 'task' then coalesce("better_supabase"."can_subject"(tag.subject_type, tag.subject_id, 'tag'), false)`,
    );
    expect(sql).not.toContain(`can_subject"(subject_tags.subject_type`);
    expect(sqlOf({ subjects })).not.toContain("can_subject");
  });
});
