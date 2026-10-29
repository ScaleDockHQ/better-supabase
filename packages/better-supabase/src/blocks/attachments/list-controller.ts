import type { DbError } from "../../core/errors.ts";
import type { SubscriptionStatus } from "../../realtime/index.ts";
import type { TopicPort } from "../../realtime/watch-topic.ts";
import type { RecordRef } from "../../schema/types.ts";
import type { AuthPort, Controller } from "../controller.ts";
import type { Attachment, Attachments } from "./attachments.ts";

import { defineController, whileSignedIn } from "../controller.ts";

/**
 * The private topic attachment changes go to: `<topic>:<organizationId>`. Pass
 * `blockConfig.attachments.options.topic` when the app renamed it.
 */
export function attachmentsTopic(
  organizationId: string,
  topic = "attachments",
): string {
  return `${topic}:${organizationId}`;
}

export interface AttachmentListControllerOptions<
  F extends object = Record<never, never>,
> {
  readonly client: Pick<Attachments<F>, "list">;
  readonly auth: AuthPort;
  readonly ports: { readonly topic: TopicPort };
  /**
   * The tenant whose attachment broadcasts to hear, the client's own; the
   * controller loads without listening when it is `null`.
   */
  readonly tenant: string | null;
  /** The record whose files to list; `null` lists files without a subject. */
  readonly subject: RecordRef | null;
  /**
   * `blockConfig.attachments.options.topic` from `blocks.generated.ts`; `null`
   * loads without listening.
   */
  readonly topic?: string | null;
}

export interface AttachmentListSnapshot<
  F extends object = Record<never, never>,
> {
  /** `undefined` until the first load. */
  readonly attachments: readonly (Attachment & F)[] | undefined;
  readonly status: SubscriptionStatus;
  readonly error: DbError | undefined;
}

export interface AttachmentListActions {
  readonly refresh: () => Promise<void>;
}

export type AttachmentListController<F extends object = Record<never, never>> =
  Controller<AttachmentListSnapshot<F>, AttachmentListActions>;

/**
 * A record's files, loaded again when anyone in the tenant uploads, replaces or
 * deletes one of them.
 */
export function createAttachmentListController<
  F extends object = Record<never, never>,
>(options: AttachmentListControllerOptions<F>): AttachmentListController<F> {
  const { client, subject, tenant } = options;
  const topic = options.topic === undefined ? "attachments" : options.topic;

  const watched = (payload: unknown): boolean =>
    typeof payload !== "object" ||
    payload === null ||
    !("subjectId" in payload) ||
    !("subjectType" in payload) ||
    (subject === null
      ? payload.subjectType === null
      : payload.subjectType === subject.type &&
        payload.subjectId === subject.id);

  return defineController<AttachmentListSnapshot<F>, AttachmentListActions>(
    { attachments: undefined, status: "closed", error: undefined },
    (state) => {
      let ticket = 0;

      const refresh = async (): Promise<void> => {
        ticket += 1;
        const request = ticket;
        const result = await client.list(subject);

        if (request !== ticket) {
          return;
        }

        state.set(
          result.ok
            ? { attachments: result.data, error: undefined }
            : { error: result.error },
        );
      };

      return {
        actions: { refresh },
        start: () =>
          whileSignedIn(options.auth, () => {
            void refresh();

            const leave =
              topic && tenant !== null
                ? options.ports.topic(attachmentsTopic(tenant, topic), {
                    onMessage: (_event, payload) => {
                      if (watched(payload)) {
                        void refresh();
                      }
                    },
                    onRejoin: () => void refresh(),
                    onStatus: (status) => {
                      state.set({ status });
                    },
                  }).leave
                : undefined;

            return () => {
              leave?.();
            };
          }),
      };
    },
  );
}
