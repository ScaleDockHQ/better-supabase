import type { MessagingSql } from "./messaging-names.ts";

import { sqlIdent } from "../../core/template.ts";

/**
 * With the inbox: its conversations and message details hang off the core rows,
 * and a core message in an inbox conversation pings the inbox's staff topic.
 * The inbox renders before messaging, so the links live here.
 */
export function messagingInbox(q: MessagingSql): string {
  const { ctx } = q;

  if (!ctx.installed("inbox") || ctx.of("inbox").mode === "custom") {
    return "";
  }

  const inbox = ctx.of("inbox");
  const cv = q.cols("conversations");
  const ms = q.cols("messages");
  const conversations = inbox.table("conversations");
  const details = inbox.table("details");

  const conversationKey = sqlIdent(
    `${inbox.tableName("conversations").name}_core_fkey`,
  );

  const detailKey = sqlIdent(`${inbox.tableName("details").name}_core_fkey`);
  const trigger = ctx.trigger(inbox.naming.rename("messaging_inbox_broadcast"));

  return `-- The inbox's conversations and message details belong to core rows.
alter table ${conversations} drop constraint if exists ${conversationKey};
alter table ${conversations} add constraint ${conversationKey}
  foreign key (${inbox.col("conversations", "id")}) references ${q.t("conversations")} (${cv("id")}) on delete cascade;
alter table ${details} drop constraint if exists ${detailKey};
alter table ${details} add constraint ${detailKey}
  foreign key (${inbox.col("details", "message")}) references ${q.t("messages")} (${ms("id")}) on delete cascade;

drop trigger if exists ${trigger} on ${q.t("messages")};
create trigger ${trigger} after insert or update on ${q.t("messages")}
  for each row execute function ${inbox.fn("inbox_message_broadcast")}();`;
}
