import type { Subject } from "./subjects.ts";

import { sqlIdent, sqlString } from "../core/template.ts";
import { asColumnType } from "./column-type.ts";

export interface BoundSubject {
  readonly type: string;
  readonly column: string;
  readonly idType: string | undefined;
}

export interface PolymorphicColumns {
  readonly type: string;
  readonly id: string;
}

const COLUMN = /^[a-z_][a-z0-9_]{0,62}$/u;

export function boundSubjects(
  subjects: readonly (readonly [string, Subject])[],
  where: string,
): readonly BoundSubject[] {
  return subjects.flatMap(([type, subject]) => {
    const column = subject.extra["column"];

    if (column === undefined) {
      return [];
    }

    if (typeof column !== "string" || !COLUMN.test(column)) {
      throw new TypeError(`${where}.${type}.column must be a column name`);
    }

    return [{ type, column, idType: subject.idType }];
  });
}

function boundMatch(subject: BoundSubject, alias: string, id: string): string {
  const column = `${alias}.${sqlIdent(subject.column)}`;

  return subject.idType === undefined
    ? `${column}::text = ${id}`
    : `${column} = (${id})::${subject.idType}`;
}

export function boundSubjectMatch(
  bound: readonly BoundSubject[],
  poly: PolymorphicColumns | undefined,
  alias: string,
  type: string,
  id: string,
): string {
  const rest =
    poly === undefined
      ? "false"
      : `${alias}.${poly.type} = ${type} and ${alias}.${poly.id} = ${id}`;

  if (bound.length === 0) {
    return rest;
  }

  return `(case ${type} ${bound
    .map(
      (subject) =>
        `when ${sqlString(subject.type)} then ${boundMatch(subject, alias, id)}`,
    )
    .join(" ")} else ${rest} end)`;
}

export function boundRowSubject(
  bound: readonly BoundSubject[],
  poly: PolymorphicColumns | undefined,
  alias: string,
): { readonly type: string; readonly id: string } {
  const type = `case ${bound
    .map(
      (subject) =>
        `when ${alias}.${sqlIdent(subject.column)} is not null then ${sqlString(subject.type)}`,
    )
    .join(" ")}${poly ? ` else ${alias}.${poly.type}::text` : ""} end`;

  const id = `coalesce(${[
    ...bound.map((subject) => `${alias}.${sqlIdent(subject.column)}::text`),
    ...(poly ? [`${alias}.${poly.id}`] : []),
  ].join(", ")})`;

  return { type, id };
}

export function boundSubjectValues(
  bound: readonly BoundSubject[],
  table: string,
  type: string,
  id: string,
): readonly (readonly [string, string])[] {
  return bound.map((subject) => [
    sqlIdent(subject.column),
    `case when ${type} = ${sqlString(subject.type)} then ${asColumnType(table, subject.column, id)} end`,
  ]);
}
