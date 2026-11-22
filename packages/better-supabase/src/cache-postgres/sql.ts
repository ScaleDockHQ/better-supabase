import { sqlIdent } from "../core/template.ts";

export interface PostgresCacheSqlOptions {
  /** Default: `public`. */
  readonly schema?: string;
  /** Default: `bsb_cache_entries`. */
  readonly entriesTable?: string;
  /** Default: `bsb_cache_tags`. */
  readonly tagsTable?: string;
  /**
   * Also schedule `pg_cron` to delete entries past their hard limit every hour.
   * Default: false.
   */
  readonly prune?: boolean;
}

/**
 * The SQL for the tables `postgresCacheStore` uses. Both tables enable row
 * level security with no policy and revoke every grant from `anon` and
 * `authenticated`, so only the service role reads or writes them. Put it in a
 * migration of your app.
 */
export function postgresCacheSql(
  options: PostgresCacheSqlOptions = {},
): string {
  const schema = sqlIdent(options.schema ?? "public");
  const entries = `${schema}.${sqlIdent(options.entriesTable ?? "bsb_cache_entries")}`;
  const tags = `${schema}.${sqlIdent(options.tagsTable ?? "bsb_cache_tags")}`;

  const pruneJob = options.prune
    ? `
select cron.schedule(
  'bsb-cache-prune',
  '0 * * * *',
  $$delete from ${entries} where expires_at < (extract(epoch from now()) * 1000)::bigint$$
);
`
    : "";

  return `create table if not exists ${entries} (
  key text primary key,
  value text not null,
  tags text[] not null default '{}',
  stored_at bigint not null,
  expires_at bigint not null,
  path text,
  meta jsonb not null default '{}'::jsonb
);

create index if not exists ${sqlIdent("bsb_cache_entries_expires_at_idx")} on ${entries} (expires_at);
create index if not exists ${sqlIdent("bsb_cache_entries_path_idx")} on ${entries} (path) where path is not null;

create table if not exists ${tags} (
  tag text primary key,
  stale_at bigint not null default 0,
  expired_at bigint not null default 0
);

alter table ${entries} enable row level security;
alter table ${tags} enable row level security;

revoke all on ${entries} from anon, authenticated;
revoke all on ${tags} from anon, authenticated;
${pruneJob}`;
}
