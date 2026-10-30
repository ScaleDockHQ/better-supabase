import type { BlockSqlContext } from "../context.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { fail, lockTable, quotedTable, raise, splitTable } from "../shared.ts";
import { subjectIdMatches } from "../subjects.ts";
import { exportOmits } from "./data-lifecycle-credentials.ts";

/** A module table whose rows belong to a record through its subject columns. */
interface SubjectEntry {
  readonly module: string;
  readonly logical: string;
  /** `schema.table`, unquoted, for file names. */
  readonly name: string;
  readonly table: string;
  readonly type: string;
  readonly id: string;
  readonly tenant: string | undefined;
  readonly omit: readonly string[];
}

/**
 * The tables a record export reads: every installed module's table with a
 * `lifecycle` entry that is exported and has `subjectType` and `subjectId`
 * columns.
 */
function subjectEntries(ctx: BlockSqlContext): readonly SubjectEntry[] {
  const list: SubjectEntry[] = [];
  const omits = tableOmits(ctx);

  for (const module of ctx.installedModules) {
    const of = ctx.of(module);

    for (const [logical, spec] of Object.entries(of.names.tables)) {
      const lifecycle = spec.lifecycle;

      if (
        lifecycle === undefined ||
        lifecycle.export === false ||
        !of.hasTable(logical) ||
        !Object.hasOwn(spec.columns, "subjectType") ||
        !Object.hasOwn(spec.columns, "subjectId") ||
        !of.has(logical, "subjectType") ||
        !of.has(logical, "subjectId") ||
        unusedSubject(of, logical, spec.app?.unused)
      ) {
        continue;
      }

      const { schema, name } = of.tableName(logical);
      const tenant = lifecycle.tenant;

      list.push({
        module,
        logical,
        name: `${schema}.${name}`,
        table: of.table(logical),
        type: of.col(logical, "subjectType"),
        id: of.col(logical, "subjectId"),
        tenant:
          tenant !== undefined &&
          Object.hasOwn(spec.columns, tenant) &&
          of.has(logical, tenant)
            ? of.col(logical, tenant)
            : undefined,
        omit: omits.get(`${schema}.${name}`) ?? [],
      });
    }
  }

  return list;
}

/**
 * Whether a table the module creates leaves its subject columns out: a
 * feature-gated column stays mapped even when the module doesn't create it.
 */
function unusedSubject(
  of: BlockSqlContext,
  logical: string,
  unused: ((ctx: BlockSqlContext) => readonly string[]) | undefined,
): boolean {
  if (unused === undefined || !of.owns(logical)) {
    return false;
  }

  const columns = unused(of);

  return columns.includes("subjectType") || columns.includes("subjectId");
}

/**
 * The columns each installed module table's exports leave out, by
 * `schema.table`.
 */
function tableOmits(
  ctx: BlockSqlContext,
): ReadonlyMap<string, readonly string[]> {
  const omits = new Map<string, readonly string[]>();

  for (const module of ctx.installedModules) {
    const of = ctx.of(module);

    for (const [logical, spec] of Object.entries(of.names.tables)) {
      if (spec.lifecycle === undefined || !of.hasTable(logical)) {
        continue;
      }

      const { schema, name } = of.tableName(logical);

      const omit = exportOmits(spec.lifecycle)
        .filter(
          (column) =>
            Object.hasOwn(spec.columns, column) && of.has(logical, column),
        )
        .map((column) => of.col(logical, column).replaceAll('"', ""));

      if (omit.length > 0) {
        omits.set(`${schema}.${name}`, omit);
      }
    }
  }

  return omits;
}

/** Whether the exports table has the columns a record export writes. */
export function subjectExportsOn(ctx: BlockSqlContext): boolean {
  return ctx.has("exports", "subjectType") && ctx.has("exports", "subjectId");
}

/**
 * The record columns of an owned exports table and the one check that ties each
 * subject to its columns, replacing the checks earlier versions created inline
 * with generated names.
 */
