import type { ModuleContext } from "./context.ts";

import { sqlString } from "../core/template.ts";
import { registeredIdMatches, registeredSubjects } from "./subject-registry.ts";

/**
 * SQL that is true when `type`/`id` (text expressions) names a record in
 * `config.subjects` that belongs to tenant `tenant` and that the caller can
 * read through `can_subject`. Types without a tenant column never match.
 * The module must require `subjects`.
 */
export function subjectInTenant(
  ctx: ModuleContext,
  type: string,
  id: string,
  tenant: string,
): string {
  const subjects = registeredSubjects(ctx.subjects).filter(
    (subject) => subject.tenant !== undefined,
  );
  if (subjects.length === 0) return "false";
  const canSubject = ctx.of("subjects").fn("can_subject");
  return `(case ${type}
${subjects
  .map(
    (subject) =>
      `      when ${sqlString(subject.type)} then exists (select 1 from ${subject.qualified} s where ${registeredIdMatches(subject, id)} and s.${subject.tenant ?? ""}::text = ${tenant}::text)`,
  )
  .join("\n")}
      else false
    end and ${canSubject}(${type}, ${id}, 'read'))`;
}

/**
 * SQL for the tenant (as text) of record `type`/`id` in `config.subjects`,
 * or null for an unknown record or type. Reads the table directly, so use
 * it in security definer code after checking the caller.
 */
export function subjectTenant(
  ctx: ModuleContext,
  type: string,
  id: string,
): string {
  const subjects = registeredSubjects(ctx.subjects).filter(
    (subject) => subject.tenant !== undefined,
  );
  if (subjects.length === 0) return "null::text";
  return `(case ${type}
${subjects
  .map(
    (subject) =>
      `      when ${sqlString(subject.type)} then (select s.${subject.tenant ?? ""}::text from ${subject.qualified} s where ${registeredIdMatches(subject, id)})`,
  )
  .join("\n")}
      else null::text
    end)`;
}
