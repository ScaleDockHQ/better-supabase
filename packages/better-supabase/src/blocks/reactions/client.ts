import type { DbError } from "../../core/errors.ts";
import type { SubscriptionStatus } from "../../realtime/index.ts";
import type { TopicPort } from "../../realtime/watch-topic.ts";
import type { RecordRef } from "../../schema/types.ts";
import type { AuthPort, Controller } from "../controller.ts";
import type { ReactionCount, Reactions } from "./reactions.ts";

import { subjectKey } from "../../core/block-subjects.ts";
import { defineController, whileSignedIn } from "../controller.ts";
import { reactionsTopic } from "./reactions.ts";

export interface ReactionsControllerOptions {
  readonly client: Pick<Reactions, "summary" | "react">;
  readonly auth: AuthPort;
  readonly ports: { readonly topic: TopicPort };
  /**
   * The tenant whose reaction broadcasts to hear, the client's own; the
   * controller waits without one.
   */
  readonly tenant: string | null;
  /**
   * The subjects on screen, at most 200 of each type; `setSubjects` changes
   * them.
   */
  readonly subjects: readonly RecordRef[];
  /**
   * `blockConfig.reactions.options.topic` from `blocks.generated.ts`; `null`
   * loads without listening.
   */
  readonly topic?: string | null;
}

export interface ReactionsSnapshot {
  /**
   * Reactions keyed by `subjectKey(subject)` (`type:id`); `undefined` until the
   * first load.
   */
  readonly reactions:
    | Readonly<Record<string, readonly ReactionCount[]>>
    | undefined;
  readonly status: SubscriptionStatus;
  readonly error: DbError | undefined;
}

export interface ReactionsActions {
  /** Adds the emoji, or removes it when the user already reacted with it. */
  readonly toggle: (input: {
    subject: RecordRef;
    emoji: string;
  }) => Promise<void>;
  readonly refresh: () => Promise<void>;
  /**
   * Watches other subjects, such as the rows on screen after a scroll, and
   * loads them.
   */
  readonly setSubjects: (subjects: readonly RecordRef[]) => void;
}

export type ReactionsController = Controller<
  ReactionsSnapshot,
  ReactionsActions
>;

const sameSubjects = (
  a: readonly RecordRef[],
  b: readonly RecordRef[],
): boolean =>
  a.length === b.length &&
  a.every((subject, index) => {
    const other = b[index];

    return (
      other !== undefined &&
      subject.type === other.type &&
      subject.id === other.id
    );
  });

/**
 * The reactions of the subjects on screen, loaded again when anyone in the
 * tenant reacts to one of them. `toggle` feeds an emoji picker.
 */
export function createReactionsController(
  options: ReactionsControllerOptions,
): ReactionsController {
  const { client, tenant } = options;
  const topic = options.topic === undefined ? "reactions" : options.topic;
  let subjects = [...options.subjects];
  let watching = false;

  return defineController<ReactionsSnapshot, ReactionsActions>(
    { reactions: undefined, status: "closed", error: undefined },
    (state) => {
      let ticket = 0;

      const refresh = async (): Promise<void> => {
        if (tenant === null) {
          return;
        }

        ticket += 1;
        const request = ticket;

        const result = await client.summary(subjects);

        if (request !== ticket) {
          return;
        }

        state.set(
          result.ok
            ? { reactions: result.data, error: undefined }
            : { error: result.error },
        );
      };

      const watched = (payload: unknown): boolean =>
        typeof payload !== "object" ||
        payload === null ||
        !("subjectId" in payload) ||
        !("subjectType" in payload) ||
        subjects.some(
          (subject) =>
            subject.type === payload.subjectType &&
            subject.id === payload.subjectId,
        );

      return {
        actions: {
          refresh,
          setSubjects: (next) => {
            if (sameSubjects(subjects, next)) {
              return;
            }

            subjects = [...next];

            if (watching) {
              void refresh();
            }
          },
          toggle: async ({ subject, emoji }) => {
            const key = subjectKey(subject);

            const present = !state
              .get()
              .reactions?.[key]?.some(
                (reaction) => reaction.emoji === emoji && reaction.reacted,
              );

            const result = await client.react({ subject, emoji, present });

            if (!result.ok) {
              state.set({ error: result.error });

              return;
            }

            state.set((current) => ({
              error: undefined,
              reactions: { ...current.reactions, [key]: result.data },
            }));
          },
        },
        start: () =>
          tenant === null
            ? undefined
            : whileSignedIn(options.auth, () => {
                watching = true;
                void refresh();

                const leave = topic
                  ? options.ports.topic(reactionsTopic(tenant, topic), {
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
                  watching = false;
                  leave?.();
                };
              }),
      };
    },
  );
}
