SET local check_function_bodies = off;

CREATE OR REPLACE FUNCTION better_supabase.messaging_message_written()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO ''
  AS $function$
begin
  if new."sent_at" is null then
    return null;
  end if;
  if tg_op = 'INSERT' or old."sent_at" is null then
    update "better_supabase"."conversations" c set "last_message_at" = greatest(coalesce(c."last_message_at", new."sent_at"), new."sent_at"), "updated_at" = now()
    where c."id" = new."conversation_id";
  end if;
  if new."thread_id" is not null and (tg_op = 'INSERT' or old."sent_at" is null or new."archived_at" is distinct from old."archived_at") then
    -- A reply that is sent live and not deleted adds to the root's rollup in
    -- place. A delete, a restore or a reply that is not newer than the rollup's
    -- newest (a copied thread carries its counts, replies of one transaction share
    -- a time) asks the replies again (ADR 0639).
    if new."archived_at" is null and (tg_op = 'INSERT' or old."sent_at" is null) then
      update "better_supabase"."messages" r set
        "reply_count" = r."reply_count" + 1,
        "last_reply_at" = greatest(r."last_reply_at", new."sent_at"),
        "reply_user_ids" = case
          when new."author_id" is null or new."author_id" = any (r."reply_user_ids") or cardinality(r."reply_user_ids") >= 3 then r."reply_user_ids"
          else r."reply_user_ids" || new."author_id"
        end
      where r."id" = new."thread_id"
        and (r."last_reply_at" is null or r."last_reply_at" < new."sent_at");
      if found then
        return null;
      end if;
    end if;
    update "better_supabase"."messages" r set
      "reply_count" = (select count(*) from "better_supabase"."messages" x where x."thread_id" = r."id" and x."sent_at" is not null and x."archived_at" is null),
      "last_reply_at" = (select max(x."sent_at") from "better_supabase"."messages" x where x."thread_id" = r."id" and x."archived_at" is null),
      "reply_user_ids" = array(
        select y.u from (
          select x."author_id" as u, min(x."sent_at") as first
          from "better_supabase"."messages" x
          where x."thread_id" = r."id" and x."sent_at" is not null and x."archived_at" is null and x."author_id" is not null
          group by x."author_id"
        ) y order by y.first limit 3
      )
    where r."id" = new."thread_id";
  end if;
  return null;
end;
$function$;
