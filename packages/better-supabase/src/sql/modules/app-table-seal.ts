import type {
  AppColumnConfig,
  AppTableConfig,
} from "../../config/types/app-tables.ts";
import type { ModuleContext } from "../context.ts";

import { encryptedColumns } from "../../config/app-access.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
import { fail, SERVICE_CALLER } from "../shared.ts";
import { FIELD_CIPHER_PREFIX, fieldKeyOwner } from "./field-encryption.ts";

const SCHEMA = "public";

/** The most ids one `<table>_reveal` call decrypts. */
const APP_REVEAL_LIMIT = 500;

/** An app table as the encryption SQL needs it. */
export interface SealTable {
  readonly name: string;
  readonly config: AppTableConfig;
  readonly ctx: ModuleContext;
  /** The scope column, or `undefined` in `none` scope. */
  readonly scope: { readonly name: string } | undefined;
  /** The rows a caller reaches, as the select policy checks them. */
  readonly own: string;
  /** Whether the session policy guards the table too. */
  readonly sessionPolicy: boolean;
}

const qualified = (table: string): string =>
  `${sqlIdent(SCHEMA)}.${sqlIdent(table)}`;

/** The reveal function of `table`, quoted. */
const revealFunction = (table: string): string => qualified(`${table}_reveal`);

/** The SQL type of the table's id. */
const idType = (config: AppTableConfig): string =>
  config.id === "bigint" ? "bigint" : "uuid";

/** The SQL that names the data key a row of `table` is encrypted with. */
function ownerOf(table: SealTable, row: string): string {
  const scope = table.scope;

  if (scope === undefined) {
    return fieldKeyOwner("none", "");
  }

  return fieldKeyOwner(
    table.ctx.scope.kind === "user" ? "user" : "tenant",
    `${row}.${sqlIdent(scope.name)}`,
  );
}

/** Throws unless the blocks an encrypted table needs are installed. */
export function checkSealBlocks(table: SealTable): void {
  if (encryptedColumns(table.config).length === 0) {
    return;
  }

  if (!table.ctx.installed("field-encryption")) {
    throw new TypeError(
      `appTables.${table.name}: an encrypted column needs the field-encryption block, which keeps its keys in Vault; add it to blocks`,
    );
  }

  if (table.config.auditReads === true && !table.ctx.installed("audit")) {
    throw new TypeError(
      `appTables.${table.name}.auditReads needs the audit block; add it to blocks`,
    );
  }
}

/**
 * The plaintext checks of an encrypted column, which can't be table checks: the
 * table only holds ciphertext.
 */
function plainChecks(
  column: AppColumnConfig,
  checks: (column: AppColumnConfig, value: string) => readonly string[],
  value: string,
): readonly string[] {
  return checks(
    column,
    column.type === "text" ? value : `(${value})::${column.type}`,
  );
}

/**
 * The `before insert or update` trigger that checks and encrypts each encrypted
 * column, and encrypts it again with the new owner's key when a row moves to
 * another tenant or user. A value that is already ciphertext and didn't change
 * stays as it is.
 */
export function sealSql(
  table: SealTable,
  checks: (column: AppColumnConfig, value: string) => readonly string[],
): string {
  const columns = encryptedColumns(table.config);

  if (columns.length === 0) {
    return "";
  }

  const { ctx } = table;
  const encryption = ctx.of("field-encryption");
  const key = encryption.fn("field_key");
  const seal = encryption.fn("field_seal");
  const open = encryption.fn("field_open");
  const fn = ctx.fn(`${table.name}_seal`);
  const trigger = ctx.trigger("seal_fields");
  const target = qualified(table.name);
  const prefix = sqlString(FIELD_CIPHER_PREFIX);
  const width = String(FIELD_CIPHER_PREFIX.length);

  const branch = (name: string): string => {
    const column = table.config.columns?.[name] ?? { type: "text" };
    const value = `new.${sqlIdent(name)}`;
    const conditions = plainChecks(column, checks, value);

    const normalize =
      column.type === "text"
        ? ""
        : `\n    ${value} := ((${value})::${column.type})::text;`;

    const check =
      conditions.length === 0
        ? ""
        : `\n    if not (${conditions.join(" and ")}) then
      raise exception 'new row for relation "%" violates check constraint "%"', ${sqlString(table.name)}, ${sqlString(`${table.name}_${name}_check`)}
        using errcode = '23514';
    end if;`;

    const fresh = `case when tg_op = 'INSERT' then true else ${value} is distinct from old.${sqlIdent(name)} end`;

    return `  if ${value} is not null and (${fresh} or left(${value}, ${width}) <> ${prefix}) then${normalize}${check}
    v_key := coalesce(v_key, ${key}(v_owner, true));
    ${value} := ${seal}(v_key, ${value});
  elsif ${value} is not null and v_moved then
    v_key := coalesce(v_key, ${key}(v_owner, true));
    ${value} := ${seal}(v_key, ${open}(${key}(v_old_owner, false), ${value}));
  end if;`;
  };

  const watched = [...(table.scope ? [table.scope.name] : []), ...columns].map(
    (column) => sqlIdent(column),
  );

  return `-- Encrypts ${columns.join(", ")} with the row's data key before the row is written.
create or replace function ${fn}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner text := ${ownerOf(table, "new")};
  v_old_owner text;
  v_moved boolean := false;
  v_key text;
begin
  if tg_op = 'UPDATE' then
    v_old_owner := ${ownerOf(table, "old")};
    v_moved := v_owner is distinct from v_old_owner;
  end if;
${columns.map((name) => branch(name)).join("\n")}
  return new;
end;
$$;
revoke all on function ${fn}() from public, anon, authenticated;
drop trigger if exists ${trigger} on ${target};
create trigger ${trigger} before insert or update of ${watched.join(", ")} on ${target}
  for each row execute function ${fn}();`;
}