export function recordColumnsSql(ctx: BlockSqlContext): string {
  if (!ctx.owns("exports")) {
    return "";
  }

  const e = ctx.table("exports");
  const ce = (logical: string): string => ctx.col("exports", logical);
  const name = ctx.tableName("exports").name;

  const legacy = ["subject_check", "check", "check1"].map(
    (suffix) =>
      `alter table ${e} drop constraint if exists ${sqlIdent(`${name}_${suffix}`)};`,
  );

  const check = sqlIdent(`bsb_${name}_subject`);
  const records = subjectExportsOn(ctx);

  const unset = records
    ? ` and ${ce("subjectType")} is null and ${ce("subjectId")} is null`
    : "";

  const columns = records
    ? `alter table ${e} add column if not exists ${ce("subjectType")} text;
alter table ${e} add column if not exists ${ce("subjectId")} text;
`
    : "";

  const record = records
    ? `
  when 'record' then ${ce("subjectType")} is not null and ${ce("subjectId")} is not null and ${ce("user")} is null`
    : "";

  const formatted = ctx.has("exports", "format");

  const formatColumn = formatted
    ? `alter table ${e} add column if not exists ${ce("format")} text;
`
    : "";

  const formatCheck = formatted
    ? `alter table ${e} drop constraint if exists ${sqlIdent(`bsb_${name}_format`)};
alter table ${e} add constraint ${sqlIdent(`bsb_${name}_format`)} check (${ce("format")} is null or ${ce("format")} in ('ndjson', 'csv'));
`
    : "";

  const index = records
    ? `create unique index if not exists ${sqlIdent(`${name}_open_record_idx`)} on ${e} (${ce("subjectType")}, ${ce("subjectId")}, ${ce("requestedBy")}) where ${ce("status")} in ('pending', 'running') and ${ce("subject")} = 'record';
`
    : "";

  return `${columns}${formatColumn}${legacy.join("\n")}
alter table ${e} drop constraint if exists ${check};
alter table ${e} add constraint ${check} check (case ${ce("subject")}
  when 'user' then ${ce("user")} is not null and ${ce("tenant")} is null${unset}
  when 'organization' then ${ce("tenant")} is not null and ${ce("user")} is null${unset}${record}
  else false
end);
${formatCheck}${index}`;
}

interface SubjectExportParts {
  readonly exportJson: (row: string) => string;
  readonly requestedEvent: string;
  readonly can: (tenant: string) => string;
}

const omitted = (omit: readonly string[]): string =>
  omit.length === 0
    ? ""
    : ` - array[${omit.map((column) => sqlString(column)).join(", ")}]::text[]`;

/**
 * The record's own row, then its table's `<table>_reveal` over it as the
 * caller, so encrypted columns come back decrypted and `auditReads` logs the
 * read.
 */
function recordBranch(
  ctx: BlockSqlContext,
  type: string,
  omits: ReadonlyMap<string, readonly string[]>,
): string {
  const subject = ctx.subjects[type]!;
  const [schema, table] = splitTable(subject.table);
  const omit = omits.get(`${schema}.${table}`) ?? [];

  const tenant =
    subject.tenant === false
      ? "null"
      : `s.${sqlIdent(subject.tenant ?? ctx.naming.rename("organization_id"))}`;

  const match = subjectIdMatches(
    {
      table: subject.table,
      ...(subject.id === undefined ? {} : { id: subject.id }),
      ...(subject.idType === undefined ? {} : { idType: subject.idType }),
      extra: {},
    },
    "request_subject_export.subject_id",
  );

  return `when ${sqlString(type)} then
      select to_jsonb(s.*)${omitted(omit)}, ${tenant} into v_record, v_tenant
      from ${quotedTable(subject.table)} s where ${match};
      v_name := ${sqlString(`${schema}.${table}`)};
      v_reveal := ${sqlString(`${table}_reveal`)};
      v_reveal_schema := ${sqlString(schema)};`;
}

/** The SQL that adds one module table's rows to `v_parts`. */
function entrySql(ctx: BlockSqlContext, entry: SubjectEntry): string {
  const tenant =
    entry.tenant === undefined
      ? ""
      : ` and (v_tenant is null or t.${entry.tenant}::text = v_tenant::text)`;

  const where = `t.${entry.type}::text = request_subject_export.subject_type and t.${entry.id}::text = request_subject_export.subject_id${tenant}`;

  // Custom field values decrypt through read_field_values as the caller, which
  // also leaves out the fields the caller may not read.
  if (entry.module === "custom-fields" && entry.logical === "values") {
    const fields = ctx.of("custom-fields");
    const text = fields.col("values", "valueText").replaceAll('"', "");
    const id = fields.col("values", "id");

    return `if v_tenant is not null then
    v_fields := coalesce(${fields.fn("read_field_values")}(v_tenant, request_subject_export.subject_type, request_subject_export.subject_id), '[]'::jsonb);
    select coalesce(jsonb_agg(((to_jsonb(t.*)${omitted(entry.omit)}) || jsonb_build_object(${sqlString(text)}, f.value ->> 'text')) order by t.ctid), '[]'::jsonb) into v_rows
    from ${entry.table} t
    join jsonb_array_elements(v_fields) f on f.value ->> 'id' = t.${id}::text
    where ${where};
    if jsonb_array_length(v_rows) > 0 then
      v_parts := v_parts || jsonb_build_object(${sqlString(entry.name)}, v_rows);
    end if;
  end if;`;
  }

  return `select coalesce(jsonb_agg((to_jsonb(t.*)${omitted(entry.omit)}) order by t.ctid), '[]'::jsonb) into v_rows
  from ${entry.table} t where ${where};
  if jsonb_array_length(v_rows) > 0 then
    v_parts := v_parts || jsonb_build_object(${sqlString(entry.name)}, v_rows);
  end if;`;
}

