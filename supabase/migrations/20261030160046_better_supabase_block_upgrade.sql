-- better-supabase upgrade: steps that run before the schema diff.

-- ai-files: version 1 to 2. Document versions move onto the versions block: each ai_document_versions row becomes a versions row of subject type ai_document, with its text and the message that wrote it in content, and the old table is dropped.
-- The versions table, so the document versions can move before the module files run.
create table if not exists "better_supabase"."versions" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "subject_type" text not null,
  "subject_id" text not null,
  "number" integer not null check ("number" > 0),
  "label" text check (length("label") between 1 and 120),
  "content" jsonb,
  "storage_path" text,
  "content_hash" text not null,
  "source" text not null default 'manual' check ("source" in ('manual', 'auto', 'restore')),
  "frozen" boolean not null default false,
  "created_by" uuid,
  "created_at" timestamptz not null default now(),
  unique ("subject_type", "subject_id", "number"),
  check ("content" is not null or "storage_path" is not null)
);
create index if not exists "versions_tenant_idx" on "better_supabase"."versions" ("tenant_id");

do $$
begin
  if to_regclass('"better_supabase"."ai_document_versions"') is null then
    return;
  end if;
  insert into "better_supabase"."versions" ("tenant_id", "subject_type", "subject_id", "number", "content", "storage_path", "content_hash", "source", "frozen", "created_by", "created_at")
  select doc."organization_id", 'ai_document', x.document_id::text, x.version, jsonb_build_object('text', x.content, 'messageId', x.created_by_message_id), x.storage_path,
    encode(extensions.digest(coalesce(jsonb_build_object('text', x.content, 'messageId', x.created_by_message_id)::text, '') || coalesce(x.storage_path, ''), 'sha256'), 'hex'),
    'manual', false, x.created_by, x.created_at
  from "better_supabase"."ai_document_versions" x
  join "better_supabase"."ai_documents" doc on doc."id" = x.document_id
  on conflict ("subject_type", "subject_id", "number") do nothing;
  drop table "better_supabase"."ai_document_versions" cascade;
end;
$$;
