import type {
  AuthSnapshot,
  TopicPort,
  TopicWatch,
} from "better-supabase/client";

const USER = "00000000-0000-4000-8000-0000000000aa";

export const signedIn = (id: string = USER): AuthSnapshot => ({
  status: "signed-in",
  user: { id },
  claims: { sub: id },
});

interface Joined {
  readonly topic: string;
  readonly watch: TopicWatch;
  left: boolean;
  readonly sent: { event: string; payload: unknown }[];
}

/** A topic port that records joins; a test emits messages, rejoins and status. */
export function fakeTopic(): {
  readonly port: TopicPort;
  readonly joined: Joined[];
  readonly open: () => string[];
  readonly emit: (topic: string, event: string, payload?: unknown) => void;
  readonly rejoin: (topic: string) => void;
  readonly status: (topic: string, status: "subscribed" | "error") => void;
} {
  const joined: Joined[] = [];

  const live = (topic: string) =>
    joined.filter((each) => each.topic === topic && !each.left);

  return {
    joined,
    port: (topic, watch) => {
      const entry: Joined = { topic, watch, left: false, sent: [] };
      joined.push(entry);
      watch.onStatus("joining");
      watch.onStatus("subscribed");

      return {
        leave: () => {
          if (entry.left) {
            return;
          }

          entry.left = true;
          watch.onStatus("closed");
        },
        send: (event, payload) => {
          entry.sent.push({ event, payload });
        },
      };
    },
    open: () => joined.filter((each) => !each.left).map((each) => each.topic),
    emit: (topic, event, payload = {}) => {
      for (const each of live(topic)) {
        each.watch.onMessage(event, payload);
      }
    },
    rejoin: (topic) => {
      for (const each of live(topic)) {
        each.watch.onRejoin();
      }
    },
    status: (topic, status) => {
      for (const each of live(topic)) {
        each.watch.onStatus(status);
      }
    },
  };
}

/** A keyboard port a test presses. */
export const flush = (): Promise<void> =>
  new Promise((resolve) => {
    setTimeout(resolve, 0);
  });
