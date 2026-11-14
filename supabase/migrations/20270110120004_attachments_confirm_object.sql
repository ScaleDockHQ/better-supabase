SET local check_function_bodies = off;

DROP FUNCTION "api"."confirm_attachment"(uuid);

CREATE OR REPLACE FUNCTION api.confirm_attachment (
  id     uuid,
  object jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE sql
  SET search_path TO ''
  AS $function$ select "better_supabase"."confirm_attachment"($1, $2) $function$;

CREATE OR REPLACE FUNCTION better_supabase.confirm_attachment (
  id     uuid,
  object jsonb DEFAULT NULL::jsonb
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
declare
  v_row "better_supabase"."attachments";
  v_meta jsonb;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."attachments" a where a."id" = confirm_attachment.id for update;
  if v_row."id" is null or (v_row."uploaded_by" is distinct from auth.uid() and not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin'))) then
    raise exception 'No pending attachment of yours has this id' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_FOUND';
  end if;
  if v_row."uploaded_at" is not null then
    return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
  end if;
  select o.metadata into v_meta from storage.objects o
  where o.bucket_id = v_row."bucket" and o.name = (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end);
  if not found then
    if confirm_attachment.object is null or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin')) then
      raise exception 'The file was not uploaded yet' using errcode = 'P0002', hint = 'ATTACHMENT_NOT_UPLOADED';
    end if;
    if (case when jsonb_typeof(confirm_attachment.object -> 'size') = 'number'
        then (confirm_attachment.object ->> 'size')::numeric < 0
          or (confirm_attachment.object ->> 'size')::numeric <> trunc((confirm_attachment.object ->> 'size')::numeric)
        else true end)
      or coalesce(confirm_attachment.object ->> 'mimetype', '') !~ '^[^/[:space:]]+/[^[:space:]]+$' then
      raise exception 'object needs a whole size of 0 or more and a MIME type' using errcode = '22023', hint = 'ATTACHMENT_OBJECT_INVALID';
    end if;
    v_meta := jsonb_build_object('size', confirm_attachment.object -> 'size', 'mimetype', lower(confirm_attachment.object ->> 'mimetype'));
    if exists (
      select 1 from storage.buckets b
      where b.id = v_row."bucket"
        and ((b.file_size_limit is not null and (v_meta ->> 'size')::bigint > b.file_size_limit)
          or (coalesce(cardinality(b.allowed_mime_types), 0) > 0
            and not exists (select 1 from unnest(b.allowed_mime_types) m where v_meta ->> 'mimetype' like replace(lower(m), '*', '%'))))
    ) then
      raise exception 'The file breaks the size limit or MIME types of its bucket' using errcode = '22023', hint = 'ATTACHMENT_OBJECT_REFUSED';
    end if;
  end if;
  update "better_supabase"."attachments" a set
    "uploaded_at" = now(),
    "size" = coalesce((v_meta ->> 'size')::bigint, a."size"),
    "mime_type" = coalesce(lower(v_meta ->> 'mimetype'), a."mime_type"),
    "status" = 'clean'
  where a."id" = v_row."id"
  returning * into v_row;
  perform "better_supabase".emit_event('attachment.uploaded', jsonb_build_object('attachmentId', v_row."id", 'organizationId', v_row."tenant_id"::text, 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'uploadedBy', v_row."uploaded_by", 'mimeType', v_row."mime_type", 'size', v_row."size", 'version', v_row."version"), 'attachments/' || v_row."id"::text, (v_row."tenant_id")::text, null, 'better-supabase/attachments');
  perform better_supabase.audit_event(
    event_type => 'attachment.uploaded',
    category => 'data',
    target_type => 'attachment',
    record_id => v_row."id"::text,
    tenant => (v_row."tenant_id")::uuid,
    metadata => jsonb_build_object('attachmentId', v_row."id", 'organizationId', v_row."tenant_id"::text, 'subjectType', v_row."subject_type", 'subjectId', v_row."subject_id", 'uploadedBy', v_row."uploaded_by", 'mimeType', v_row."mime_type", 'size', v_row."size", 'version', v_row."version")
  );
  return (to_jsonb(v_row) || jsonb_build_object('object_path', (case when v_row."version" > 1 then v_row."object_path" || '-v' || v_row."version"::text else v_row."object_path" end)));
end;
$function$;

REVOKE ALL ON FUNCTION "api"."confirm_attachment"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "api"."confirm_attachment"(uuid, jsonb) TO "authenticated", "service_role";

REVOKE ALL ON FUNCTION "better_supabase"."confirm_attachment"(uuid, jsonb) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION "better_supabase"."confirm_attachment"(uuid, jsonb) TO "authenticated", "service_role";
