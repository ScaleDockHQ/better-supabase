import type { MessagingSql } from "./messaging-names.ts";

import { fail, serviceGrant, userGrant } from "../shared.ts";
import { MAX_SUMMARY_LENGTH } from "./messaging-tables.ts";

/** `thread_summary` and the service role's `save_thread_summary`. */
export function summaryFunctions(q: MessagingSql): string {
  const { t, fn } = q;
  const ms = q.cols("messages");
  const cv = q.cols("conversations");
  const su = q.cols("summaries");

  return `
-- The summary of a thread (by its root message) or of a conversation's
-- top-level messages (thread null), or null. stale is true once a message in
-- scope was sent after through_at, or edited or deleted after the summary was
-- saved. Notes never count. Runs as the caller, so it shows only summaries of
-- conversations they read.
create or replace function ${fn("thread_summary")}(conversation uuid default null, thread uuid default null)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select to_jsonb(s) || jsonb_build_object(
    'stale', exists (
      select 1 from ${t("messages")} m
      where m.${ms("conversation")} = s.${su("conversation")}
        and m.${ms("kind")} = 'message' and m.${ms("sentAt")} is not null
        and case when s.${su("thread")} is null then m.${ms("thread")} is null
          else m.${ms("id")} = s.${su("thread")} or m.${ms("thread")} = s.${su("thread")} end
        and (m.${ms("sentAt")} > s.${su("throughAt")}
          or m.${ms("editedAt")} > s.${su("updatedAt")}
          or m.${ms("deletedAt")} > s.${su("updatedAt")})
    )
  )
  from ${t("summaries")} s
  where s.${su("conversation")} = coalesce(thread_summary.conversation,
      (select m.${ms("conversation")} from ${t("messages")} m where m.${ms("id")} = thread_summary.thread))
    and s.${su("thread")} is not distinct from thread_summary.thread
$$;
${userGrant(`${fn("thread_summary")}(uuid, uuid)`)}

-- Saves the summary of a thread (by its sent root message) or of a
-- conversation (thread null), in place of the one saved before. attrs: model,
-- messageCount and throughAt (when the newest summarized message was sent).
-- The service role calls it after the app read the messages as the user.
-- Returns the summary as thread_summary does.
create or replace function ${fn("save_thread_summary")}(conversation uuid, thread uuid, summary text, attrs jsonb default '{}')
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_conversation uuid;
  v_tenant ${q.id};
  v_count integer;
begin
  if not ${q.service} then
    ${fail("MESSAGING_FORBIDDEN", "save_thread_summary runs as the service role")}
  end if;
  if save_thread_summary.thread is null then
    select c.${cv("id")}, c.${cv("tenant")} into v_conversation, v_tenant
    from ${t("conversations")} c where c.${cv("id")} = save_thread_summary.conversation;
  else
    select m.${ms("conversation")}, m.${ms("tenant")} into v_conversation, v_tenant
    from ${t("messages")} m
    where m.${ms("id")} = save_thread_summary.thread and m.${ms("thread")} is null and m.${ms("sentAt")} is not null
      and (save_thread_summary.conversation is null or m.${ms("conversation")} = save_thread_summary.conversation);
  end if;
  if v_conversation is null then
    ${fail("MESSAGING_NOT_FOUND", "no such conversation or thread root", "P0002")}
  end if;
  begin
    v_count := coalesce((save_thread_summary.attrs ->> 'messageCount')::integer, 0);
  exception when invalid_text_representation or numeric_value_out_of_range then
    v_count := -1;
  end;
  if char_length(btrim(coalesce(save_thread_summary.summary, ''))) not between 1 and ${String(MAX_SUMMARY_LENGTH)}
    or char_length(save_thread_summary.attrs ->> 'model') > 200
    or v_count < 0
    or save_thread_summary.attrs ->> 'throughAt' is null then
    ${fail("MESSAGING_SUMMARY_INVALID", `a summary needs 1 to ${String(MAX_SUMMARY_LENGTH)} characters, a message count and throughAt`, "22023")}
  end if;
  insert into ${t("summaries")} (${su("tenant")}, ${su("conversation")}, ${su("thread")}, ${su("summary")}, ${su("model")}, ${su("messageCount")}, ${su("throughAt")})
  values (v_tenant, v_conversation, save_thread_summary.thread, btrim(save_thread_summary.summary),
    save_thread_summary.attrs ->> 'model', v_count, (save_thread_summary.attrs ->> 'throughAt')::timestamptz)
  on conflict (${su("conversation")}, ${su("thread")}) do update
  set ${su("summary")} = excluded.${su("summary")},
    ${su("model")} = excluded.${su("model")},
    ${su("messageCount")} = excluded.${su("messageCount")},
    ${su("throughAt")} = excluded.${su("throughAt")},
    ${su("updatedAt")} = now();
  return ${fn("thread_summary")}(v_conversation, save_thread_summary.thread);
end;
$$;
${serviceGrant(`${fn("save_thread_summary")}(uuid, uuid, text, jsonb)`)}
`;
}