/**
 * `public.<table>_reveal(ids)`: the id and the decrypted encrypted columns of
 * each row the caller reaches, at most `APP_REVEAL_LIMIT` per call. It loads
 * each owner's key once. A column with `access: "server"` decrypts for the
 * service role only. With `auditReads`, it writes one audit entry per tenant
 * per call that names the rows it returned. The decrypting `security definer`
 * function lives in `better_supabase`, which PostgREST doesn't expose, and the
 * `public` function is a `security invoker` wrapper around it.
 */
export function revealSql(table: SealTable): string {
  const columns = encryptedColumns(table.config);

  if (columns.length === 0) {
    return "";
  }

  const { ctx } = table;
  const encryption = ctx.of("field-encryption");
  const fn = ctx.fn(`${table.name}_reveal`);
  const wrapper = revealFunction(table.name);
  const id = idType(table.config);
  const target = qualified(table.name);
  const ids = `${ctx.fnName(`${table.name}_reveal`)}.ids`;

  const reach = [
    table.own,
    ...(table.sessionPolicy
      ? ["(select better_supabase.session_active())"]
      : []),
  ].join(" and ");

  const filter = `t.id = any (${ids}) and (v_service or (${reach}))`;

  const outputs = columns.map((name) => {
    const column = table.config.columns?.[name] ?? { type: "text" };

    return `${sqlIdent(name)} ${column.type}`;
  });

  const decrypted = columns.map((name) => {
    const column = table.config.columns?.[name] ?? { type: "text" };
    const plain = `(${encryption.fn("field_open")}(k.bsb_key, r.${sqlIdent(name)}))::${column.type}`;

    return column.access === "server"
      ? `case when v_service then ${plain} end`
      : plain;
  });

  return `-- Decrypts ${columns.join(", ")} for the rows the caller reaches, as the table's policies do.
create or replace function ${fn}(ids ${id}[])
returns table (id ${id}, ${outputs.join(", ")})
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_service boolean := ${SERVICE_CALLER};${table.config.auditReads === true ? "\n  v_read record;" : ""}
begin
  if (select auth.uid()) is null and not v_service then
    ${fail("APP_REVEAL_FORBIDDEN", `only signed-in users and the service role reveal ${table.name}`)}
  end if;
  if coalesce(cardinality(${ids}), 0) > ${String(APP_REVEAL_LIMIT)} then
    ${fail("APP_REVEAL_TOO_MANY", `reveal at most ${String(APP_REVEAL_LIMIT)} rows of ${table.name} per call`, "22023")}
  end if;${auditSql(table, columns, filter)}
  return query
    with r as materialized (
      select t.id, ${ownerOf(table, "t")} as bsb_owner, ${columns.map((name) => `t.${sqlIdent(name)}`).join(", ")}
      from ${target} t
      where ${filter}
    ),
    k as materialized (
      select o.bsb_owner, ${encryption.fn("field_key")}(o.bsb_owner, false) as bsb_key
      from (select distinct r.bsb_owner from r) o
    )
    select r.id, ${decrypted.join(", ")}
    from r join k on k.bsb_owner = r.bsb_owner;
end;
$$;
revoke execute on function ${fn}(${id}[]) from public, anon;
grant execute on function ${fn}(${id}[]) to authenticated, service_role;
-- The API entry point for ${fn}; the definer function stays out of the exposed schemas.
create or replace function ${wrapper}(ids ${id}[])
returns table (id ${id}, ${outputs.join(", ")})
language sql
security invoker
set search_path = ''
as $$
  select * from ${fn}(ids);
$$;
revoke execute on function ${wrapper}(${id}[]) from public, anon;
grant execute on function ${wrapper}(${id}[]) to authenticated, service_role;`;
}

