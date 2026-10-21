import type { DbError } from "../../core/errors.ts";
import type { SubscriptionStatus } from "../../realtime/index.ts";
import type { TopicPort } from "../../realtime/watch-topic.ts";
import type { AuthPort, Controller } from "../controller.ts";
import type { ReactionCount, Reactions } from "./reactions.ts";

import { defineController, whileSignedIn } from "../controller.ts";
import { reactionsTopic } from "./reactions.ts";

export interface ReactionsControllerOptions {
  readonly client: Pick<Reactions, "summary" | "react">;
  readonly auth: AuthPort;
  readonly ports: { readonly topic: TopicPort };
  readonly organizationId: string;
  readonly subjectType: string;
  /** The subjects on screen, at most 200; `setSubjects` changes them. */
  readonly subjectIds: readonly string[];
  /**
   * `blockConfig.reactions.options.topic` from `blocks.generated.ts`; `null`
   * loads without listening.
   */
  readonly topic?: string | null;
}

export interface ReactionsSnapshot {
  /** Reactions by subject id; `undefined` until the first load. */
  readonly reactions:
    | Readonly<Record<string, readonly ReactionCount[]>>
    | undefined;
  readonly status: SubscriptionStatus;
  readonly error: DbError | undefined;
}

export interface ReactionsActions {
  /** Adds the emoji, or removes it when the user already reacted with it. */
  readonly toggle: (subjectId: string, emoji: string) => Promise<void>;
  readonly refresh: () => Promise<void>;
  /**
   * Watches other subjects, such as the rows on screen after a scroll, and
   * loads them.
   */
  readonly setSubjects: (subjectIds: readonly string[]) => void;
}

export type ReactionsController = Controller<
  ReactionsSnapshot,
  ReactionsActions
>;

const sameIds = (a: readonly string[], b: readonly string[]): boolean =>
  a.length === b.length && a.every((id, index) => id === b[index]);

/**
 * The reactions of the subjects on screen, loaded again when anyone in the
 * organization reacts to one of them. `toggle` feeds an emoji picker.
 */
export function createReactionsController(
  options: ReactionsControllerOptions,
): ReactionsController {
  const { client, organizationId, subjectType } = options;
  const topic = options.topic === undefined ? "reactions" : options.topic;
  let subjects = [...options.subjectIds];
  let watching = false;

  return defineController<ReactionsSnapshot, ReactionsActions>(
    { reactions: undefined, status: "closed", error: undefined },
    (state) => {
      let ticket = 0;

      const refresh = async (): Promise<void> => {
        const request = ++ticket;

        const result = await client.summary(
          organizationId,
          subjectType,
          subjects,
        );

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
        (payload.subjectType === subjectType &&
          typeof payload.subjectId === "string" &&
          subjects.includes(payload.subjectId));

      return {
        actions: {
          refresh,
          setSubjects: (subjectIds) => {
            if (sameIds(subjects, subjectIds)) {
              return;
            }

            subjects = [...subjectIds];

            if (watching) {
              void refresh();
            }
          },
          toggle: async (subjectId, emoji) => {
            const present = !state
              .get()
              .reactions?.[subjectId]?.some(
                (reaction) => reaction.emoji === emoji && reaction.reacted,
              );

            const result = await client.react(
              organizationId,
              subjectType,
              subjectId,
              emoji,
              { present },
            );

            if (!result.ok) {
              state.set({ error: result.error });

              return;
            }

            state.set((current) => ({
              error: undefined,
              reactions: { ...current.reactions, [subjectId]: result.data },
            }));
          },
        },
        start: () =>
          whileSignedIn(options.auth, () => {
            watching = true;
            void refresh();

            const leave = topic
              ? options.ports.topic(reactionsTopic(organizationId, topic), {
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
