import { describe, expect, it } from "vitest";

import {
  blockNamesOnAppTables,
  blockPolicyNames,
} from "../../src/sql/app-table-names.ts";
import { declaredUpdatedAtTriggers } from "../../src/sql/schema-scan.ts";

const APP = new Set(["public.organizations"]);

describe("blockPolicyNames", () => {
  it("names one policy per command bsb_<table>_<command>", () => {
    expect([
      ...blockPolicyNames("organizations", [
        { name: "organizations_read", command: "select" },
        { name: "organizations_update", command: "update" },
      ]),
    ]).toStrictEqual([
      ["organizations_read", "bsb_organizations_select"],
      ["organizations_update", "bsb_organizations_update"],
    ]);
  });

  it("keeps the rest of the block's name when a command has more than one", () => {
    expect([
      ...blockPolicyNames("organizations", [
        { name: "organizations_member_select", command: "select" },
        { name: "organizations_platform_select", command: "select" },
      ]),
    ]).toStrictEqual([
      ["organizations_member_select", "bsb_organizations_select_member"],
      ["organizations_platform_select", "bsb_organizations_select_platform"],
    ]);
  });

  it("fits a long name into 63 characters", () => {
    const [[, name]] = [
      ...blockPolicyNames("t".repeat(60), [{ name: "x", command: "select" }]),
    ] as [[string, string]];

    expect(name).toHaveLength(63);
  });
});

describe("blockNamesOnAppTables", () => {
  it("renames the block's policies and their drops on the app's table", () => {
    const sql = `-- members read their organization
drop policy if exists organizations_read on public.organizations;
create policy organizations_read on public.organizations
  for select to authenticated using (true);
drop policy if exists teams_read on public.teams;
create policy teams_read on public.teams for select using (true);`;

    expect(blockNamesOnAppTables(sql, APP))
      .toBe(`-- members read their organization
drop policy if exists bsb_organizations_select on public.organizations;
create policy bsb_organizations_select on public.organizations
  for select to authenticated using (true);
drop policy if exists teams_read on public.teams;
create policy teams_read on public.teams for select using (true);`);
  });

  it("leaves out a drop of a policy the block doesn't create there", () => {
    const sql = `drop policy if exists organizations_select on public.organizations;
create policy bsb_tenant_scope on public.organizations as restrictive using (true);`;

    expect(blockNamesOnAppTables(sql, APP)).toBe(`
create policy bsb_tenant_scope on public.organizations as restrictive using (true);`);
  });

  it("prefixes the block's triggers on the app's table", () => {
    const sql = `drop trigger if exists organizations_slug on public.organizations;
create trigger organizations_slug before insert on public.organizations
  for each row execute function better_supabase.slug();
alter table public.organizations disable trigger organizations_slug;`;

    expect(blockNamesOnAppTables(sql, APP))
      .toBe(`drop trigger if exists bsb_organizations_slug on public.organizations;
create trigger bsb_organizations_slug before insert on public.organizations
  for each row execute function better_supabase.slug();
alter table public.organizations disable trigger bsb_organizations_slug;`);
  });

  it("keeps the app's updated_at trigger instead of adding the block's", () => {
    const sql = `drop trigger if exists bsb_updated_at on public.organizations;
create trigger bsb_updated_at before update on public.organizations
  for each row execute function better_supabase.set_updated_at('updated_at');`;

    expect(
      blockNamesOnAppTables(sql, APP, {
        "public.organizations": "organizations_touch",
      }),
    ).toBe(`drop trigger if exists bsb_updated_at on public.organizations;
-- public.organizations keeps updated_at current with its own trigger organizations_touch.`);
  });

  it("changes nothing without app tables", () => {
    const sql = "create policy a on public.organizations using (true);";

    expect(blockNamesOnAppTables(sql, new Set())).toBe(sql);
  });
});

describe("declaredUpdatedAtTriggers", () => {
  it("finds the update trigger by its function's name or body", () => {
    expect(
      declaredUpdatedAtTriggers(
        [
          {
            text: `create function public.stamp() returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
create trigger organizations_stamp before update on public.organizations
  for each row execute function public.stamp();
create trigger projects_moddate before update on projects
  for each row execute procedure extensions.moddatetime(updated_at);
create trigger tasks_audit after insert on public.tasks
  for each row execute function public.set_updated_at();
create trigger bsb_updated_at before update on public.teams
  for each row execute function better_supabase.set_updated_at();`,
          },
        ],
        ["public"],
      ),
    ).toStrictEqual({
      "public.organizations": "organizations_stamp",
      "public.projects": "projects_moddate",
    });
  });
});
