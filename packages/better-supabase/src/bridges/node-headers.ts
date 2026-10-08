/** Node's request headers: a string, an array of strings, or absent. */
export type NodeIncomingHeaders = Readonly<
  Record<string, string | readonly string[] | undefined>
>;

/** The part of a Node `IncomingMessage` a URL and headers need; no stream is read. */
export interface NodeRequestHead {
  readonly method?: string | undefined;
  readonly url?: string | undefined;
  readonly headers: NodeIncomingHeaders;
  readonly socket?: object | undefined;
}

function first(
  value: string | readonly string[] | undefined,
): string | undefined {
  return typeof value === "string" ? value : value?.[0];
}

/** Node's headers as `Headers`; HTTP/2 pseudo-headers (`:path`) are dropped. */
export function toWebHeaders(incoming: NodeIncomingHeaders): Headers {
  const headers = new Headers();
  for (const [name, value] of Object.entries(incoming)) {
    if (value === undefined || name.startsWith(":")) continue;
    if (typeof value === "string") headers.set(name, value);
    else for (const item of value) headers.append(name, item);
  }
  return headers;
}

function originOf(req: NodeRequestHead, trustProxy: boolean): string {
  const forwardedProto = trustProxy
    ? first(req.headers["x-forwarded-proto"])?.split(",")[0]?.trim()
    : undefined;
  const socket = req.socket;
  const encrypted =
    socket !== undefined && "encrypted" in socket && socket.encrypted === true;
  const protocol = forwardedProto ?? (encrypted ? "https" : "http");
  const forwardedHost = trustProxy
    ? first(req.headers["x-forwarded-host"])?.split(",")[0]?.trim()
    : undefined;
  const host = forwardedHost ?? first(req.headers["host"]) ?? "localhost";
  return `${protocol}://${host}`;
}

/**
 * The absolute URL of a Node request. Express keeps the mounted path in
 * `originalUrl`; `x-forwarded-*` count only with `trustProxy`.
 */
export function nodeRequestUrl(req: NodeRequestHead, trustProxy = false): URL {
  const path =
    "originalUrl" in req && typeof req.originalUrl === "string"
      ? req.originalUrl
      : (req.url ?? "/");
  return new URL(path, originOf(req, trustProxy));
}

/** A body-less `Request` with a Node request's method, URL and headers. */
export function headRequest(req: NodeRequestHead, trustProxy = false): Request {
  return new Request(nodeRequestUrl(req, trustProxy), {
    method: req.method ?? "GET",
    headers: toWebHeaders(req.headers),
  });
}

/** The part of a Node `ServerResponse` header writes need. */
export interface NodeHeaderTarget {
  getHeader(name: string): number | string | readonly string[] | undefined;
  setHeader(name: string, value: number | string | readonly string[]): unknown;
}

/**
 * Copies a `Response`'s headers onto a Node response: `set-cookie` and
 * `server-timing` are appended to what is already there, the rest replaced.
 */
export function applyWebHeaders(
  target: NodeHeaderTarget,
  headers: Headers,
): void {
  const append = (name: string, values: readonly string[]): void => {
    if (values.length === 0) return;
    const existing = target.getHeader(name);
    const before =
      existing === undefined
        ? []
        : typeof existing === "object"
          ? existing
          : [String(existing)];
    target.setHeader(name, [...before, ...values]);
  };
  append("set-cookie", headers.getSetCookie());
  for (const [name, value] of headers) {
    if (name === "set-cookie") continue;
    if (name === "server-timing") append(name, [value]);
    else target.setHeader(name, value);
  }
}
