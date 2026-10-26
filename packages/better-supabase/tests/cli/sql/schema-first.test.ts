import { describe, expect, it } from "vitest";

import { splitAppTables } from "../../../src/cli/sql/schema-first.ts";
import { resolveConfig } from "../../../src/config/index.ts";

const SQL = `-- header
-- @bsb-hash sha256:abc

create table if not exists "public"."tasks" (id uuid primary key);

alter table "public"."tasks" enable row level security;

create unique index tasks_id on public.tasks (id);

create policy "tasks_select" on "public"."tasks" for select to authenticated using (true);

create trigger tasks_touch before update on public.tasks for each row execute function touch();

grant select on "public"."tasks" to authenticated;

create or replace view public.task_totals as select 1 as n;

create function public.helper() returns int language sql as $$ select 1; select 2 $$;

comment on table public.tasks is 'Plain text.';
`;

describe("splitAppTables", () => {
  const base = resolveConfig({ blocks: {} }, "/tmp");

  const config = {
    ...base,
    subjects: { work: { table: "tasks", title: "id", url: "/t/{id}" } },
    realtime: {
      ...base.realtime,
      tables: ["tasks"],
      global: ["tasks"],
      users: { tasks: "owner_id" },
    },
    vectorSearch: [
      { table: "public.tasks", column: "embedding", distance: "l2" as const },
    ],
  };

  it("groups statements per table, view and the rest", () => {
    const files = splitAppTables(config, SQL, ["tasks"]);
    const paths = files.map((file) => file.path);

    expect(paths).toEqual([
      "public/tables/tasks.sql",
      "public/views/task_totals.sql",
      "public/_custom/app_tables.sql",
    ]);

    const table = files[0]?.contents ?? "";

    expect(table).not.toContain("@bsb-hash");
    expect(table).toContain("create unique index");
    expect(table).toContain("create trigger");
    expect(table).toContain("grant select");
    expect(table).toContain("Plain text. @bsb subject type=work title=id");
    expect(table).toContain("realtime global user=owner_id");
    expect(table).toContain("vector-search column=embedding distance=l2");
    expect(files[2]?.contents).toContain("select 1; select 2");
  });

  it("omits the custom file when every statement has a home", () => {
    const files = splitAppTables(
      resolveConfig({ blocks: {} }, "/tmp"),
      'create table "public"."a" (id int);',
      ["a"],
    );

    expect(files.map((file) => file.path)).toEqual(["public/tables/a.sql"]);
    expect(files[0]?.contents).not.toContain("@bsb");
  });

  it("handles block comments, empty statements and a missing final semicolon", () => {
    const sql =
      'create table "public"."b" (id int); /* note; here */ ;; $x$ not; sql $x$; -- trailing';

    const files = splitAppTables(
      base,
      `${sql}\ncreate index b_i on public.b (id)`,
      ["b"],
    );

    expect(files[0]?.contents).toContain("create index b_i");
    expect(files.at(-1)?.path).toBe("public/_custom/app_tables.sql");
  });
});
