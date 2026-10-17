import type { SupabaseClient } from "@supabase/supabase-js";

import type { TableMeta } from "../../schema/types.ts";

type Rename = (name: string) => string;

type Fetch = typeof fetch;

interface ChangesFilter {
  readonly schema?: string;
  readonly filter?: string;
  readonly [key: string]: unknown;
}

interface ChangesPayload {
  readonly new?: unknown;
  readonly old?: unknown;
  readonly [key: string]: unknown;
}

const PLAIN_PARAMS = new Set(["limit", "offset"]);
const LIST_PARAMS = new Set(["columns", "on_conflict", "order", "select"]);
const LOGIC_PARAM = /^(not\.)?(and|or)$/;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function renameRows(
  value: unknown,
  names: ReadonlyMap<string, string>,
): unknown {
  if (Array.isArray(value)) {
    return value.map((row) => renameRows(row, names));
  }

  if (!isRecord(value)) {
    return value;
  }

  return Object.fromEntries(
    Object.entries(value).map(([key, item]) => [names.get(key) ?? key, item]),
  );
}

/** Index of the first `,` or `)` outside quotes and nested parentheses. */
function valueEnd(text: string, start: number): number {
  let depth = 0;
  let quoted = false;
  let index = start;

  for (; index < text.length; index += 1) {
    const char = text[index];

    if (quoted) {
      if (char === "\\") {
        index += 1;
      } else if (char === '"') {
        quoted = false;
      }
    } else if (char === '"') {
      quoted = true;
    } else if (char === "(") {
      depth += 1;
    } else if (char === ")") {
      if (depth === 0) {
        break;
      }

      depth -= 1;
    } else if (char === "," && depth === 0) {
      break;
    }
  }

  return index;
}

