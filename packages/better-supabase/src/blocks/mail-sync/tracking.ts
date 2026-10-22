/**
 * At most this many links in one message are tracked; the rest stay as they
 * are.
 */
const MAX_LINKS = 100;

const MAX_URL = 2048;

const HREF = /(<a\b[^>]*?\bhref\s*=\s*)(["'])(https?:\/\/[^"']+)\2/giu;

const TOKEN = /^[A-Za-z0-9_-]{43}$/u;

/** The transparent 1x1 GIF the open pixel answers with. */
const PIXEL = Uint8Array.of(
  0x47,
  0x49,
  0x46,
  0x38,
  0x39,
  0x61,
  0x01,
  0x00,
  0x01,
  0x00,
  0x80,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0xff,
  0xff,
  0xff,
  0x21,
  0xf9,
  0x04,
  0x01,
  0x00,
  0x00,
  0x00,
  0x00,
  0x2c,
  0x00,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x01,
  0x00,
  0x00,
  0x02,
  0x01,
  0x44,
  0x00,
  0x3b,
);

/** A tracked message: the HTML to send, and what `record_sent_mail` stores. */
export interface TrackedHtml {
  readonly html: string;
  /** The SHA-256 of the token in the message's tracking URLs, in hex. */
  readonly hash: string;
  /** The original link URLs, by position. */
  readonly links: readonly string[];
}

const base64url = (bytes: Uint8Array): string =>
  btoa(String.fromCodePoint(...bytes))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/[=]+$/u, "");

/** The SHA-256 of a tracking token, in hex. */
export async function trackingHash(token: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(token),
  );

  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

const decode = (url: string): string => url.replaceAll("&amp;", "&");

/**
 * Rewrites a message's `http(s)` links to go through `baseUrl/c/<token>/<n>`
 * and adds an open pixel at `baseUrl/o/<token>`. The token is random and only
 * its hash is stored, so a URL can't be guessed from the database.
 */
export async function trackHtml(
  html: string,
  baseUrl: string,
): Promise<TrackedHtml> {
  const token = base64url(crypto.getRandomValues(new Uint8Array(32)));
  const base = baseUrl.replace(/\/+$/u, "");
  const links: string[] = [];

  const rewritten = html.replaceAll(
    HREF,
    (whole, start: string, quote: string, url: string) => {
      const target = decode(url);

      if (links.length >= MAX_LINKS || target.length > MAX_URL) {
        return whole;
      }

      links.push(target);

      return `${start}${quote}${base}/c/${token}/${String(links.length - 1)}${quote}`;
    },
  );

  const pixel = `<img src="${base}/o/${token}" width="1" height="1" alt="" style="display:none">`;
  const closing = rewritten.search(/<\/body>/iu);

  return {
    html:
      closing === -1
        ? `${rewritten}${pixel}`
        : `${rewritten.slice(0, closing)}${pixel}${rewritten.slice(closing)}`,
    hash: await trackingHash(token),
    links,
  };
}

/** A tracking request: an open, or a click on the link at `position`. */
export type TrackingHit =
  | { readonly kind: "open"; readonly token: string }
  | {
      readonly kind: "click";
      readonly token: string;
      readonly position: number;
    };

/** Reads `.../o/<token>` or `.../c/<token>/<n>` from a request URL. */
export function trackingHitOf(url: string): TrackingHit | undefined {
  const parts = new URL(url).pathname.split("/").filter(Boolean);
  const [kind, token, position] = parts.slice(parts.at(-3) === "c" ? -3 : -2);

  if (token === undefined || !TOKEN.test(token)) {
    return undefined;
  }

  if (kind === "o" && position === undefined) {
    return { kind: "open", token };
  }

  if (kind === "c" && position !== undefined && /^\d{1,3}$/u.test(position)) {
    return { kind: "click", token, position: Number(position) };
  }

  return undefined;
}

/** The open pixel's response: never cached, so each open reaches the route. */
export function pixelResponse(): Response {
  return new Response(PIXEL, {
    headers: {
      "content-type": "image/gif",
      "cache-control": "no-store, max-age=0",
    },
  });
}
