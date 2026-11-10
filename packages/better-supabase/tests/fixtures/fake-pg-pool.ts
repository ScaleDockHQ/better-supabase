import type { PgPool, PgPoolClient } from "../../src/postgres/pool.ts";

/**
 * A `pg.Pool` stand-in that records every statement per connection. `answer`
 * returns rows for a statement or throws to fail it.
 */
export function fakePgPool(
  answer: (text: string, values: readonly unknown[]) => unknown[] = () => [],
): {
  pool: PgPool;
  log: string[];
  connections: number;
  released: number;
  ended: number;
  /** Messages sent to the server: `begin` and the settings count as one. */
  messages: number;
} {
  const state = {
    log: [] as string[],
    connections: 0,
    released: 0,
    ended: 0,
    messages: 0,
  };

  const pool: PgPool = {
    async connect() {
      state.connections += 1;

      const client: PgPoolClient = {
        async query(text, values = []) {
          state.messages += 1;

          // One simple message opens the transaction and sets the claims; the log and the
          // answer see it as the two statements it holds, with the literals read back.
          const combined =
            /^(begin(?: read only)?);select (set_config\(.*\))$/s.exec(text);

          if (combined) {
            const settings = [
              ...combined[2]!.matchAll(/E'((?:[^']|'')*)'/g),
            ].map((match) =>
              match[1]!.replaceAll("''", "'").replaceAll("\\\\", "\\"),
            );

            const calls = settings.length / 2;

            const settingsText = `select ${Array.from({ length: calls }, (_, index) => `set_config($${index * 2 + 1}, $${index * 2 + 2}, true)`).join(", ")}`;

            state.log.push(combined[1]!, settingsText);
            answer(combined[1]!, []);

            return { rows: answer(settingsText, settings) };
          }

          state.log.push(text);

          return { rows: answer(text, values) };
        },
        release() {
          state.released += 1;
        },
      };

      return client;
    },
    async end() {
      state.ended += 1;
    },
  };

  return {
    pool,
    log: state.log,
    get connections() {
      return state.connections;
    },
    get released() {
      return state.released;
    },
    get ended() {
      return state.ended;
    },
    get messages() {
      return state.messages;
    },
  };
}
