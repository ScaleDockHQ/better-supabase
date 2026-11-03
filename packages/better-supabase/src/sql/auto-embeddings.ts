/**
 * What an app table's `embedding` option declares: the text columns that are
 * embedded and the vector column that holds the result.
 */
export interface AutoEmbeddingConfig {
  readonly schema?: string;
  readonly table: string;
  /** The key column the worker addresses a row by. Defaults to `id`. */
  readonly idColumn?: string;
  /** Text columns, joined with a blank line, that make up the embedded text. */
  readonly content: readonly string[];
  readonly dimensions: number;
  /** `halfvec` (the default) stores half precision and indexes up to 4000. */
  readonly type?: "vector" | "halfvec";
  /** The schema pgvector is installed in. Defaults to `extensions`. */
  readonly vectorSchema?: string;
  /** The vector column. Defaults to `embedding`. */
  readonly column?: string;
  /** The pgmq queue. Defaults to `<table>_embed`. */
  readonly queue?: string;
  /** The pg_cron schedule of the drain job. Defaults to `10 seconds`. */
  readonly schedule?: string;
  /** Rows one drain sends to the worker. Defaults to 20. */
  readonly batch?: number;
  /** The Vault secret that holds the worker URL. */
  readonly urlSecret?: string;
  /** The Vault secret that holds the bearer token the worker checks. */
  readonly tokenSecret?: string;
}

const IDENT = /^[a-z_][a-z0-9_]{0,62}$/;
const QUEUE = /^[a-z_][a-z0-9_]{0,46}$/;
const SCHEDULE = /^(\d{1,2} seconds?|[0-9*/, -]+( [0-9*/, -]+){4})$/;
const MAX_DIMENSIONS = { vector: 2000, halfvec: 4000 } as const;

const quote = (name: string): string => `"${name}"`;
const literal = (value: string): string => `'${value.replaceAll("'", "''")}'`;

function check(value: string, pattern: RegExp, what: string): void {
  if (!pattern.test(value)) {
    throw new Error(`embedding ${what} "${value}" is not valid`);
  }
}

/**
 * The SQL that keeps an app table's embedding column current: a vector column
 * with an HNSW cosine index, a trigger that clears the vector and enqueues the
 * row on pgmq when the content changes, a function that sends a batch to the
 * worker through pg_net and a pg_cron job that runs it. The worker URL and
 * token come from Vault, never from the file.
 *
 * `<table>_apply_embedding` stores a vector only while the row's content still
 * hashes to the value the worker embedded, and deletes the queue message.
 */