/**
 * The private table that holds a record export's rows until the export job
 * writes them, and `request_subject_export`. Empty when the exports table lacks
 * the subject columns.
 */
export function subjectExportSql(
  ctx: BlockSqlContext,
  parts: SubjectExportParts,
): string {
  if (!subjectExportsOn(ctx)) {
    return `
create or replace function ${ctx.fn("request_subject_export")}(subject_type text, subject_id text, format text default 'ndjson')
returns jsonb
language plpgsql
set search_path = ''
as $$
begin
  ${fail("DATA_EXPORT_SUBJECT", "The exports table has no subject_type and subject_id columns", "0A000")}
end;
$$;
revoke execute on function ${ctx.fn("request_subject_export")}(text, text, text) from public, anon;
grant execute on function ${ctx.fn("request_subject_export")}(text, text, text) to authenticated, service_role;
`;
  }

  const id = ctx.idType;
  const e = ctx.table("exports");
  const c = ctx.table("contents");
  const ce = (logical: string): string => ctx.col("exports", logical);
  const cc = (logical: string): string => ctx.col("contents", logical);
  const fn = ctx.fn("request_subject_export");
  const formatted = ctx.has("exports", "format");

  const types = Object.keys(ctx.subjects);
  const omits = tableOmits(ctx);

  const lookup =
    types.length === 0
      ? fail("DATA_EXPORT_SUBJECT", "No record type can be exported", "22023")
      : `case request_subject_export.subject_type
    ${types.map((type) => recordBranch(ctx, type, omits)).join("\n    ")}
    else
      ${fail("DATA_EXPORT_SUBJECT", "subject_type is not a record type in config.subjects", "22023")}
  end case;`;

  const managed = ctx.installed("subjects")
    ? types.filter((type) =>
        Object.hasOwn(ctx.subjects[type]?.permissions ?? {}, "manage"),
      )
    : [];

  const manage =
    managed.length === 0
      ? ""
      : ` or (request_subject_export.subject_type in (${managed.map((type) => sqlString(type)).join(", ")}) and coalesce(${ctx.of("subjects").fn("can_subject")}(request_subject_export.subject_type, request_subject_export.subject_id, 'manage'), false))`;

  const entries = subjectEntries(ctx);
  const fields = entries.some((entry) => entry.module === "custom-fields");

  return `
-- A record export's rows, from request_subject_export until the export job
-- writes them: parts maps each file name to its rows.
create table if not exists ${c} (
  ${cc("export")} uuid primary key references ${e} (${ce("id")}) on delete cascade,
  ${cc("parts")} jsonb not null default '{}'::jsonb
);
${lockTable(c)}

-- One record's data (subject 'record'): its own row, decrypted through its
-- table's reveal function as the caller, and every installed module's rows
-- attached to it. Needs the export permission in the record's tenant or the
-- record's manage action. An open export of the record by the caller is
-- returned instead of a second one.
create or replace function ${fn}(subject_type text, subject_id text, format text default 'ndjson')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${e};
  v_tenant ${id};
  v_record jsonb;
  v_name text;
  v_reveal text;
  v_reveal_schema text;
  v_proc text;
  v_arg text;
  v_sealed text[];
  v_plain jsonb;
  v_rows jsonb;${fields ? "\n  v_fields jsonb;" : ""}
  v_parts jsonb := '{}'::jsonb;
begin
  if auth.uid() is null then
    ${fail("DATA_EXPORT_FORBIDDEN", "Sign in to export data")}
  end if;
  if request_subject_export.format is null or request_subject_export.format not in ('ndjson', 'csv') then
    ${fail("DATA_EXPORT_FORMAT", "format must be ndjson or csv", "22023")}
  end if;
  ${lookup}
  if v_record is null or not ((v_tenant is not null and ${parts.can("v_tenant")})${manage}) then
    ${fail("DATA_EXPORT_FORBIDDEN", "You may not export this record")}
  end if;
  select * into v_row from ${e} x
  where x.${ce("subject")} = 'record' and x.${ce("subjectType")} = request_subject_export.subject_type
    and x.${ce("subjectId")} = request_subject_export.subject_id and x.${ce("requestedBy")} = auth.uid()
    and x.${ce("status")} in ('pending', 'running');
  if v_row.${ce("id")} is not null then
    return ${parts.exportJson("v_row")};
  end if;
  -- Only the owner's reveal function, so one another role created never runs
  -- with this function's rights.
  select pg_catalog.format('%I.%I', n.nspname, p.proname), pg_catalog.format_type(p.proargtypes[0], null),
    array(select a.name from unnest(p.proargnames, p.proargmodes::text[]) with ordinality a(name, mode, n)
      where a.mode = 't' order by a.n offset 1)
  into v_proc, v_arg, v_sealed
  from pg_catalog.pg_proc p
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  where n.nspname = v_reveal_schema and p.proname = v_reveal and p.pronargs = 1
    and p.proowner = (select r.oid from pg_catalog.pg_roles r where r.rolname = current_user)
  limit 1;
  -- The stored ciphertext never leaves: a caller the reveal returns no row
  -- for gets the record without its encrypted columns.
  if v_proc is not null then
    execute format('select to_jsonb(r.*) from %s(array[$1]::%s) r', v_proc, v_arg) into v_plain
    using request_subject_export.subject_id;
    v_record := (v_record - coalesce(v_sealed, '{}'::text[])) || coalesce(v_plain, '{}'::jsonb);
  end if;
  v_parts := jsonb_build_object(v_name, jsonb_build_array(v_record));
  ${entries.map((entry) => entrySql(ctx, entry)).join("\n  ")}
  insert into ${e} (${ce("subject")}, ${ce("tenant")}, ${ce("subjectType")}, ${ce("subjectId")}${formatted ? `, ${ce("format")}` : ""})
  values ('record', v_tenant, request_subject_export.subject_type, request_subject_export.subject_id${formatted ? ", request_subject_export.format" : ""})
  returning * into v_row;
  insert into ${c} (${cc("export")}, ${cc("parts")}) values (v_row.${ce("id")}, v_parts);
  ${parts.requestedEvent}
  return ${parts.exportJson("v_row")};
end;
$$;
revoke execute on function ${fn}(text, text, text) from public, anon;
grant execute on function ${fn}(text, text, text) to authenticated, service_role;
`;
}

