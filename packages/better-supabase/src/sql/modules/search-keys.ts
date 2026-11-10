import type { BlockSqlLayout } from "../module-types.ts";
import type { RegisteredSubject } from "../subject-registry.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { quotedTable } from "../shared.ts";
import { registeredIdMatches, urlExpression } from "../subject-registry.ts";

/** `schema.table`, with `public` when the config names no schema. */
function qualifiedName(table: string): string {
  return table.includes(".") ? table : `public.${table}`;
}

/**
 * The type the generator already knows for a column: the subject's `idType`, a
 * column the app declares `uuid`, or a column the app's files add. Anything
 * else stays unknown, and a comparison then follows the subject's id type.
 */
export function knownColumnType(
  layout: BlockSqlLayout,
  subject: RegisteredSubject,
  table: string,
  column: string,
): string | undefined {
  const qualified = qualifiedName(table);
  const dot = qualified.indexOf(".");
  const schema = qualified.slice(0, dot);
  const name = qualified.slice(dot + 1);
  const idColumn = subject.config.id ?? "id";

  if (
    subject.schema === schema &&
    subject.table === name &&
    column === idColumn &&
    subject.config.idType !== undefined
  ) {
    return subject.config.idType;
  }

  if (layout.uuidColumns?.[qualified]?.includes(column) === true) {
    return "uuid";
  }

  const declared = layout.appColumns?.[qualified]?.find(
    (entry) => entry.name === column,
  );

  return declared?.type.toLowerCase().replaceAll(/\s+/g, " ").trim();
}

/** `text` and `varchar` compare the same way, so a mismatch is a real one. */
export function sqlTypeKey(type: string): string {
  const flat = type.toLowerCase().replaceAll(/\s+/g, " ").trim();

  if (
    flat === "text" ||
    flat === "varchar" ||
    flat.startsWith("varchar(") ||
    flat === "character varying" ||
    flat.startsWith("character varying(")
  ) {
    return "text";
  }

  return flat.replace(/^(?:public|extensions)\./, "");
}

/**
 * `left = right` on the columns' own type. Both sides unknown, and a subject
 * with no `idType`, stay `::text`. A known mismatch stays `::text` too, and is
 * noted, because a cast to one side's type would not compile.
 */
export function typedEqual(
  leftSql: string,
  leftType: string | undefined,
  rightSql: string,
  rightType: string | undefined,
  where: string,
  subject: RegisteredSubject,
  notes: string[],
): string {
  const left = leftType === undefined ? undefined : sqlTypeKey(leftType);
  const right = rightType === undefined ? undefined : sqlTypeKey(rightType);

  if (left !== undefined && right !== undefined && left !== right) {
    notes.push(
      `-- better-supabase: ${where} compares ${left} with ${right}, so the comparison stays text.`,
    );

    return `${leftSql}::text = ${rightSql}::text`;
  }

  if (
    left === undefined &&
    right === undefined &&
    subject.config.idType === undefined
  ) {
    return `${leftSql}::text = ${rightSql}::text`;
  }

  return `${leftSql} = ${rightSql}`;
}

/** `column in (query)`, with the same type rules as `typedEqual`. */
export function typedIn(
  columnSql: string,
  columnType: string | undefined,
  query: string,
  queryType: string | undefined,
  where: string,
  subject: RegisteredSubject,
  notes: string[],
): string {
  const left = columnType === undefined ? undefined : sqlTypeKey(columnType);
  const right = queryType === undefined ? undefined : sqlTypeKey(queryType);

  const text =
    (left !== undefined && right !== undefined && left !== right) ||
    (left === undefined &&
      right === undefined &&
      subject.config.idType === undefined);

  if (left !== undefined && right !== undefined && left !== right) {
    notes.push(
      `-- better-supabase: ${where} compares ${left} with ${right}, so the comparison stays text.`,
    );
  }

  return text
    ? `${columnSql}::text in (select v.value::text from (${query}) v(value))`
    : `${columnSql} in (${query})`;
}

/** One `when` branch of `search_refresh`, joining a source view on its own type. */
export function refreshBranch(
  subject: RegisteredSubject,
  described: boolean,
  layout: BlockSqlLayout,
  notes: string[],
): string {
  const { config } = subject;
  const title = config.search?.title ?? config.title ?? "";
  const body = config.search?.body ?? [];
  const from = config.search?.from;
  const source = from === undefined ? "s" : "f";

  const bodySql =
    body.length === 0
      ? "null"
      : `nullif(concat_ws(E'\\n', ${body.map((name) => `${source}.${sqlIdent(name)}::text`).join(", ")}), '')`;

  const url =
    config.url === undefined ? "null" : urlExpression(config.url, "s");

  const deleted =
    config.deletedAt === undefined
      ? ""
      : `\n        and s.${sqlIdent(config.deletedAt)} is null`;

  const template =
    typeof config.template === "string"
      ? config.template
      : config.template?.column;

  const templated =
    template === undefined
      ? ""
      : `\n        and s.${sqlIdent(template)} is null`;

  const exclude = config.search?.exclude;

  const excluded =
    exclude === undefined
      ? ""
      : `\n        and (${source}.${sqlIdent(exclude)} is null or ${source}.${sqlIdent(exclude)}::text = 'false')`;

  const description = config.search?.description;

  const subjectIdType =
    config.idType ??
    knownColumnType(
      layout,
      subject,
      `${subject.schema}.${subject.table}`,
      config.id ?? "id",
    );

  const viewKeyType =
    from === undefined
      ? undefined
      : knownColumnType(layout, subject, from.view, from.key);

  const join =
    from === undefined
      ? ""
      : `\n        join ${quotedTable(from.view)} f on ${typedEqual(
          `f.${sqlIdent(from.key)}`,
          viewKeyType,
          `s.${subject.id}`,
          subjectIdType,
          `${subject.type} search.from`,
          subject,
          notes,
        )}`;

  const sourceFrom = from;

  const pushed =
    sourceFrom !== undefined &&
    config.idType !== undefined &&
    (viewKeyType === undefined ||
      sqlTypeKey(viewKeyType) === sqlTypeKey(config.idType))
      ? `\n        and f.${sqlIdent(sourceFrom.key)} = (search_refresh.subject_id)::${config.idType}`
      : "";

  return `    when ${sqlString(subject.type)} then
      select s.${subject.tenant ?? sqlIdent("organization_id")}, ${source}.${sqlIdent(title)}::text, ${bodySql}, ${url}${described ? `, ${description === undefined ? "null" : `${source}.${sqlIdent(description)}::text`}` : ""}
        into v_tenant, v_title, v_body, v_url${described ? ", v_description" : ""}
        from ${subject.qualified} s${join}
        where ${registeredIdMatches(subject, "search_refresh.subject_id")}${pushed}${deleted}${templated}${excluded};
      v_found := found;`;
}
