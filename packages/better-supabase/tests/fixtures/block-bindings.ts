import type { ClientLike } from "../../src/bindings/client.ts";
import type { AuthPort, Controller } from "../../src/blocks/controller.ts";
import type { TopicPort } from "../../src/realtime/watch-topic.ts";

import { defineController } from "../../src/blocks/controller.ts";
import { fakeAuth, fakeTopic } from "./ports.ts";

/** Options of a controller that takes the provider's session and ports. */
export interface EnvOptions {
  readonly auth: AuthPort;
  readonly ports: { readonly topic: TopicPort };
}

export const fakeEnv = (): EnvOptions => ({
  auth: fakeAuth(),
  ports: { topic: fakeTopic().port },
});

/** A client for a framework provider; the block bindings read only `supabase`, `auth` and `ports`. */
export const fakeBlockClient = (): ClientLike =>
  // SAFETY: see above; nothing reads `db`, `queries` or `betterSupabase`.
  ({
    supabase: { name: "supabase" },
    ...fakeEnv(),
  }) as unknown as ClientLike;

type Counter = Controller<{ readonly label: string }, object>;

/** A controller factory that records its options and counts how often its work starts. */
export function startCounter(): {
  readonly create: (
    options: EnvOptions & { readonly label?: string },
  ) => Counter;
  readonly given: () => (EnvOptions & { readonly label?: string }) | undefined;
  readonly starts: () => number;
} {
  let given: (EnvOptions & { readonly label?: string }) | undefined;
  let starts = 0;
  return {
    create: (options) => {
      given = options;
      return defineController({ label: "initial" }, () => ({
        actions: {},
        start: () => {
          starts += 1;
          return () => undefined;
        },
      }));
    },
    given: () => given,
    starts: () => starts,
  };
}
