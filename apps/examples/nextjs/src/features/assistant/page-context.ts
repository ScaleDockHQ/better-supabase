import * as v from "valibot";

/** The record types the assistant can read from the page it was opened on. */
export const PAGE_RECORD_TYPES = [
  "deal",
  "contract",
  "quote",
  "customer",
  "case",
  "agent",
] as const;

export type PageRecordType = (typeof PAGE_RECORD_TYPES)[number];

/**
 * The page the assistant was opened from: its path, and the record when the
 * path is a record page. The client sends it with every message and the route
 * parses it again, since the body is user input.
 */
export const PageContext = v.object({
  path: v.pipe(v.string(), v.maxLength(300)),
  recordType: v.optional(v.picklist(PAGE_RECORD_TYPES)),
  recordId: v.optional(v.pipe(v.string(), v.uuid())),
});

export type PageContext = v.InferOutput<typeof PageContext>;

const RECORD_ROUTES: readonly {
  readonly prefix: string;
  readonly type: PageRecordType;
}[] = [
  { prefix: "/crm/deals/", type: "deal" },
  { prefix: "/crm/contracts/", type: "contract" },
  { prefix: "/crm/quotes/", type: "quote" },
  { prefix: "/customers/", type: "customer" },
  { prefix: "/cases/", type: "case" },
  { prefix: "/assistant/agents/", type: "agent" },
];

const ID = v.pipe(v.string(), v.uuid());

/**
 * The context of a pathname without its locale prefix. A path under a record
 * route whose next segment is an id also names the record.
 */
export function pageContextOf(pathname: string): PageContext {
  const path = pathname.slice(0, 300);

  for (const route of RECORD_ROUTES) {
    if (!path.startsWith(route.prefix)) {
      continue;
    }

    const id = path.slice(route.prefix.length).split("/")[0] ?? "";

    if (v.is(ID, id)) {
      return { path, recordType: route.type, recordId: id };
    }
  }

  return { path };
}

/** The request body the panel sends: the page context next to the messages. */
export const PageContextBody = v.object({ pageContext: PageContext });

/** The context a parsed body carries; `undefined` when it has none. */
export function pageContextOfBody(
  parsed: v.SafeParseResult<typeof PageContextBody> | undefined,
): PageContext | undefined {
  return parsed?.success ? parsed.output.pageContext : undefined;
}
