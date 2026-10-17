import type { AuthPort, Controller } from "../../src/blocks/controller.ts";
import type { AuthSnapshot } from "../../src/client/bind.ts";
import type {
  KeyboardPort,
  Shortcut,
  TopicPort,
  TopicWatch,
} from "../../src/client/ports.ts";
import type { AsyncResult } from "../../src/core/result.ts";

import { dbError } from "../../src/core/errors.ts";
import { AsyncResult as Async, ok } from "../../src/core/result.ts";

export const USER = "00000000-0000-4000-8000-0000000000aa";
export const OTHER = "00000000-0000-4000-8000-0000000000bb";

export const signedIn = (id: string = USER): AuthSnapshot => ({
  status: "signed-in",
  user: { id },
  claims: { sub: id },
});

export const SIGNED_OUT: AuthSnapshot = {
  status: "signed-out",
  user: null,
  claims: null,
};

/** An auth port whose session a test switches with `set`. */
export function fakeAuth(initial: AuthSnapshot = signedIn()): AuthPort & {
  readonly set: (next: AuthSnapshot) => void;
  readonly listeners: () => number;
} {
  let snapshot = initial;
  const listeners = new Set<() => void>();

  return {
    current: () => snapshot,
    subscribe: (listener) => {
      listeners.add(listener);

      return () => void listeners.delete(listener);
    },
    set: (next) => {
      snapshot = next;

      for (const listener of [...listeners]) {
        listener();
      }
    },
    listeners: () => listeners.size,
  };
}

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
export function fakeKeyboard(): {
  readonly port: KeyboardPort;
  readonly press: (shortcut: Shortcut) => void;
  readonly bound: () => number;
} {
  const handlers = new Map<string, () => void>();

  const keyOf = (shortcut: Shortcut) =>
    `${shortcut.mod ? "mod+" : ""}${shortcut.key.toLowerCase()}`;

  return {
    port: (shortcut, run) => {
      handlers.set(keyOf(shortcut), run);

      return () => void handlers.delete(keyOf(shortcut));
    },
    press: (shortcut) => handlers.get(keyOf(shortcut))?.(),
    bound: () => handlers.size,
  };
}

/** Subscribes like a binding and returns the snapshot reader and the unsubscribe. */
export function mount<S, A>(
  controller: Controller<S, A>,
): {
  readonly view: () => S & A;
  readonly renders: () => number;
  readonly unmount: () => void;
} {
  let renders = 0;

  const unmount = controller.subscribe(() => {
    renders += 1;
  });

  return {
    view: () => ({ ...controller.getSnapshot(), ...controller.actions }),
    renders: () => renders,
    unmount,
  };
}

export const flush = (): Promise<void> =>
  new Promise((resolve) => {
    setTimeout(resolve, 0);
  });

export const resolved = <T>(data: T): AsyncResult<T> =>
  Async.from(() => Promise.resolve(ok(data)));

export const failed = <T = never>(message: string): AsyncResult<T> =>
  Async.err<T>(dbError("not_found", message));

/** A result that resolves when the test calls `release`. */
export function held<T>(data: T): {
  readonly result: AsyncResult<T>;
  readonly release: () => void;
} {
  let release = (): void => undefined;

  const result = new Async<T>(
    new Promise((resolve) => {
      release = () => {
        resolve(ok(data));
      };
    }),
  );

  return {
    result,
    release: () => {
      release();
    },
  };
}
