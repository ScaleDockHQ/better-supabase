import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import { errorText } from "../core/errors.ts";
import { ident as sqlIdent, literal as sqlString } from "./live.ts";

/** Reads of one queue message after which the worker skips it. */
const POISON_READS = 5;

/** The pgmq queue of an app table with `embedding` (`<table>_embed`). */
const queueOf = (table: string): string => `${table}_embed`;

/**
 * The tables whose queue BS241 reads and whether any pipeline posts to a worker
 * (BS242): app tables with `embedding`, and `blocks.knowledge` with
 * `autoEmbed`.
 */
function pipelines(context: DoctorContext): {
  readonly tables: string[];
  readonly knowledge: boolean;
} {
  return {
    tables: Object.entries(context.config.appTables)
      .filter(([, table]) => table.embedding !== undefined)
      .map(([name]) => name),
    knowledge:
      context.config.blocks["knowledge"]?.options?.["autoEmbed"] === true,
  };
}

export const EMBEDDING_JOB_RULES: readonly Rule[] = [
  {
    code: "BS241",
    severity: "warning",
    title: "Embedding jobs read too often",
    description:
      "An app table with `embedding` queues each changed row on a pgmq queue named `<table>_embed`, and the drain reads a message again after 60 seconds until the worker applies it. A message read five times or more is a job the worker can't finish (the embedder refuses the text, or the worker URL or token is wrong), and the worker stops sending it once it passes that count, so the row keeps no vector. Doctor lists the queues that hold such messages. Fix the cause, then delete the message with `select pgmq.delete('<queue>', <msg_id>)` or change the row. Needs a database; saved snapshots skip it.",
    async check(context) {
      const db = context.database;

      if (!db || "skipped" in db) {
        return [];
      }

      const findings: FindingInput[] = [];

      for (const table of pipelines(context).tables) {
        const queue = queueOf(table);
        const relation = `pgmq.${sqlIdent(`q_${queue}`)}`;

        try {
          const [row] = await db.query<{ stuck: string; reads: string | null }>(
            `select count(*) as stuck, max(read_ct) as reads from ${relation} where read_ct >= ${String(POISON_READS)}`,
          );

          const stuck = Number(row?.stuck ?? 0);

          if (stuck > 0) {
            findings.push({
              message: `The queue ${queue} holds ${String(stuck)} embedding job${stuck === 1 ? "" : "s"} read ${String(POISON_READS)} times or more (up to ${row?.reads ?? "?"}), so public.${table} has rows without a vector. Check the worker's logs and the Vault secrets embedding_worker_url and embedding_worker_token, then delete the message with \`select pgmq.delete(${sqlString(queue)}, <msg_id>)\`.`,
              target: `pgmq.${queue}`,
            });
          }
        } catch (cause) {
          // A queue the migration has not created yet is not a finding.
          const text = errorText(cause);

          if (!text.includes("does not exist")) {
            findings.push({
              message: `Could not read the queue ${queue} (${db.describe}): ${text}`,
            });
          }
        }
      }

      return findings;
    },
  },
  {
    code: "BS242",
    severity: "warning",
    title: "Embedding worker requests fail",
    description:
      "The drain posts each batch to the embedding worker with pg_net, which keeps the answers in `net._http_response` for six hours. A response with an error or a status of 400 or more means the worker is unreachable, rejects the token (401) or fails while it embeds (500). Doctor counts those in the last hour when an app table has `embedding` or `blocks.knowledge.options.autoEmbed` is on. Needs a database; saved snapshots skip it.",
    async check(context) {
      const db = context.database;

      if (!db || "skipped" in db) {
        return [];
      }

      const { tables, knowledge } = pipelines(context);

      if (tables.length === 0 && !knowledge) {
        return [];
      }

      try {
        const [row] = await db.query<{
          failed: string;
          status: number | null;
          error: string | null;
        }>(
          `select count(*) as failed, max(status_code) as status, max(error_msg) as error from net._http_response where created > now() - interval '1 hour' and (error_msg is not null or status_code >= 400)`,
        );

        const failed = Number(row?.failed ?? 0);

        if (failed === 0) {
          return [];
        }

        const reason =
          row?.error ??
          (row?.status === null ? "" : `status ${String(row?.status)}`);

        return [
          {
            message: `${String(failed)} pg_net request${failed === 1 ? "" : "s"} failed in the last hour (${reason}). Check that the Vault secrets embedding_worker_url and embedding_worker_token match the deployed worker.`,
            target: "net._http_response",
          },
        ];
      } catch (cause) {
        const text = errorText(cause);

        return text.includes("does not exist")
          ? []
          : [
              {
                message: `Could not read net._http_response (${db.describe}): ${text}`,
              },
            ];
      }
    },
  },
];