/** Renames the columns in a PostgREST logic tree: `(a.eq.1,and(b.gt.2,c.is.null))`. */
function renameLogic(text: string, rename: Rename): string {
  let out = "";
  let index = 0;

  while (index < text.length) {
    const char = text[index];

    if (char === "(" || char === ")" || char === ",") {
      out += char;
      index += 1;
      continue;
    }

    let end = index;

    while (end < text.length && !".(),".includes(text[end] ?? "")) {
      end += 1;
    }

    const token = text.slice(index, end);

    if (text[end] === "(") {
      out += token;
      index = end;
    } else if (token === "not" && /^\.(and|or)\(/.test(text.slice(end))) {
      out += "not.";
      index = end + 1;
    } else {
      const stop = valueEnd(text, end);
      out += rename(token) + text.slice(end, stop);
      index = stop;
    }
  }

  return out;
}

/** Renames the head of `column.asc`, `alias:column.sum()` or `column::text`. */
function renameHead(item: string, rename: Rename): string {
  const colon = /^[^.:(]*:(?!:)/.exec(item)?.[0] ?? "";
  const rest = item.slice(colon.length);
  const head = /^[^.:(]*/.exec(rest)?.[0] ?? "";

  return colon + rename(head) + rest.slice(head.length);
}

function renameSearch(
  search: URLSearchParams,
  rename: Rename,
): URLSearchParams {
  const out = new URLSearchParams();

  for (const [key, value] of search) {
    if (PLAIN_PARAMS.has(key)) {
      out.append(key, value);
    } else if (LIST_PARAMS.has(key)) {
      out.append(
        key,
        value
          .split(",")
          .map((item) => renameHead(item, rename))
          .join(","),
      );
    } else if (LOGIC_PARAM.test(key)) {
      out.append(key, renameLogic(value, rename));
    } else {
      out.append(rename(key), value);
    }
  }

  return out;
}

/** Renames the columns in a Realtime filter list: `a=eq.1,b=in.("x,y")`. */
function renameRealtimeFilter(text: string, rename: Rename): string {
  let out = "";
  let index = 0;

  while (index < text.length) {
    const equals = text.indexOf("=", index);

    if (equals === -1) {
      return out + text.slice(index);
    }

    const stop = valueEnd(text, equals + 1);
    const tail = text[stop] === "," ? stop : text.length;
    out += rename(text.slice(index, equals)) + text.slice(equals, tail);
    index = tail;

    if (text[index] === ",") {
      out += ",";
      index += 1;
    }
  }

  return out;
}

function renamingFetch(
  inner: Fetch,
  rename: Rename,
  toApp: ReadonlyMap<string, string>,
  toDb: ReadonlyMap<string, string>,
): Fetch {
  return async (input, init) => {
    const url = new URL(input instanceof Request ? input.url : String(input));
    url.search = renameSearch(url.searchParams, rename).toString();

    const request: RequestInit =
      typeof init?.body === "string" && init.body !== ""
        ? {
            ...init,
            body: JSON.stringify(renameRows(JSON.parse(init.body), toDb)),
          }
        : { ...init };

    const response = await inner(url.toString(), request);
    const type = response.headers.get("content-type") ?? "";

    if (!response.ok || !type.includes("json")) {
      return response;
    }

    const text = await response.text();

    return new Response(
      text === "" ? null : JSON.stringify(renameRows(JSON.parse(text), toApp)),
      {
        status: response.status,
        statusText: response.statusText,
        headers: response.headers,
      },
    );
  };
}

function bound<T extends object>(target: T, prop: string | symbol): unknown {
  // SAFETY: a Proxy trap forwards any property of the wrapped object.
  const value = (target as Record<string | symbol, unknown>)[prop];

  return typeof value === "function" ? value.bind(target) : value;
}

/**
 * The client `@supabase-labs/tanstack-db` sees for one table: requests and
 * Realtime listeners run in the table's schema, and when app names differ
 * from column names, rows arrive in app names and leave in column names.
 */
export function tableClient(
  supabase: SupabaseClient,
  table: TableMeta,
): SupabaseClient {
  const toDb = new Map<string, string>();
  const toApp = new Map<string, string>();

  for (const [name, column] of Object.entries(table.columns)) {
    if (name !== column.db) {
      toDb.set(name, column.db);
      toApp.set(column.db, name);
    }
  }

  if (table.schema === "public" && toDb.size === 0) {
    return supabase;
  }

  const rename: Rename = (name) => toDb.get(name) ?? name;
  const channels = new WeakMap<object, unknown>();

  const from = (name: string): unknown => {
    const builder =
      table.schema === "public"
        ? supabase.from(name)
        : supabase.schema(table.schema).from(name);

    if (toDb.size === 0) {
      return builder;
    }

    const fetch = renamingFetch(
      builder.fetch ?? globalThis.fetch,
      rename,
      toApp,
      toDb,
    );

    return new Proxy(builder, {
      get: (target, prop) => (prop === "fetch" ? fetch : bound(target, prop)),
    });
  };

  const channel = (...args: Parameters<SupabaseClient["channel"]>): unknown => {
    const real = supabase.channel(...args);

    const proxy: object = new Proxy(real, {
      get: (target, prop) => {
        if (prop !== "on") {
          return bound(target, prop);
        }

        return (
          type: string,
          filter: ChangesFilter,
          callback: (payload: ChangesPayload) => void,
        ) => {
          if (type !== "postgres_changes") {
            // SAFETY: other channel events pass through unchanged.
            (target.on as (...rest: unknown[]) => unknown)(
              type,
              filter,
              callback,
            );

            return proxy;
          }

          const scoped: ChangesFilter = {
            ...filter,
            schema: table.schema,
            ...(filter.filter === undefined
              ? {}
              : { filter: renameRealtimeFilter(filter.filter, rename) }),
          };

          // SAFETY: the overload for postgres_changes takes this filter and callback.
          (target.on as (...rest: unknown[]) => unknown)(
            type,
            scoped,
            (payload: ChangesPayload) => {
              callback({
                ...payload,
                new: renameRows(payload.new, toApp),
                old: renameRows(payload.old, toApp),
              });
            },
          );

          return proxy;
        };
      },
    });

    channels.set(proxy, real);

    return proxy;
  };

  const removeChannel = (proxy: object): unknown =>
    // SAFETY: removeChannel receives a channel from channel() above.
    supabase.removeChannel((channels.get(proxy) ?? proxy) as never);

  const overrides = new Map<string | symbol, unknown>([
    ["from", from],
    ["channel", channel],
    ["removeChannel", removeChannel],
  ]);

  return new Proxy(supabase, {
    get: (target, prop) =>
      overrides.has(prop) ? overrides.get(prop) : bound(target, prop),
  });
}
