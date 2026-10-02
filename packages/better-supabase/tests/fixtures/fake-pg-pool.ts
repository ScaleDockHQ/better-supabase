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
} {
  const state = { log: [] as string[], connections: 0, released: 0, ended: 0 };
  const pool: PgPool = {
    async connect() {
      state.connections += 1;
      const client: PgPoolClient = {
        async query(text, values = []) {
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
  };
}
