import type {
  ModuleContext,
  ModuleContractFunction,
  ModuleNames,
} from "../context.ts";
import type { ModuleDefinition } from "../registry.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { SERVICE_CALLER, schemaPreamble } from "../shared.ts";
import { MODULE_PERMISSIONS } from "./access-model.ts";

const NAMES: ModuleNames = {
  options: ["subjects", "maxBodyLength"],
  tables: {
    comments: {
      name: "comments",
      columns: {
        id: "id",
        tenant: "organization_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        author: "author_id",
        body: "body",
        mentions: "mentions",
        parent: "parent_id",
        createdAt: "created_at",
        editedAt: "edited_at",
        deletedAt: "deleted_at",
      },
    },
    activity: {
      name: "activity_entries",
      columns: {
        id: "id",
        tenant: "organization_id",
        event: "event_id",
        type: "type",
        actor: "actor_id",
        subjectType: "subject_type",
        subjectId: "subject_id",
        summary: "summary",
        data: "data",
        occurredAt: "occurred_at",
      },
    },
  },
};

/** One commentable subject type: its table, and who may read it. */
export interface CommentSubject {
  /** `schema.table`, or a table in `public`. */
  readonly table: string;
  /** Default `id`. */
  readonly id?: string;
  /** The subject's tenant column, default `organization_id`. */
  readonly tenant?: string;
  /** A permission the caller also needs in the tenant, e.g. `projects.read`. */
  readonly permission?: string;
}

const isObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const SUBJECT_TYPE = /^[a-z][a-z0-9_]{0,62}$/;

function subjectsOf(ctx: ModuleContext): readonly [string, CommentSubject][] {
  const raw = ctx.option("subjects");
  if (raw === undefined) return [];
  if (!isObject(raw)) {
    throw new TypeError(
      "sql.modules.comments.options.subjects: pass an object of subject type to { table, id?, tenant?, permission? }",
    );
  }
  return Object.entries(raw).map(([type, entry]): [string, CommentSubject] => {
    if (!SUBJECT_TYPE.test(type)) {
      throw new TypeError(
        `sql.modules.comments.options.subjects: "${type}" must be lowercase letters, digits and underscores`,
      );
    }
    if (!isObject(entry) || typeof entry["table"] !== "string") {
      throw new TypeError(
        `sql.modules.comments.options.subjects.${type} needs a table`,
      );
    }
    const text = (key: string): string | undefined => {
      const value = entry[key];
      if (value === undefined) return undefined;
      if (typeof value !== "string") {
        throw new TypeError(
          `sql.modules.comments.options.subjects.${type}.${key} must be a string`,
        );
      }
      return value;
    };
    const table = text("table") ?? "";
    const id = text("id");
    const tenant = text("tenant");
    const permission = text("permission");
    return [
      type,
      {
        table,
        ...(id !== undefined && { id }),
        ...(tenant !== undefined && { tenant }),
        ...(permission !== undefined && { permission }),
      },
    ];
  });
}

const qualified = (table: string): string => {
  const [schema, name] = table.includes(".")
    ? table.split(".", 2)
    : ["public", table];
  return `${sqlIdent(schema ?? "public")}.${sqlIdent(name ?? table)}`;
};

