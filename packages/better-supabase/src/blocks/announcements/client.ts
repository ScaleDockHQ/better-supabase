import type { DbError } from "../../core/errors.ts";
import type { SubscriptionStatus } from "../../realtime/index.ts";
import type { TopicPort } from "../../realtime/watch-topic.ts";
import type { AuthPort, Controller } from "../controller.ts";
import type { Announcement, Announcements } from "./announcements.ts";

import { defineController, whileSignedIn } from "../controller.ts";

export interface AnnouncementsControllerOptions {
  readonly client: Pick<Announcements, "listActive" | "dismiss">;
  readonly auth: AuthPort;
  readonly ports: { readonly topic: TopicPort };
  /** The active tenant, for tenant, role and plan audiences. */
  readonly organizationId?: string | null;
  /** The topic the module broadcasts to (`blockConfig.announcements.options.topic` from `blocks.generated.ts`); `null` loads once. */
  readonly topic?: string | null;
}

export interface AnnouncementsSnapshot {
  /** `undefined` until the first load. */
  readonly items: readonly Announcement[] | undefined;
  readonly status: SubscriptionStatus;
  readonly error: DbError | undefined;
}

export interface AnnouncementsActions {
  /** Hides one for the user, then drops it from `items`. */
  readonly dismiss: (announcementId: string) => Promise<void>;
  readonly refresh: () => Promise<void>;
}

export type AnnouncementsController = Controller<
  AnnouncementsSnapshot,
  AnnouncementsActions
>;

/**
 * The signed-in user's live announcements, loaded again whenever staff
 * publish, change or remove one.
 */
export function createAnnouncementsController(
  options: AnnouncementsControllerOptions,
): AnnouncementsController {
  const { client } = options;
  const organizationId = options.organizationId ?? null;
  const topic = options.topic === undefined ? "announcements" : options.topic;
  return defineController<AnnouncementsSnapshot, AnnouncementsActions>(
    { items: undefined, status: "closed", error: undefined },
    (state) => {
      const refresh = async (): Promise<void> => {
        const run = state.run();
        const result = await client.listActive(organizationId);
        if (run !== state.run()) return;
        state.set(
          result.ok
            ? { items: result.data, error: undefined }
            : { error: result.error },
        );
      };
      return {
        actions: {
          refresh,
          dismiss: async (announcementId) => {
            const result = await client.dismiss(announcementId);
            if (!result.ok) {
              state.set({ error: result.error });
              return;
            }
            state.set((current) => ({
              items: current.items?.filter(
                (item) => item.id !== announcementId,
              ),
            }));
          },
        },
        start: () =>
          whileSignedIn(options.auth, () => {
            void refresh();
            if (!topic) return;
            return options.ports.topic(topic, {
              onMessage: () => void refresh(),
              onRejoin: () => void refresh(),
              onStatus: (status) => {
                state.set({ status });
              },
            }).leave;
          }),
      };
    },
  );
}
