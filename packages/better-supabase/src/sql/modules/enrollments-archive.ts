import type { BlockSqlContext } from "../context.ts";

import { fail, userGrant } from "../shared.ts";

interface ProgramLifecycle {
  readonly allowed: (tenant: string, permission: string) => string;
  readonly archivable: boolean;
  readonly forbidden: (message: string) => string;
  readonly manage: string;
  readonly programJson: (row: string) => string;
  readonly programMissing: string;
  readonly programRecord: (
    type: string,
    row: string,
    summary: string,
  ) => string;
  readonly purge: string;
  readonly read: string;
}

/**
 * The program list, archive, restore and purge. An archived program leaves the
 * list and refuses new enrollments and edits; its enrollments stay.
 */
export function programLifecycleFunctions(
  ctx: BlockSqlContext,
  h: ProgramLifecycle,
): string {
  const programs = ctx.table("programs");
  const enrollments = ctx.table("enrollments");
  const p = (column: string): string => ctx.col("programs", column);
  const e = (column: string): string => ctx.col("enrollments", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const { archivable } = h;

  const toggle = (verb: "archive" | "restore"): string => {
    const name = `${verb}_enrollment_program`;
    const archiving = verb === "archive";

    return `create or replace function ${fn(name)}(program_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${programs};
begin
  select * into v_row from ${programs} x where x.${p("id")} = ${name}.program_id for update;
  if v_row.${p("id")} is null then
    ${h.programMissing}
  end if;
  if not ${h.allowed(`v_row.${p("tenant")}`, h.manage)} then
    ${h.forbidden("not allowed to manage enrollment programs")}
  end if;
  if v_row.${p("archivedAt")} is ${archiving ? "not null" : "null"} then
    return ${h.programJson("v_row")};
  end if;
  update ${programs} x set ${p("archivedAt")} = ${archiving ? "now()" : "null"}${ctx.has("programs", "updatedAt") ? `, ${p("updatedAt")} = now()` : ""}
  where x.${p("id")} = v_row.${p("id")}
  returning * into v_row;
  ${h.programRecord(`enrollment_program.${verb}d`, "v_row", `${verb}d an enrollment program`)}
  return ${h.programJson("v_row")};
end;
$$;
${userGrant(`${fn(name)}(uuid)`)}
`;
  };

  return `-- The organization's programs by key; archived ones stay out unless
-- include_archived is true.${archivable ? `\ndrop function if exists ${fn("enrollment_programs")}(${idType});` : ""}
create or replace function ${fn("enrollment_programs")}(tenant ${idType}${archivable ? ", include_archived boolean default false" : ""})
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not ${h.allowed("enrollment_programs.tenant", h.read)} then
    ${h.forbidden("not allowed to read enrollment programs")}
  end if;
  return coalesce((
    select jsonb_agg(${h.programJson("x")} order by x.${p("key")})
    from ${programs} x where x.${p("tenant")} = enrollment_programs.tenant${archivable ? `\n      and (coalesce(enrollment_programs.include_archived, false) or x.${p("archivedAt")} is null)` : ""}
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("enrollment_programs")}(${idType}${archivable ? ", boolean" : ""})`)}
${archivable ? `\n${toggle("archive")}\n${toggle("restore")}` : ""}
-- Deletes a program with its enrollments for good${archivable ? ", once it is archived" : ""}; false when it was already gone.
drop function if exists ${fn("delete_enrollment_program")}(uuid);
create or replace function ${fn("purge_enrollment_program")}(program_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${programs};
begin
  select * into v_row from ${programs} x where x.${p("id")} = purge_enrollment_program.program_id for update;
  if v_row.${p("id")} is null then
    return false;
  end if;
  if not ${h.allowed(`v_row.${p("tenant")}`, h.purge)} then
    ${h.forbidden("not allowed to purge enrollment programs")}
  end if;${
    archivable
      ? `
  if v_row.${p("archivedAt")} is null then
    ${fail("ENROLLMENTS_PROGRAM_NOT_ARCHIVED", "archive the program before purging it", "55000")}
  end if;`
      : ""
  }
  delete from ${enrollments} x where x.${e("tenant")} = v_row.${p("tenant")} and x.${e("program")} = v_row.${p("key")};
  delete from ${programs} x where x.${p("id")} = v_row.${p("id")};
  ${h.programRecord("enrollment_program.purged", "v_row", "purged an enrollment program")}
  return true;
end;
$$;
${userGrant(`${fn("purge_enrollment_program")}(uuid)`)}`;
}