/** The audit entries of one reveal call: one per tenant, naming its rows. */
function auditSql(
  table: SealTable,
  columns: readonly string[],
  filter: string,
): string {
  if (table.config.auditReads !== true) {
    return "";
  }

  const { ctx } = table;

  const tenant =
    ctx.scope.kind === "tenant" && table.scope
      ? `t.${sqlIdent(table.scope.name)}`
      : "null";

  const base = table.config.subject?.type ?? table.name;

  const entry = ctx.audit({
    type: `${base}.viewed`,
    payload: `jsonb_build_object('ids', v_read.ids, 'columns', ${sqlString(JSON.stringify(columns))}::jsonb)`,
    subject: `${sqlString(`${table.name.replaceAll("_", "-")}/`)} || (v_read.ids ->> 0)`,
    ...(tenant === "null" ? {} : { tenant: "v_read.tenant" }),
    audit: {
      category: "read",
      targetType: base,
      recordId:
        "case when jsonb_array_length(v_read.ids) = 1 then v_read.ids ->> 0 end",
      summary: `'Revealed ' || jsonb_array_length(v_read.ids)::text || ' ' || ${sqlString(base)} || ' record(s)'`,
    },
  });

  return `
  for v_read in
    select ${tenant} as tenant, jsonb_agg(t.id order by t.id) as ids
    from ${qualified(table.name)} t
    where ${filter}
    group by 1
  loop
    ${entry}
  end loop;`;
}

/** The pgTAP checks of an encrypted table, by where `testSql` runs them. */
export interface SealChecks {
  /** Run as the table owner, before any row exists. */
  readonly static: readonly string[];
  /** Run as the table owner after the row of another tenant is inserted. */
  readonly seeded: readonly string[];
  /** Run as a signed-in user outside the seeded row's scope. */
  readonly behaviour: readonly string[];
}

const REVEAL_IDS = "bsb.app_reveal_ids";

/** Fixed plaintexts for the types `sampleValue` fills with a random value. */
const FIXED_SAMPLES: Partial<Record<AppColumnConfig["type"], string>> = {
  uuid: "'00000000-0000-4000-8000-0000000000e1'::uuid",
  timestamptz: "'2026-01-01 00:00:00+00'::timestamptz",
  date: "'2026-01-01'::date",
};

/** A fixed plaintext for an encrypted column, so the test can compare it. */
function plainSample(
  column: AppColumnConfig,
  sample: (column: AppColumnConfig) => string | null | undefined,
): string {
  const { default: _default, identity: _identity, ...rest } = column;

  return (
    FIXED_SAMPLES[column.type] ?? sample({ ...rest, nullable: false }) ?? "null"
  );
}

/**
 * The pgTAP checks that the table stores ciphertext, that the service role
 * reveals the plaintext and that anon and a signed-in user of another tenant
 * reveal nothing. `seeded` is `false` when no row of another tenant can be
 * inserted, which drops the checks that need one.
 */
export function sealChecks(
  table: SealTable,
  seeded: boolean,
  sample: (column: AppColumnConfig) => string | null | undefined,
): SealChecks {
  const columns = encryptedColumns(table.config);

  if (columns.length === 0) {
    return { static: [], seeded: [], behaviour: [] };
  }

  const label = `${SCHEMA}.${table.name}`;
  const name = sqlString(table.name);
  const id = idType(table.config);
  const signature = sqlString(`${revealFunction(table.name)}(${id}[])`);
  const trigger = table.ctx.trigger("seal_fields").replaceAll('"', "");
  const reveal = `${revealFunction(table.name)}(current_setting(${sqlString(REVEAL_IDS)})::${id}[])`;

  const statics = [
    `select extensions.has_trigger('${SCHEMA}'::name, ${name}::name, ${sqlString(trigger)}::name, ${sqlString(`${label} encrypts its encrypted columns`)});`,
    `select extensions.has_function('${SCHEMA}'::name, ${sqlString(`${table.name}_reveal`)}::name, array[${sqlString(`${id}[]`)}]::name[], ${sqlString(`${label} has a reveal function`)});`,
    `select extensions.ok(not has_function_privilege('anon', ${signature}, 'execute'), ${sqlString(`anon cannot reveal ${label}`)});`,
  ];

  if (!seeded || table.scope === undefined) {
    return { static: statics, seeded: [], behaviour: [] };
  }

  const plain = (column: string): string =>
    plainSample(table.config.columns?.[column] ?? { type: "text" }, sample);

  const seededChecks = [
    `update ${qualified(table.name)} set ${columns.map((column) => `${sqlIdent(column)} = (${plain(column)})::text`).join(", ")};`,
    `select set_config(${sqlString(REVEAL_IDS)}, (select array_agg(id)::text from ${qualified(table.name)}), true);`,
    // An earlier block may have left a signed-in user's claims behind.
    `select set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);`,
    ...columns.flatMap((column) => [
      `select extensions.ok((select bool_and(left(${sqlIdent(column)}, ${String(FIELD_CIPHER_PREFIX.length)}) = ${sqlString(FIELD_CIPHER_PREFIX)} and ${sqlIdent(column)} <> (${plain(column)})::text) from ${qualified(table.name)}), ${sqlString(`${label}.${column} is ciphertext at rest`)});`,
      `select extensions.is((select r.${sqlIdent(column)}::text from ${reveal} r limit 1), (${plain(column)})::text, ${sqlString(`the service role reveals ${label}.${column}`)});`,
    ]),
  ];

  return {
    static: statics,
    seeded: seededChecks,
    behaviour: [
      `select extensions.is((select count(*)::integer from ${reveal}), 0, ${sqlString(`a signed-in user does not reveal a row of ${label} outside their scope`)});`,
    ],
  };
}