export function renderAutoEmbedding(config: AutoEmbeddingConfig): string {
  const schema = config.schema ?? "public";
  const idColumn = config.idColumn ?? "id";
  const column = config.column ?? "embedding";
  const type = config.type ?? "halfvec";
  const vectorSchema = config.vectorSchema ?? "extensions";
  const queue = config.queue ?? `${config.table}_embed`;
  const schedule = config.schedule ?? "10 seconds";
  const batch = config.batch ?? 20;
  const urlSecret = config.urlSecret ?? "embedding_worker_url";
  const tokenSecret = config.tokenSecret ?? "embedding_worker_token";

  check(schema, IDENT, "schema");
  check(config.table, IDENT, "table");
  check(idColumn, IDENT, "id column");
  check(column, IDENT, "column");
  check(vectorSchema, IDENT, "vector schema");
  check(queue, QUEUE, "queue");
  check(schedule, SCHEDULE, "schedule");

  if (config.content.length === 0) {
    throw new Error("embedding.content needs at least one column");
  }

  for (const name of config.content) {
    check(name, IDENT, "content column");
  }

  const max = MAX_DIMENSIONS[type];

  if (
    !Number.isInteger(config.dimensions) ||
    config.dimensions < 1 ||
    config.dimensions > max
  ) {
    throw new Error(
      `embedding.dimensions must be an integer from 1 to ${max} for ${type}`,
    );
  }

  if (!Number.isInteger(batch) || batch < 1 || batch > 200) {
    throw new Error("embedding.batch must be an integer from 1 to 200");
  }

  const t = `${quote(schema)}.${quote(config.table)}`;
  const id = quote(idColumn);
  const col = quote(column);
  const vtype = `${quote(vectorSchema)}.${type}(${config.dimensions})`;
  const opclass = `${quote(vectorSchema)}.${type}_cosine_ops`;
  const name = (suffix: string): string => quote(`${config.table}_${suffix}`);
  const fn = (suffix: string): string => `${quote(schema)}.${name(suffix)}`;

  const text = (row: string): string =>
    `concat_ws(E'\\n\\n', ${config.content.map((c) => `${row}.${quote(c)}`).join(", ")})`;

  const changed = config.content
    .map((c) => `new.${quote(c)} is distinct from old.${quote(c)}`)
    .join(" or ");

  return `-- Embeddings for ${t}, kept current by pgmq, pg_net and pg_cron.
create extension if not exists vector with schema ${quote(vectorSchema)};
create extension if not exists pgmq;
create extension if not exists pg_net;
create extension if not exists pg_cron;

alter table ${t} add column if not exists ${col} ${vtype};
create index if not exists ${name("embedding_idx")} on ${t} using hnsw (${col} ${opclass});

select pgmq.create(${literal(queue)});

create or replace function ${fn("embedding_enqueue")}() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and not (${changed}) then
    return new;
  end if;

  new.${col} := null;

  return new;
end;
$$;

create or replace function ${fn("embedding_enqueue_after")}() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform pgmq.send(${literal(queue)}, jsonb_build_object('id', new.${id}));

  return null;
end;
$$;

drop trigger if exists ${name("embedding_clear")} on ${t};
create trigger ${name("embedding_clear")} before insert or update on ${t}
  for each row execute function ${fn("embedding_enqueue")}();

drop trigger if exists ${name("embedding_queue")} on ${t};
create trigger ${name("embedding_queue")} after insert or update of ${config.content.map(quote).join(", ")} on ${t}
  for each row execute function ${fn("embedding_enqueue_after")}();

-- Sends up to ${batch} queued rows to the worker. A message the worker doesn't
-- apply becomes visible again after 60 seconds, so a failed batch retries.
create or replace function ${fn("process_embeddings")}() returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_url text;
  v_token text;
  v_jobs jsonb;
begin
  select decrypted_secret into v_url from vault.decrypted_secrets where name = ${literal(urlSecret)};
  select decrypted_secret into v_token from vault.decrypted_secrets where name = ${literal(tokenSecret)};

  if v_url is null or v_token is null then
    return;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'msgId', m.msg_id,
    'readCount', m.read_ct,
    'id', x.${id},
    'content', ${text("x")},
    'hash', md5(${text("x")})
  )), '[]'::jsonb) into v_jobs
  from pgmq.read(${literal(queue)}, 60, ${batch}) m
  join ${t} x on x.${id}::text = m.message ->> 'id';

  if jsonb_array_length(v_jobs) = 0 then
    return;
  end if;

  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object('content-type', 'application/json', 'authorization', 'Bearer ' || v_token),
    body := jsonb_build_object('queue', ${literal(queue)}, 'table', ${literal(config.table)}, 'jobs', v_jobs)
  );
end;
$$;

revoke all on function ${fn("process_embeddings")}() from public, anon, authenticated;

-- Runs the drain with pg_cron when the extension exists.
do $bsb$
begin
  if pg_catalog.to_regprocedure('cron.schedule(text, text, text)') is not null then
    perform cron.schedule(${literal(`${config.table}_embeddings`)}, ${literal(schedule)}, ${literal(`select ${fn("process_embeddings")}()`)});
  end if;
end;
$bsb$;

-- Stores the vector while the row still hashes to what was embedded, then
-- removes the queue message either way.
create or replace function ${fn("apply_embedding")}(row_id text, embedding_json jsonb, content_hash text, msg_id bigint)
returns boolean
language plpgsql security definer set search_path = '' as $$
declare
  v_updated integer;
begin
  update ${t} x set ${col} = (apply_embedding.embedding_json::text)::${vtype}
  where x.${id}::text = apply_embedding.row_id and md5(${text("x")}) = apply_embedding.content_hash;

  get diagnostics v_updated = row_count;

  perform pgmq.delete(${literal(queue)}, apply_embedding.msg_id);

  return v_updated > 0;
end;
$$;

revoke all on function ${fn("apply_embedding")}(text, jsonb, text, bigint) from public, anon, authenticated;
grant execute on function ${fn("apply_embedding")}(text, jsonb, text, bigint) to service_role;
`;
}
