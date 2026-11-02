import type { AsyncResult } from "../../core/result.ts";
import type { BlockPorts } from "../ports.ts";
import type { BlockOptions } from "../shared.ts";

import { ok } from "../../core/result.ts";
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

/** What one `sendDue` call did. */
export interface DigestRunReport {
  readonly claimed: number;
  readonly sent: number;
  readonly failed: number;
  readonly skipped: number;
}

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
  return digest.items
    .map((item) => {
      const label = item.summary ?? item.subjectLabel ?? item.type;

      return `- ${label}${item.actionPath === undefined ? "" : ` (${item.actionPath})`}`;
    })
    .join("\n");
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
      service(
        "claim_notification_digests",
        { max_items: run.limit ?? 50 },
        (value) => recordsOf(value, "claim_notification_digests").map(digestOf),
      ).andThen(async (digests) => {
        let sent = 0;
        let failed = 0;
        let skipped = 0;

        for (const digest of digests) {
          if (digest.email === null) {
            skipped += 1;

            const done = await service(
              "complete_notification_digest",
              {
                digest: digest.id,
                status: "skipped",
                error: "The member has no email address",
              },
              () => true,
            );

            if (!done.ok) {
              return done;
            }

            continue;
          }

          const outcome = await options.mailer.send({
            accountId: options.accountId,
            draft: {
              to: [{ address: digest.email }],
              subject: options.subject?.(digest) ?? "Your notifications",
              text: digestText(digest),
            },
          });

          const done = await service(
            "complete_notification_digest",
            outcome.ok
              ? {
                  digest: digest.id,
                  status: "sent",
                  provider_message_id: outcome.data.id,
                }
              : {
                  digest: digest.id,
                  status: "pending",
                  error: errorText(outcome.error),
                },
            (status) => status,
          );

          if (!done.ok) {
            return done;
          }

          if (outcome.ok) {
            sent += 1;
          } else {
            failed += 1;
          }
        }

        return ok({ claimed: digests.length, sent, failed, skipped });
      }),
  };
}
