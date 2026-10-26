import type { BlockSqlContext } from "../context.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { asColumnType } from "../column-type.ts";
import { fail } from "../shared.ts";
import { registeredSubjects } from "../subject-registry.ts";
import { lockModuleTable } from "./over-app.ts";

export function optIn(ctx: BlockSqlContext, table: string): boolean {
  return ctx.hasTable(table) && typeof ctx.config.tables[table] === "string";
}

export function choice(
  ctx: BlockSqlContext,
  name: string,
  values: readonly [string, ...string[]],
): string {
  const value = ctx.text(name, values[0]);

  if (!values.includes(value)) {
    throw new TypeError(
      `blocks.${ctx.instance}.options.${name} must be ${values.map((item) => `"${item}"`).join(" or ")}`,
    );
  }

  return value;
}

export function candidateSubjectIdType(
  ctx: BlockSqlContext,
  candidate: string,
): string {
  const subject = registeredSubjects(ctx.subjects, ctx.naming).find(
    (item) => item.type === candidate,
  );

  return subject?.config.idType ?? "text";
}

export function reviewable(
  check: string | undefined,
  editable: string,
  from: string,
): string {
  return check === undefined
    ? `(${editable})`
    : `(${editable} or exists (
    select 1 from ${from} and ${check}))`;
}

export function managerCheck(ctx: BlockSqlContext, employee: boolean): string {
  if (
    !employee ||
    !ctx.has("jobs", "hiringManager") ||
    !ctx.installed("employees")
  ) {
    return "";
  }

  const e = ctx.of("employees");

  return `
  if save_job.attrs ->> 'hiringManagerId' is not null and not exists (
    select 1 from ${e.table("employees")} x
    where x.${e.col("employees", "id")}::text = save_job.attrs ->> 'hiringManagerId' and x.${e.col("employees", "tenant")}::text = save_job.tenant::text) then
    ${fail("HIRING_HIRING_MANAGER_INVALID", "the hiring manager is no employee of this organization", "22023")}
  end if;`;
}

export function scoresTable(ctx: BlockSqlContext, read: string): string {
  const t = ctx.table("scorecardScores");
  const c = (column: string): string => ctx.col("scorecardScores", column);
  const s = (column: string): string => ctx.col("scorecards", column);
  const policy = sqlIdent(`${ctx.tableName("scorecardScores").name}_read`);

  const optional = (logical: string, type: string): string =>
    ctx.has("scorecardScores", logical) ? `\n  ${c(logical)} ${type},` : "";

  return `
create table if not exists ${t} (${optional("tenant", `${ctx.idType} not null`)}
  ${c("scorecard")} uuid not null references ${ctx.table("scorecards")} (${s("id")}) on delete cascade,
  ${c("criterion")} text not null check (length(${c("criterion")}) between 1 and 100),
  ${c("score")} smallint not null check (${c("score")} between 1 and 4),${optional("notes", "text")}
  primary key (${c("scorecard")}, ${c("criterion")})
);
${lockModuleTable(ctx, "scorecardScores", { read: true })}
drop policy if exists ${policy} on ${t};
create policy ${policy} on ${t} for select to authenticated
using (exists (select 1 from ${ctx.table("scorecards")} c where c.${s("id")} = ${t}.${c("scorecard")} and ${ctx.scope.check(`c.${s("tenant")}`, read)}));
`;
}

export function scoresWrite(ctx: BlockSqlContext): string {
  const t = ctx.table("scorecardScores");
  const c = (column: string): string => ctx.col("scorecardScores", column);

  const physical = (column: string): string =>
    ctx.colName("scorecardScores", column);

  const tenant = ctx.has("scorecardScores", "tenant");
  const notes = ctx.has("scorecardScores", "notes");

  return `
  if submit_scorecard.scores is not null then
    if jsonb_typeof(submit_scorecard.scores) <> 'array' then
      ${fail("HIRING_SCORES_INVALID", "scores must be a list of { criterion, score, notes }", "22023")}
    end if;
    delete from ${t} x where x.${c("scorecard")} = v_card.${ctx.col("scorecards", "id")};
    begin
      insert into ${t} (${tenant ? `${c("tenant")}, ` : ""}${c("scorecard")}, ${c("criterion")}, ${c("score")}${notes ? `, ${c("notes")}` : ""})
      select ${tenant ? `v_row.${ctx.col("applications", "tenant")}, ` : ""}v_card.${ctx.col("scorecards", "id")}, ${asColumnType(t, physical("criterion"), "e ->> 'criterion'")}, ${asColumnType(t, physical("score"), "e ->> 'score'")}${notes ? ", e ->> 'notes'" : ""}
      from jsonb_array_elements(submit_scorecard.scores) e;
    exception when data_exception or integrity_constraint_violation then
      ${fail("HIRING_SCORES_INVALID", "each score needs a distinct criterion and a valid score", "22023")}
    end;
  end if;`;
}

export function interviewersTable(ctx: BlockSqlContext, read: string): string {
  const t = ctx.table("interviewers");
  const c = (column: string): string => ctx.col("interviewers", column);
  const v = (column: string): string => ctx.col("interviews", column);
  const name = ctx.tableName("interviewers").name;
  const policy = sqlIdent(`${name}_read`);

  return `
create table if not exists ${t} (${ctx.has("interviewers", "tenant") ? `\n  ${c("tenant")} ${ctx.idType} not null,` : ""}
  ${c("interview")} uuid not null references ${ctx.table("interviews")} (${v("id")}) on delete cascade,
  ${c("user")} uuid not null,
  primary key (${c("interview")}, ${c("user")})
);
create index if not exists ${sqlIdent(`${name}_user_idx`)} on ${t} (${c("user")});
${lockModuleTable(ctx, "interviewers", { read: true })}
drop policy if exists ${policy} on ${t};
create policy ${policy} on ${t} for select to authenticated
using (${c("user")} = (select auth.uid()) or exists (select 1 from ${ctx.table("interviews")} i where i.${v("id")} = ${t}.${c("interview")} and ${ctx.scope.check(`i.${v("tenant")}`, read)}));
`;
}

export function hiringCandidate(
  hiring: BlockSqlContext,
  row: string,
): { readonly type: string; readonly id: string } {
  const id = `${row}.${hiring.col("applications", "candidateId")}`;

  return hiring.has("applications", "candidateType")
    ? { type: `${row}.${hiring.col("applications", "candidateType")}`, id }
    : {
        type: sqlString(hiring.text("candidate", "person")),
        id: `${id}::text`,
      };
}
