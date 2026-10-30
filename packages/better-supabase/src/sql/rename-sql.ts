import type { BlockSqlContext, BlockSqlNameMigration } from "./context.ts";

import { sqlString } from "../core/template.ts";

export interface Qualified {
  readonly schema: string;
  readonly name: string;
}

const IDENT: string = String.raw`(?:"(?:[^"]|"")+"|[A-Za-z_][\w$]*)`;
const QUALIFIED: string = String.raw`${IDENT}(?:\.${IDENT})?`;

export const TABLE: RegExp = new RegExp(
  String.raw`^create table if not exists (${QUALIFIED}) \(\n([\s\S]*?)\n\);`,
  "gm",
);

export const ADDED_COLUMN: RegExp = new RegExp(
  String.raw`^alter table (?:if exists )?(${QUALIFIED})\s+add column if not exists (${IDENT})`,
  "gim",
);

export const INDEX: RegExp = new RegExp(
  String.raw`create (?:unique )?index (?:if not exists )?(${IDENT})\s+on (?:only )?(${QUALIFIED})`,
  "gi",
);

export const POLICY: RegExp = new RegExp(
  String.raw`create policy (${IDENT}) on (${QUALIFIED})`,
  "gi",
);

export const TRIGGER: RegExp = new RegExp(
  String.raw`create (?:or replace )?(?:constraint )?trigger (${IDENT})\s[^;]*? on (${QUALIFIED})`,
  "gi",
);

export const FUNCTION: RegExp = new RegExp(
  String.raw`create (?:or replace )?function (${QUALIFIED})\(`,
  "gi",
);

export const NOT_COLUMN: RegExp =
  /^(?:constraint|primary key|unique|foreign key|check|exclude)\b/i;

export const unquote = (ident: string): string =>
  ident.startsWith('"') ? ident.slice(1, -1).replaceAll('""', '"') : ident;

export const quote = (ident: string): string =>
  `"${ident.replaceAll('"', '""')}"`;

export const identParts = (text: string): string[] =>
  [...text.matchAll(new RegExp(IDENT, "g"))].map((match) => match[0]);

export function qualified(text: string, schema: string): Qualified {
  const parts = identParts(text).map(unquote);

  return parts.length > 1
    ? { schema: parts[0]!, name: parts[1]! }
    : { schema, name: parts[0] ?? text };
}

export const sqlName = (table: Qualified): string =>
  `${quote(table.schema)}.${quote(table.name)}`;

export const guarded = (condition: string, statement: string): string =>
  `do $$ begin if ${condition} then ${statement} end if; end $$;`;

const tableExists = (table: Qualified): string =>
  `to_regclass(${sqlString(sqlName(table))}) is not null`;

export function renameTable(from: Qualified, to: Qualified): string {
  return guarded(
    `${tableExists(from)} and to_regclass(${sqlString(sqlName({ schema: from.schema, name: to.name }))}) is null`,
    `alter table ${sqlName(from)} rename to ${quote(to.name)};`,
  );
}

export function renameColumn(
  table: Qualified,
  from: string,
  to: string,
): string {
  return guarded(
    `exists (select 1 from information_schema.columns where table_schema = ${sqlString(table.schema)} and table_name = ${sqlString(table.name)} and column_name = ${sqlString(from)})`,
    `alter table ${sqlName(table)} rename column ${quote(from)} to ${quote(to)};`,
  );
}

export function renameFunction(from: Qualified, to: Qualified): string {
  return `do $$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = ${sqlString(from.schema)} and p.proname = ${sqlString(from.name)} loop
    execute format('alter function %s rename to %I', f, ${sqlString(to.name)});
  end loop;
end $$;`;
}

/**
 * Renames the indexes, policies, triggers, constraints and owned sequences of
 * `table` whose names start with `from_` to start with the table's name, unless
 * the new name is taken.
 */
export function renameTableObjects(table: Qualified, from: string): string {
  const schema = sqlString(table.schema);
  const prefix = sqlString(`${from}_`);
  const to = sqlString(table.name);
  const relation = sqlString(sqlName(table));
  const renamed = `${to} || substr(o.name, ${String(from.length + 1)})`;

  const fresh = (exists: string): string =>
    `left(o.name, ${String(from.length + 1)}) = ${prefix} and not exists (${exists})`;

  return `do $$
declare o record;
begin
  if to_regclass(${relation}) is null then return; end if;
  for o in select c.relname as name from pg_index i join pg_class c on c.oid = i.indexrelid
    where i.indrelid = ${relation}::regclass loop
    if ${fresh(`select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = ${schema} and x.relname = ${renamed}`)} then
      execute format('alter index %I.%I rename to %I', ${schema}, o.name, ${renamed});
    end if;
  end loop;
  for o in select p.polname as name from pg_policy p where p.polrelid = ${relation}::regclass loop
    if ${fresh(`select 1 from pg_policy x where x.polrelid = ${relation}::regclass and x.polname = ${renamed}`)} then
      execute format('alter policy %I on %s rename to %I', o.name, ${relation}, ${renamed});
    end if;
  end loop;
  for o in select t.tgname as name from pg_trigger t where t.tgrelid = ${relation}::regclass and not t.tgisinternal loop
    if ${fresh(`select 1 from pg_trigger x where x.tgrelid = ${relation}::regclass and x.tgname = ${renamed}`)} then
      execute format('alter trigger %I on %s rename to %I', o.name, ${relation}, ${renamed});
    end if;
  end loop;
  for o in select k.conname as name from pg_constraint k where k.conrelid = ${relation}::regclass loop
    if ${fresh(`select 1 from pg_constraint x join pg_namespace n on n.oid = x.connamespace where n.nspname = ${schema} and x.conname = ${renamed}`)} then
      execute format('alter table %s rename constraint %I to %I', ${relation}, o.name, ${renamed});
    end if;
  end loop;
  for o in select s.relname as name from pg_depend d join pg_class s on s.oid = d.objid
    where d.refobjid = ${relation}::regclass and d.classid = 'pg_class'::regclass and s.relkind = 'S' loop
    if ${fresh(`select 1 from pg_class x join pg_namespace n on n.oid = x.relnamespace where n.nspname = ${schema} and x.relname = ${renamed}`)} then
      execute format('alter sequence %I.%I rename to %I', ${schema}, o.name, ${renamed});
    end if;
  end loop;
end $$;`;
}

/** The `alter table ... rename` statements for one declared move. */
export function nameMigrationSql(
  ctx: BlockSqlContext,
  migration: BlockSqlNameMigration,
): string {
  if (!ctx.hasTable(migration.table)) {
    return "";
  }

  const table = qualified(ctx.table(migration.table), ctx.schemaName);
  const statements: string[] = [];

  if (migration.was !== undefined) {
    const was = ctx.naming.rename(migration.was);

    if (was !== table.name) {
      statements.push(renameTable({ schema: table.schema, name: was }, table));
    }

    if (migration.objects === true && was !== table.name) {
      statements.push(renameTableObjects(table, was));
    }
  }

  for (const [logical, was] of Object.entries(migration.columns ?? {})) {
    const to = ctx.colName(migration.table, logical);
    const from = ctx.naming.rename(was);

    if (from !== to) {
      statements.push(renameColumn(table, from, to));
    }
  }

  return statements.join("\n");
}