function build(ctx: ModuleContext): string {
  if (ctx.mode === "custom") return "";
  const id = ctx.idType;
  const comments = ctx.table("comments");
  const activity = ctx.table("activity");
  const c = (logical: string): string => ctx.col("comments", logical);
  const a = (logical: string): string => ctx.col("activity", logical);
  const fn = (name: string): string => ctx.fn(name);
  const permissions = MODULE_PERMISSIONS.comments;
  const permission = (action: keyof typeof permissions): string =>
    ctx.permission(action, permissions[action]);
  const can = (tenant: string, action: keyof typeof permissions): string =>
    `coalesce(better_supabase.can('tenant', ${tenant}, ${permission(action)}), false)`;
  const maxBody = ctx.number("maxBodyLength", 10_000);
  if (!Number.isInteger(maxBody) || maxBody < 1) {
    throw new TypeError(
      "sql.modules.comments.options.maxBodyLength must be a whole number above zero",
    );
  }
  const subjects = subjectsOf(ctx);
  const readable =
    subjects.length === 0
      ? "true"
      : `case subject_type\n${subjects
          .map(([type, subject]) => {
            const extra = subject.permission
              ? ` and coalesce(better_supabase.can('tenant', tenant, ${sqlString(subject.permission)}), false)`
              : "";
            return `    when ${sqlString(type)} then exists (select 1 from ${qualified(subject.table)} s where s.${sqlIdent(subject.id ?? "id")}::text = subject_id and s.${sqlIdent(subject.tenant ?? "organization_id")} = tenant)${extra}`;
          })
          .join("\n")}\n    else false\n  end`;
  const notifications = ctx.installed("notifications")
    ? `
  -- notify() trusts only the service role, so the mention is sent as it,
  -- with the comment's author as the actor; the claims are restored after.
  if cardinality(v_new) > 0 then
    v_claims := current_setting('request.jwt.claims', true);
    perform set_config('request.jwt.claims', '{"role": "service_role"}', true);
    perform ${ctx.of("notifications").fn("notify")}(jsonb_build_object(
      'type', 'comment.mentioned',
      'tenant', new.${c("tenant")},
      'actor', new.${c("author")},
      'subject_type', new.${c("subjectType")},
      'subject_id', new.${c("subjectId")},
      'summary', left(new.${c("body")}, 140),
      'recipients', to_jsonb(v_new),
      'key', 'comment.mentioned:' || new.${c("id")}::text || ':' || md5(array_to_string(v_new, ',')),
      'data', jsonb_build_object('commentId', new.${c("id")})
    ));
    perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  end if;`
    : "";
  const payload = (extra: string): string =>
    `jsonb_build_object('commentId', new.${c("id")}, 'organizationId', new.${c("tenant")}::text, 'subjectType', new.${c("subjectType")}, 'subjectId', new.${c("subjectId")}, 'authorId', new.${c("author")}${extra})`;
  const subject = `'comments/' || new.${c("id")}::text`;
  const tenant = `new.${c("tenant")}`;
  const created = ctx.emit({
    type: "comment.created",
    payload: payload(
      `, 'parentId', new.${c("parent")}, 'mentionIds', to_jsonb(new.${c("mentions")})`,
    ),
    subject,
    tenant,
  });
  const mentioned = ctx.emit({
    type: "comment.mentioned",
    payload: payload(`, 'mentionIds', to_jsonb(v_new)`),
    subject,
    tenant,
  });
  const deleted = ctx.emit({
    type: "comment.deleted",
    payload: payload(""),
    subject,
    tenant,
  });

  return `${schemaPreamble(ctx)}
-- Comments on any subject in a tenant. options.subjects maps each subject
-- type to its table, so the policies require that the caller can read the
-- subject; without it any subject type is accepted.
create table if not exists ${comments} (
  ${c("id")} uuid primary key default gen_random_uuid(),
  ${c("tenant")} ${id} not null,
  ${c("subjectType")} text not null check (${c("subjectType")} ~ '^[a-z][a-z0-9_]{0,62}$'),
  ${c("subjectId")} text not null check (length(${c("subjectId")}) between 1 and 200),
  ${c("author")} uuid references auth.users (id) on delete set null default auth.uid(),
  ${c("body")} text not null check (length(${c("body")}) <= ${String(maxBody)}),
  ${c("mentions")} uuid[] not null default '{}',
  ${c("parent")} uuid references ${comments} (${c("id")}) on delete cascade,
  -- clock_timestamp keeps a thread in order within one transaction.
  ${c("createdAt")} timestamptz not null default clock_timestamp(),
  ${c("editedAt")} timestamptz,
  ${c("deletedAt")} timestamptz,
  check (${c("deletedAt")} is not null or length(btrim(${c("body")})) > 0)
);
create index if not exists comments_subject_idx on ${comments} (${c("tenant")}, ${c("subjectType")}, ${c("subjectId")}, ${c("createdAt")});
create index if not exists comments_author_idx on ${comments} (${c("author")});
create index if not exists comments_parent_idx on ${comments} (${c("parent")});
alter table ${comments} enable row level security;
revoke all on ${comments} from anon, authenticated;
grant select on ${comments} to authenticated;
grant insert (${[c("tenant"), c("subjectType"), c("subjectId"), c("body"), c("mentions"), c("parent")].join(", ")}) on ${comments} to authenticated;
grant update (${[c("body"), c("mentions"), c("deletedAt")].join(", ")}) on ${comments} to authenticated;
grant all on ${comments} to service_role;

-- Whether the caller may read a subject: its row is visible to them (the
-- subject table's own policies apply) and they hold its permission.
create or replace function ${fn("comment_subject_readable")}(subject_type text, subject_id text, tenant ${id})
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select ${readable}
$$;

drop policy if exists "comments_read" on ${comments};
create policy "comments_read" on ${comments} for select to authenticated
  using (${can(c("tenant"), "read")} and ${fn("comment_subject_readable")}(${c("subjectType")}, ${c("subjectId")}, ${c("tenant")}));
drop policy if exists "comments_insert" on ${comments};
create policy "comments_insert" on ${comments} for insert to authenticated
  with check (
    ${c("author")} = (select auth.uid())
    and ${can(c("tenant"), "create")}
    and ${fn("comment_subject_readable")}(${c("subjectType")}, ${c("subjectId")}, ${c("tenant")})
  );
drop policy if exists "comments_update" on ${comments};
create policy "comments_update" on ${comments} for update to authenticated
  using (${c("author")} = (select auth.uid()) or ${can(c("tenant"), "moderate")})
  with check (${c("author")} = (select auth.uid()) or ${can(c("tenant"), "moderate")});

-- Keeps mentions to distinct members other than the author, a reply on its
-- parent's subject, and edited_at; a deleted comment keeps no body.
create or replace function ${fn("comments_before_write")}()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and old.${c("deletedAt")} is not null then
    raise exception 'This comment was deleted' using errcode = 'P0001', hint = 'COMMENT_DELETED';
  end if;
  if new.${c("deletedAt")} is not null then
    new.${c("body")} := '';
    new.${c("mentions")} := '{}';
    return new;
  end if;
  new.${c("mentions")} := array(
    select distinct x from unnest(new.${c("mentions")}) x
    where x is not null and x is distinct from new.${c("author")}
    order by x
  );
  if tg_op = 'INSERT' and new.${c("parent")} is not null and not exists (
    select 1 from ${comments} p
    where p.${c("id")} = new.${c("parent")} and p.${c("tenant")} = new.${c("tenant")}
      and p.${c("subjectType")} = new.${c("subjectType")} and p.${c("subjectId")} = new.${c("subjectId")}
  ) then
    raise exception 'A reply must be on its parent''s subject' using errcode = '23514', hint = 'COMMENT_PARENT_MISMATCH';
  end if;
  if tg_op = 'UPDATE' and (new.${c("body")} is distinct from old.${c("body")} or new.${c("mentions")} is distinct from old.${c("mentions")}) then
    if old.${c("author")} is distinct from auth.uid() and not (${SERVICE_CALLER}) then
      raise exception 'Only the author edits a comment' using errcode = '42501', hint = 'COMMENT_NOT_AUTHOR';
    end if;
    new.${c("editedAt")} := now();
  end if;
  return new;
end;
$$;
drop trigger if exists ${ctx.trigger("comments_before_write")} on ${comments};
create trigger ${ctx.trigger("comments_before_write")}
  before insert or update on ${comments}
  for each row execute function ${fn("comments_before_write")}();

-- Notifies newly mentioned members who can read comments in the tenant,
-- and writes comment.created, comment.mentioned and comment.deleted to the
-- outbox when it is installed.
create or replace function ${fn("comments_after_write")}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_new uuid[];
  v_claims text;
begin
  if tg_op = 'UPDATE' and new.${c("deletedAt")} is not null then
    ${deleted || "null;"}
    return null;
  end if;
  v_new := array(
    select x from unnest(new.${c("mentions")}) x
    where (tg_op = 'INSERT' or not x = any(old.${c("mentions")}))
      and coalesce(better_supabase.can_user(x, 'tenant', new.${c("tenant")}, ${permission("read")}), false)
  );
  if tg_op = 'INSERT' then
    ${created || "null;"}
  end if;
  if cardinality(v_new) > 0 then
    ${mentioned || "null;"}
  end if;${notifications}
  return null;
end;
$$;
revoke execute on function ${fn("comments_after_write")}() from public, anon, authenticated;
drop trigger if exists ${ctx.trigger("comments_after_write")} on ${comments};
create trigger ${ctx.trigger("comments_after_write")}
  after insert or update of ${c("mentions")}, ${c("deletedAt")} on ${comments}
  for each row execute function ${fn("comments_after_write")}();

-- The functions run as the caller, so the policies above decide.
create or replace function ${fn("create_comment")}(
  tenant ${id},
  subject_type text,
  subject_id text,
  body text,
  mentions uuid[] default '{}',
  parent uuid default null
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  insert into ${comments} as x (${[c("tenant"), c("subjectType"), c("subjectId"), c("body"), c("mentions"), c("parent")].join(", ")})
  values (create_comment.tenant, create_comment.subject_type, create_comment.subject_id, create_comment.body, coalesce(create_comment.mentions, '{}'), create_comment.parent)
  returning to_jsonb(x.*)
$$;

create or replace function ${fn("edit_comment")}(id uuid, body text, mentions uuid[] default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  update ${comments} x
  set ${c("body")} = edit_comment.body,
      ${c("mentions")} = coalesce(edit_comment.mentions, x.${c("mentions")})
  where x.${c("id")} = edit_comment.id
  returning to_jsonb(x.*)
$$;

create or replace function ${fn("delete_comment")}(id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$
  with removed as (
    update ${comments} x set ${c("deletedAt")} = now()
    where x.${c("id")} = delete_comment.id and x.${c("deletedAt")} is null
    returning 1
  )
  select exists (select 1 from removed)
$$;

-- A subject's thread, oldest first; deleted comments stay as placeholders
-- so replies keep their parent.
create or replace function ${fn("list_comments")}(
  tenant ${id},
  subject_type text,
  subject_id text,
  after timestamptz default null,
  max_rows integer default 100
)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(x.*) order by x.${c("createdAt")}, x.${c("id")}), '[]'::jsonb)
  from (
    select * from ${comments} y
    where y.${c("tenant")} = list_comments.tenant
      and y.${c("subjectType")} = list_comments.subject_type
      and y.${c("subjectId")} = list_comments.subject_id
      and (list_comments.after is null or y.${c("createdAt")} > list_comments.after)
    order by y.${c("createdAt")}, y.${c("id")}
    limit least(greatest(coalesce(list_comments.max_rows, 100), 1), 500)
  ) x
$$;

-- The activity feed: one row per outbox event, written by activitySink().
create table if not exists ${activity} (
  ${a("id")} uuid primary key default gen_random_uuid(),
  ${a("tenant")} ${id} not null,
  ${a("event")} text not null unique,
  ${a("type")} text not null,
  ${a("actor")} uuid references auth.users (id) on delete set null,
  ${a("subjectType")} text,
  ${a("subjectId")} text,
  ${a("summary")} text,
  ${a("data")} jsonb not null default '{}'::jsonb,
  ${a("occurredAt")} timestamptz not null default now()
);
create index if not exists activity_entries_feed_idx on ${activity} (${a("tenant")}, ${a("occurredAt")} desc, ${a("id")} desc);
create index if not exists activity_entries_subject_idx on ${activity} (${a("tenant")}, ${a("subjectType")}, ${a("subjectId")});
create index if not exists activity_entries_actor_idx on ${activity} (${a("actor")});
alter table ${activity} enable row level security;
revoke all on ${activity} from anon, authenticated;
grant select on ${activity} to authenticated;
grant all on ${activity} to service_role;
drop policy if exists "activity_entries_read" on ${activity};
create policy "activity_entries_read" on ${activity} for select to authenticated
  using (${can(a("tenant"), "activity")});

-- Inserts batch.entries ({ event_id, organization_id, type, actor_id?,
-- subject_type?, subject_id?, summary?, data?, occurred_at? }); a seen
-- event_id is skipped, so a replayed batch writes nothing twice. The list
-- sits in an object so it reaches jsonb the same way over Postgres and the
-- Data API.
create or replace function ${fn("record_activity")}(batch jsonb)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  inserted integer;
begin
  if not (${SERVICE_CALLER}) then
    raise exception 'Only the service role records activity' using errcode = '42501', hint = 'ACTIVITY_FORBIDDEN';
  end if;
  insert into ${activity} (${[a("event"), a("tenant"), a("type"), a("actor"), a("subjectType"), a("subjectId"), a("summary"), a("data"), a("occurredAt")].join(", ")})
  select e ->> 'event_id', (e ->> 'organization_id')::${id}, e ->> 'type', nullif(e ->> 'actor_id', '')::uuid,
    e ->> 'subject_type', e ->> 'subject_id', e ->> 'summary', coalesce(e -> 'data', '{}'::jsonb),
    coalesce((e ->> 'occurred_at')::timestamptz, now())
  from jsonb_array_elements(coalesce(batch -> 'entries', '[]'::jsonb)) e
  on conflict (${a("event")}) do nothing;
  get diagnostics inserted = row_count;
  return inserted;
end;
$$;

revoke execute on function ${fn("comment_subject_readable")}(text, text, ${id}) from public, anon;
revoke execute on function ${fn("create_comment")}(${id}, text, text, text, uuid[], uuid) from public, anon;
revoke execute on function ${fn("edit_comment")}(uuid, text, uuid[]) from public, anon;
revoke execute on function ${fn("delete_comment")}(uuid) from public, anon;
revoke execute on function ${fn("list_comments")}(${id}, text, text, timestamptz, integer) from public, anon;
revoke execute on function ${fn("record_activity")}(jsonb) from public, anon, authenticated;
grant execute on function ${fn("comment_subject_readable")}(text, text, ${id}) to authenticated, service_role;
grant execute on function ${fn("create_comment")}(${id}, text, text, text, uuid[], uuid) to authenticated, service_role;
grant execute on function ${fn("edit_comment")}(uuid, text, uuid[]) to authenticated, service_role;
grant execute on function ${fn("delete_comment")}(uuid) to authenticated, service_role;
grant execute on function ${fn("list_comments")}(${id}, text, text, timestamptz, integer) to authenticated, service_role;
grant execute on function ${fn("record_activity")}(jsonb) to service_role;`;
}

function contract(): readonly ModuleContractFunction[] {
  return [
    {
      name: "comment_subject_readable",
      args: ["text", "text", "{id}"],
      returns: "boolean",
    },
    {
      name: "create_comment",
      args: ["{id}", "text", "text", "text", "uuid[]", "uuid"],
      returns: "jsonb",
    },
    {
      name: "edit_comment",
      args: ["uuid", "text", "uuid[]"],
      returns: "jsonb",
    },
    { name: "delete_comment", args: ["uuid"], returns: "boolean" },
    {
      name: "list_comments",
      args: ["{id}", "text", "text", "timestamp with time zone", "integer"],
      returns: "jsonb",
    },
    { name: "record_activity", args: ["jsonb"], returns: "integer" },
  ];
}

export const COMMENTS: ModuleDefinition = {
  name: "comments",
  title: "Comments and activity",
  description:
    "Comments on any subject in a tenant, with replies, mentions that notify (with the notifications module) and comment.* outbox events, plus an activity_entries feed that activitySink() fills from outbox events.",
  requires: ["tenant", "access"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
