export const CHANNEL_ADAPTERS = ["whatsapp", "slack"] as const;

export type ChannelAdapterName = (typeof CHANNEL_ADAPTERS)[number];

export const isChannelAdapter = (value: string): value is ChannelAdapterName =>
  CHANNEL_ADAPTERS.some((name) => name === value);

const SLACK_TOLERANCE_SECONDS = 300;
const HEX_PAIR = /[0-9a-f]{2}/giu;

function fromHex(hex: string): Uint8Array<ArrayBuffer> | null {
  const pairs = hex.match(HEX_PAIR);

  if (pairs === null || pairs.length * 2 !== hex.length) {
    return null;
  }

  return Uint8Array.from(pairs, (pair) => Number.parseInt(pair, 16));
}

/** Checks an HMAC-SHA256 hex signature in constant time with Web Crypto. */
async function hmacMatches(
  secret: string,
  signedText: string,
  signatureHex: string,
): Promise<boolean> {
  const signature = fromHex(signatureHex);

  if (signature === null) {
    return false;
  }

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );

  return crypto.subtle.verify(
    "HMAC",
    key,
    signature,
    new TextEncoder().encode(signedText),
  );
}

/** Meta signs the raw body: `X-Hub-Signature-256: sha256=<hex>`. */
export async function verifyWhatsapp(
  secret: string,
  request: Request,
  body: string,
): Promise<boolean> {
  const header = request.headers.get("x-hub-signature-256") ?? "";

  return header.startsWith("sha256=")
    ? hmacMatches(secret, body, header.slice("sha256=".length))
    : false;
}

/** Slack signs `v0:<timestamp>:<body>` and rejects a stale timestamp. */
export async function verifySlack(
  secret: string,
  request: Request,
  body: string,
  nowSeconds: number,
): Promise<boolean> {
  const timestamp = request.headers.get("x-slack-request-timestamp") ?? "";
  const header = request.headers.get("x-slack-signature") ?? "";

  if (
    !/^\d+$/u.test(timestamp) ||
    Math.abs(nowSeconds - Number(timestamp)) > SLACK_TOLERANCE_SECONDS ||
    !header.startsWith("v0=")
  ) {
    return false;
  }

  return hmacMatches(
    secret,
    `v0:${timestamp}:${body}`,
    header.slice("v0=".length),
  );
}