/** The file names of a record export, for `claim_data_export`. */
export function subjectExportTables(ctx: BlockSqlContext, row: string): string {
  const c = ctx.table("contents");
  const cc = (logical: string): string => ctx.col("contents", logical);

  return `(select coalesce(jsonb_agg(k.key order by k.key), '[]'::jsonb)
      from ${c} c, jsonb_object_keys(c.${cc("parts")}) k(key)
      where c.${cc("export")} = ${row}.${ctx.col("exports", "id")})`;
}

/**
 * The page of a record export's rows `data_export_rows` returns: `after` is the
 * offset into the stored rows.
 */
export function subjectExportRows(ctx: BlockSqlContext): string {
  if (!subjectExportsOn(ctx)) {
    return "";
  }

  const c = ctx.table("contents");
  const cc = (logical: string): string => ctx.col("contents", logical);
  const size = "greatest(1, least(data_export_rows.page_size, 10000))";

  return `if v_row.${ctx.col("exports", "subject")}::text = 'record' then
    select c.${cc("parts")} -> data_export_rows.table_name into v_rows
    from ${c} c where c.${cc("export")} = v_row.${ctx.col("exports", "id")};
    if v_rows is null or jsonb_typeof(v_rows) <> 'array' then
      ${raise("The export has no table %", "22023", "DATA_EXPORT_TABLE", "data_export_rows.table_name")}
    end if;
    v_offset := coalesce(nullif(data_export_rows.after, '')::integer, 0);
    return jsonb_build_object(
      'rows', (select coalesce(jsonb_agg(r.value order by r.n), '[]'::jsonb)
        from jsonb_array_elements(v_rows) with ordinality r(value, n)
        where r.n > v_offset and r.n <= v_offset + ${size}),
      'after', case when v_offset + ${size} < jsonb_array_length(v_rows) then (v_offset + ${size})::text end
    );
  end if;
  `;
}
