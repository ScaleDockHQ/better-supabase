/** Decides whether a webhook may be sent to `url`. Rejecting counts as `false`. */
export type AllowUrl = (url: URL) => boolean | Promise<boolean>;

/** The addresses a host name resolves to. */
export type ResolveHost = (hostname: string) => Promise<readonly string[]>;

export interface PublicUrlOptions {
  /**
   * Resolves host names so each address can be checked. Defaults to
   * `node:dns` where the runtime has it (Node, Bun, Deno); pass one on other
   * runtimes, or `false` to check only the URL.
   */
  readonly resolve?: ResolveHost | false;
  /** Allow `http:` URLs, e.g. for local development. */
  readonly allowHttp?: boolean;
  /** Host names that skip every check, e.g. an internal receiver you trust. */
  readonly allowHosts?: readonly string[];
}

const PRIVATE_V4: readonly (readonly [number, number])[] = [
  [0x00_00_00_00, 8],
  [0x0a_00_00_00, 8],
  [0x64_40_00_00, 10],
  [0x7f_00_00_00, 8],
  [0xa9_fe_00_00, 16],
  [0xac_10_00_00, 12],
  [0xc0_00_00_00, 24],
  [0xc0_00_02_00, 24],
  [0xc0_a8_00_00, 16],
  [0xc6_12_00_00, 15],
  [0xc6_33_64_00, 24],
  [0xcb_00_71_00, 24],
  [0xe0_00_00_00, 4],
  [0xf0_00_00_00, 4],
];

function v4(address: string): number | undefined {
  const parts = address.split(".");
  if (parts.length !== 4) return undefined;
  let value = 0;
  for (const part of parts) {
    if (!/^\d{1,3}$/.test(part)) return undefined;
    const octet = Number(part);
    if (octet > 255) return undefined;
    value = value * 256 + octet;
  }
  return value;
}

const publicV4 = (value: number): boolean =>
  !PRIVATE_V4.some(
    ([base, bits]) =>
      Math.floor(value / 2 ** (32 - bits)) ===
      Math.floor(base / 2 ** (32 - bits)),
  );

function v6(address: string): number[] | undefined {
  let text = address.toLowerCase();
  const zone = text.indexOf("%");
  if (zone !== -1) text = text.slice(0, zone);
  if (text.includes(".")) {
    const colon = text.lastIndexOf(":");
    const embedded = v4(text.slice(colon + 1));
    if (embedded === undefined) return undefined;
    const high = Math.floor(embedded / 65_536).toString(16);
    const low = (embedded % 65_536).toString(16);
    text = `${text.slice(0, colon + 1)}${high}:${low}`;
  }
  const halves = text.split("::");
  if (halves.length > 2) return undefined;
  const groups = (part: string) => (part === "" ? [] : part.split(":"));
  const head = groups(halves[0]!);
  const rest = halves.length === 2 ? groups(halves[1]!) : [];
  if (![...head, ...rest].every((group) => /^[0-9a-f]{1,4}$/.test(group)))
    return undefined;
  const known = head.length + rest.length;
  if (halves.length === 1 ? known !== 8 : known > 7) return undefined;
  return [
    ...head,
    ...Array.from({ length: 8 - known }, () => "0"),
    ...rest,
  ].map((group) => Number.parseInt(group, 16));
}

function publicV6(groups: readonly number[]): boolean {
  const [first = 0] = groups;
  const zeros = (from: number, to: number) =>
    groups.slice(from, to).every((group) => group === 0);
  const embedded = groups[6]! * 65_536 + groups[7]!;
  if (zeros(0, 8)) return false;
  if (zeros(0, 7) && groups[7] === 1) return false;
  // IPv4-mapped (::ffff:a.b.c.d) and NAT64 (64:ff9b::a.b.c.d) carry an IPv4 address.
  if (zeros(0, 5) && groups[5] === 0xff_ff) return publicV4(embedded);
  if (first === 0x00_64 && groups[1] === 0xff_9b && zeros(2, 6))
    return publicV4(embedded);
  if ((first & 0xfe_00) === 0xfc_00) return false;
  if ((first & 0xff_c0) === 0xfe_80) return false;
  if ((first & 0xff_00) === 0xff_00) return false;
  if (first === 0x20_01 && groups[1] === 0x0d_b8) return false;
  if (first === 0x01_00 && zeros(1, 4)) return false;
  return true;
}

/**
 * Whether an IP address is reachable on the public internet: not loopback,
 * private, link-local (cloud metadata), carrier-grade NAT, multicast or
 * reserved. Returns `false` for anything that isn't an IP address.
 */
export function isPublicAddress(address: string): boolean {
  const ipv4 = v4(address);
  if (ipv4 !== undefined) return publicV4(ipv4);
  const ipv6 = v6(address.replaceAll(/^\[|\]$/g, ""));
  return ipv6 !== undefined && publicV6(ipv6);
}

const isAddress = (host: string): boolean =>
  v4(host) !== undefined || v6(host) !== undefined;

const LOCAL_HOST = /(^|\.)(localhost|local|internal|home\.arpa)$/;

interface DnsModule {
  readonly promises: {
    lookup(
      hostname: string,
      options: { readonly all: true; readonly verbatim: true },
    ): Promise<readonly { readonly address: string }[]>;
  };
}

/** `node:dns` without importing it, so this entry stays runtime-neutral. */
function builtinResolver(): ResolveHost | undefined {
  // SAFETY: process is optional here; every property read is guarded.
  const runtime = globalThis as {
    process?: { getBuiltinModule?: (id: string) => unknown };
  };
  const dns = runtime.process?.getBuiltinModule?.("node:dns");
  if (typeof dns !== "object" || dns === null || !("promises" in dns))
    return undefined;
  // SAFETY: node:dns has `promises.lookup` with this signature since Node 10.
  const { promises } = dns as DnsModule;
  return async (hostname) =>
    (await promises.lookup(hostname, { all: true, verbatim: true })).map(
      (entry) => entry.address,
    );
}

/**
 * The default `allowUrl`: HTTPS only, no credentials in the URL, no local
 * host names, and every address the host resolves to must be public. The
 * delivery transport calls it again for each redirect.
 *
 * DNS can change between this check and the connection. Route webhooks
 * through an egress proxy when that matters.
 */
export function publicUrl(options: PublicUrlOptions = {}): AllowUrl {
  const resolve =
    options.resolve === false
      ? undefined
      : (options.resolve ?? builtinResolver());
  if (options.resolve === undefined && !resolve) {
    throw new TypeError(
      "publicUrl() needs a resolve option on runtimes without node:dns, or resolve: false to skip the DNS check",
    );
  }
  const trusted = new Set(
    options.allowHosts?.map((host) => host.toLowerCase()),
  );
  return async (url) => {
    const host = url.hostname.toLowerCase().replaceAll(/^\[|\]$/g, "");
    if (trusted.has(host)) return true;
    if (
      url.protocol !== "https:" &&
      !(options.allowHttp && url.protocol === "http:")
    )
      return false;
    if (url.username || url.password) return false;
    if (isAddress(host)) return isPublicAddress(host);
    if (LOCAL_HOST.test(host) || !host.includes(".")) return false;
    if (!resolve) return true;
    const addresses = await resolve(host);
    return addresses.length > 0 && addresses.every(isPublicAddress);
  };
}
