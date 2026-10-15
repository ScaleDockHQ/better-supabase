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
