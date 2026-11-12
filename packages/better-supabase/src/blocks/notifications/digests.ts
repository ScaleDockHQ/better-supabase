import type { AsyncResult } from "../../core/result.ts";
import type { DigestRunReport } from "../digest.ts";
import type { BlockPorts } from "../ports.ts";
import type { BlockOptions } from "../shared.ts";

import { digestLines, runDigests } from "../digest.ts";
import {
  blockCall,
  errorText,
  optionalText,
  recordsOf,
  textOf,
} from "../shared.ts";

/** One notification folded into a digest. */
export interface DigestItem {
  readonly type: string;
  readonly summary?: string;
  readonly subjectLabel?: string;
  readonly actionPath?: string;
  readonly createdAt: string;
}

/** A digest the sender claimed: one member's held notifications. */
export interface NotificationDigest {
  readonly id: string;
  readonly userId: string;
  readonly email: string | null;
  readonly channel: string;
  readonly cadence: "daily" | "weekly";
  readonly items: readonly DigestItem[];
}

export type { DigestRunReport } from "../digest.ts";

export interface NotificationDigestsOptions extends BlockOptions {
  /** Sends the digest email: the `mail-sync` block, which `createBlocks` passes. */
  readonly mailer: BlockPorts["mailer"];
  /** The mailbox digests are sent from. */
  readonly accountId: string;
  /** The subject of the email. Default: `Your notifications`. */
  readonly subject?: (digest: NotificationDigest) => string;
}

export interface NotificationDigests {
  /**
   * Claims pending digests (`run_notification_digests` folds them, as the
   * `digest_run` housekeeping job) and sends each as one email. A member with
   * no email address is skipped. The `service` transport runs it.
   */
  sendDue(options?: { readonly limit?: number }): AsyncResult<DigestRunReport>;
}

function digestOf(value: Record<string, unknown>): NotificationDigest {
  const cadence = textOf(value["cadence"]);

  return {
    id: textOf(value["digest_id"]),
    userId: textOf(value["user_id"]),
    email: optionalText(value["email"]) ?? null,
    channel: textOf(value["channel"]),
    cadence: cadence === "weekly" ? "weekly" : "daily",
    items: recordsOf(value["items"], "claim_notification_digests").map(
      (item) => {
        const summary = optionalText(item["summary"]);
        const subjectLabel = optionalText(item["subject_label"]);
        const actionPath = optionalText(item["action_path"]);

        return {
          type: textOf(item["type"]),
          createdAt: textOf(item["created_at"]),
          ...(summary === undefined ? {} : { summary }),
          ...(subjectLabel === undefined ? {} : { subjectLabel }),
          ...(actionPath === undefined ? {} : { actionPath }),
        };
      },
    ),
  };
}

/** The plain text of a digest: one line per notification. */
export function digestText(digest: NotificationDigest): string {
  return digestLines(
    digest.items.map((item) => ({
      label: item.summary ?? item.subjectLabel ?? item.type,
      path: item.actionPath,
    })),
  );
}

/**
 * Sends the digests of members who chose a daily or weekly cadence: one email
 * per member and channel, folding the notifications held since the last one.
 */
export function createNotificationDigests(
  options: NotificationDigestsOptions,
): NotificationDigests {
  const service = blockCall(
    options.service ?? options.transport,
    options.schema,
    options.mappers,
  );

  return {
    sendDue: (run = {}) =>
      runDigests({
        claim: () =>
          service(
            "claim_notification_digests",
            { max_items: run.limit ?? 50 },
            (value) =>
              recordsOf(value, "claim_notification_digests").map(digestOf),
          ),
        send: async (digest, email) => {
          const outcome = await options.mailer.send({
            accountId: options.accountId,
            draft: {
              to: [{ address: email }],
              subject: options.subject?.(digest) ?? "Your notifications",
              text: digestText(digest),
            },
          });

          return outcome.ok
            ? { ok: true, id: outcome.data.id }
            : { ok: false, error: errorText(outcome.error) };
        },
        complete: (digest, outcome) =>
          service(
            "complete_notification_digest",
            {
              digest: digest.id,
              status: outcome.status,
              ...(outcome.status === "sent"
                ? { provider_message_id: outcome.providerMessageId }
                : { error: outcome.error }),
            },
            (status) => status,
          ),
      }),
  };
}
