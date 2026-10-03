import type { connect, PgQueryable } from "../../../src/cli/db.ts";

/** A `connect` that hands out `client` and records the URLs it opened and the closes. */
export function fakeConnect(client: PgQueryable): {
  connect: typeof connect;
  urls: string[];
  closed: () => number;
} {
  const urls: string[] = [];
  let closed = 0;
  return {
    connect: (url) => {
      urls.push(url);
      return Promise.resolve({
        client,
        close: () => {
          closed += 1;
          return Promise.resolve();
        },
        describe: url.replace(/:[^:@/]+@/, ":***@"),
      });
    },
    urls,
    closed: () => closed,
  };
}
