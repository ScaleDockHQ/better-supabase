import { describe, expect, it } from "vitest";

import { columnTagCommentsOf, sameTenantTagsFrom } from "../helpers/facts.ts";

describe("columnTagComments", () => {
  it("keeps the column comments that carry tags", async () => {
    expect(
      await columnTagCommentsOf(`
        comment on column public.tasks.project_id is '@bsb same-tenant';
        comment on column tasks.title is 'Just a note';
        comment on column "billing"."invoices"."customer_id" is 'It''s @bsb same-tenant=false';
      `),
    ).toEqual([
      {
        schema: "public",
        name: "tasks",
        column: "project_id",
        comment: "@bsb same-tenant",
      },
      {
        schema: "billing",
        name: "invoices",
        column: "customer_id",
        comment: "It's @bsb same-tenant=false",
      },
    ]);
  });
});

describe("sameTenantTagsOf", () => {
  const keys = [
    {
      table: "public.tasks",
      columns: ["project_id"],
      references: "public.projects",
      referencedColumns: ["id"],
      deferrable: true,
    },
  ];

  it("turns a tag into an entry on the column's foreign key", async () => {
    const tags = await sameTenantTagsFrom(
      [
        "comment on column public.tasks.project_id is '@bsb same-tenant match=region=region';",
      ],
      ["public"],
      keys,
    );

    expect(tags.skip).toEqual([]);
    expect(tags.entries).toEqual([
      {
        table: "public.tasks",
        column: "project_id",
        references: { table: "public.projects", column: "id" },
        match: { region: "region" },
        deferrable: true,
      },
    ]);
  });

  it("reads tenant, parent-tenant and shared from the tag", async () => {
    const tags = await sameTenantTagsFrom(
      [
        "comment on column public.tasks.project_id is '@bsb same-tenant tenant=org_id parent-tenant=owner_org shared=false';",
      ],
      ["public"],
      keys,
    );

    expect(tags.entries).toEqual([
      {
        table: "public.tasks",
        column: "project_id",
        tenant: "org_id",
        references: {
          table: "public.projects",
          column: "id",
          tenant: "owner_org",
        },
        deferrable: true,
        shared: false,
      },
    ]);
  });

  it("rejects a shared flag that is not true or false", async () => {
    await expect(
      sameTenantTagsFrom(
        [
          "comment on column public.tasks.project_id is '@bsb same-tenant shared=maybe';",
        ],
        ["public"],
        keys,
      ),
    ).rejects.toThrow("shared must be true or false");
  });

  it("checks the other columns of a composite key as match pairs", async () => {
    const tags = await sameTenantTagsFrom(
      ["comment on column public.tasks.project_id is '@bsb same-tenant';"],
      ["public"],
      [
        {
          table: "public.tasks",
          columns: ["project_id", "region"],
          references: "public.projects",
          referencedColumns: ["id", "region"],
        },
      ],
    );

    expect(tags.entries).toEqual([
      {
        table: "public.tasks",
        column: "project_id",
        references: { table: "public.projects", column: "id" },
        match: { region: "region" },
      },
    ]);
  });

  it("collects the opt-outs and drops a tag with no foreign key", async () => {
    const tags = await sameTenantTagsFrom(
      [
        "comment on column public.tasks.project_id is '@bsb same-tenant=false';",
        "comment on column public.tasks.title is '@bsb same-tenant';",
      ],
      ["public"],
      keys,
    );

    expect(tags).toEqual({ entries: [], skip: ["public.tasks.project_id"] });
  });
});
