import type { BlockSqlContext } from "../context.ts";

import { moveSubjectRows, subjectMergeHandler } from "../subject-merge-sql.ts";
import { subjectsOption } from "../subjects.ts";

/**
 * The merge handler: the dropped record's conversation moves to the kept
 * record, or its messages join the kept record's conversation when that one
 * exists, and record mentions follow.
 */
export function messagingSubjectMerge(ctx: BlockSqlContext): string {
  const subjects = subjectsOption(ctx, [], { registryOnly: true });
  const conversations = ctx.table("conversations");
  const messages = ctx.table("messages");
  const mentions = ctx.table("recordMentions");
  const cv = (column: string): string => ctx.col("conversations", column);
  const ms = (column: string): string => ctx.col("messages", column);
  const rm = (column: string): string => ctx.col("recordMentions", column);

  const subjectConversation = (id: string): string =>
    `(select c.${cv("id")} from ${conversations} c where c.${cv("kind")} = 'subject' and c.${cv("subjectType")} = v_type and c.${cv("subjectId")} = ${id} limit 1)`;

  return subjectMergeHandler(
    ctx,
    subjects,
    `declare
      v_kept uuid := ${subjectConversation("v_keep")};
      v_dropped uuid := ${subjectConversation("v_drop")};
    begin
      if v_dropped is not null and v_kept is not null then
        update ${messages} x set ${ms("conversation")} = v_kept where x.${ms("conversation")} = v_dropped;
        update ${mentions} x set ${rm("conversation")} = v_kept where x.${rm("conversation")} = v_dropped;
        delete from ${conversations} x where x.${cv("id")} = v_dropped;
      end if;
      update ${conversations} x set ${cv("subjectId")} = v_keep
      where x.${cv("subjectType")} = v_type and x.${cv("subjectId")} = v_drop;
      ${moveSubjectRows(
        {
          table: mentions,
          type: rm("subjectType"),
          id: rm("subjectId"),
          unique: [rm("message")],
        },
        "v_type",
      )}
    end;`,
  );
}
