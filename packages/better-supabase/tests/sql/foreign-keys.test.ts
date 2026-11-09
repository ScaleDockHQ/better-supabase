import { describe, expect, it } from "vitest";

import { sameTenantLayout } from "../../src/sql/foreign-keys.ts";

describe("sameTenantLayout", () => {
  it("reads inline, table and alter table foreign keys in file order", () => {
    const layout = sameTenantLayout(
      [
        {
          text: `
create table public.parents (id uuid primary key, organization_id uuid);
create table "Public"."Kids" (
  id uuid,
  "Parent" uuid references public.parents,
  other uuid,
  unique (other),
  constraint kids_pk primary key (id),
  constraint kids_other_fk foreign key (other) references public.parents (id)
);
alter table only public.parents add constraint parents_self foreign key (organization_id) references public.parents (id);
create table app.skipped (id uuid references public.parents);
create table public.broken (id uuid references public.parents
`,
        },
      ],
      ["public", "Public"],
    );

    expect(layout.foreignKeys).toEqual([
      {
        table: "Public.Kids",
        columns: ["Parent"],
        references: "public.parents",
        referencedColumns: ["id"],
      },
      {
        table: "Public.Kids",
        columns: ["other"],
        references: "public.parents",
        referencedColumns: ["id"],
      },
      {
        table: "public.parents",
        columns: ["organization_id"],
        references: "public.parents",
        referencedColumns: ["id"],
      },
    ]);
    expect(layout.declaredColumns["public.parents"]).toEqual([
      "id",
      "organization_id",
    ]);
  });

  it("falls back to id for a referenced table the files don't declare", () => {
    expect(
      sameTenantLayout(
        [{ text: "create table public.a (b_id uuid references public.b);" }],
        ["public"],
      ).foreignKeys,
    ).toEqual([
      {
        table: "public.a",
        columns: ["b_id"],
        references: "public.b",
        referencedColumns: ["id"],
      },
    ]);
  });

  it("marks a deferrable key and leaves the others unmarked", () => {
    const { foreignKeys } = sameTenantLayout(
      [
        {
          text: `create table public.a (
  id uuid primary key,
  b_id uuid references public.b deferrable initially deferred,
  c_id uuid references public.c not deferrable,
  d_id uuid,
  constraint a_d foreign key (d_id) references public.d (id) deferrable
);
alter table public.a add constraint a_e foreign key (e_id) references public.e (id) deferrable initially immediate;`,
        },
      ],
      ["public"],
    );

    expect(
      foreignKeys.map((key) => [key.columns[0], key.deferrable === true]),
    ).toEqual([
      ["b_id", true],
      ["c_id", false],
      ["d_id", true],
      ["e_id", true],
    ]);
  });
});
