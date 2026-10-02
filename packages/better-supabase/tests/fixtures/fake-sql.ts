import type { SqlClient } from "../../src/postgres/executor.ts";

/** The subset of `pg.Client` the fake answers. */
export interface PgQueryable {
  query<R = Record<string, unknown>>(
    text: string,
    values?: readonly unknown[],
  ): Promise<{ rows: R[] }>;
}

export interface SqlCall {
  readonly text: string;
  readonly values: readonly unknown[];
}

/** Rows to return, or an error to throw (a `pg` error shape or any value). */
export type SqlAnswer =
  | readonly Record<string, unknown>[]
  | { readonly throws: unknown };

export type SqlRule = readonly [
  match: string | RegExp | ((call: SqlCall) => boolean),
  answer: SqlAnswer | ((call: SqlCall) => SqlAnswer),
];

/** A node-postgres error: `code` plus the optional detail fields. */
export function pgError(
  code: string,
  message: string,
  fields: Readonly<Record<string, string>> = {},
): Error & { code: string } {
  return Object.assign(new Error(message), { code, ...fields });
}

function matches(rule: SqlRule[0], call: SqlCall): boolean {
  if (typeof rule === "string") return call.text.includes(rule);
  if (rule instanceof RegExp) return rule.test(call.text);
  return rule(call);
}

/**
 * A scripted SQL client. The first rule whose matcher fits the statement
 * answers it; unmatched statements return no rows. Every call is recorded.
 */
export function fakeSql(rules: readonly SqlRule[] = []): {
  sql: SqlClient & {
    transaction<T>(fn: (c: SqlClient) => Promise<T>): Promise<T>;
  };
  pg: PgQueryable;
  calls: SqlCall[];
  transactions: number;
  texts: () => string[];
} {
  const state = { calls: [] as SqlCall[], transactions: 0 };
  async function answer(text: string, values: readonly unknown[] = []) {
    const call: SqlCall = { text, values };
    state.calls.push(call);
    const rule = rules.find(([match]) => matches(match, call));
    if (!rule) return [];
    const result = typeof rule[1] === "function" ? rule[1](call) : rule[1];
    if ("throws" in result) throw result.throws;
    return [...result];
  }
  const sql: SqlClient & {
    transaction<T>(fn: (c: SqlClient) => Promise<T>): Promise<T>;
  } = {
    // SAFETY: tests script rows that match the statement they answer.
    queryRaw: async <T>(text: string, params?: unknown[]) =>
      (await answer(text, params)) as T[],
    async transaction(fn) {
      state.transactions += 1;
      return fn(sql);
    },
  };
  const pg: PgQueryable = {
    // SAFETY: tests script rows that match the statement they answer.
    query: async <R>(text: string, values?: readonly unknown[]) => ({
      rows: (await answer(text, values)) as R[],
    }),
  };
  return {
    sql,
    pg,
    calls: state.calls,
    get transactions() {
      return state.transactions;
    },
    texts: () => state.calls.map((call) => call.text),
  };
}
