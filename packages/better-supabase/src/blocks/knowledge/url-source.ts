import type { ListPage } from "../../core/block-helpers.ts";
import type { KnowledgeExtractor } from "./extractors.ts";
import type {
  Knowledge,
  KnowledgeDocument,
  NewKnowledgeDocument,
} from "./knowledge.ts";

import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { errorText } from "../shared.ts";
import { chunk, textExtract } from "./knowledge.ts";

const DEFAULT_MAX_BYTES = 5 * 1024 * 1024;
const DEFAULT_TIMEOUT_MS = 15_000;
const MAX_REDIRECTS = 5;
const HTML_TYPE = /^(text\/html|application\/xhtml\+xml)$/;

export interface UrlSourceOptions {
  readonly knowledge: Knowledge;
  /** Defaults to the global `fetch`. */
  readonly fetch?: typeof fetch;
  /**
   * Hosts the source may fetch, such as `docs.example.com`. A host matches
   * itself and its subdomains. Without it any public host is allowed.
   */
  readonly allowedHosts?: readonly string[];
  /** Largest body to read, in bytes. Defaults to 5 MiB; a larger one fails. */
  readonly maxBytes?: number;
  /** Time for one request, redirects included. Defaults to 15 seconds. */
  readonly timeoutMs?: number;
  /**
   * Turns a non-HTML body into text, for PDF or Office pages. HTML is converted
   * to text and Markdown headings by the source itself. Defaults to decoding
   * text, JSON, XML and YAML.
   */
  readonly extract?: KnowledgeExtractor;
  /** Sent with each request, such as a `User-Agent`. */
  readonly headers?: Readonly<Record<string, string>>;
}

export interface UrlIngestInput {
  readonly organizationId: string | null;
  readonly url: string;
  /** The title defaults to the page's `<title>` or the URL. */
  readonly document?: Partial<Omit<NewKnowledgeDocument, "source">>;
  readonly signal?: AbortSignal;
}

export interface UrlResyncResult {
  readonly document: KnowledgeDocument;
  /**
   * The document's chunks differ from before; unchanged ones keep their
   * embedding.
   */
  readonly changed: boolean;
}

export interface UrlSource {
  /**
   * Fetches a page and stores it as a knowledge document whose `source` is the
   * URL.
   */
  ingest(input: UrlIngestInput): AsyncResult<KnowledgeDocument>;
  /**
   * Fetches the document's URL again and replaces its chunks. Chunks that did
   * not change keep their embedding, so an unchanged page costs no embedding
   * calls.
   */
  resync(input: {
    readonly documentId: string;
    readonly signal?: AbortSignal;
  }): AsyncResult<UrlResyncResult>;
  /**
   * Resyncs the URL documents of a tenant, at most `limit` (default 50). One
   * failing page does not stop the others; its error is returned with its id.
   */
  resyncAll(input: {
    readonly organizationId: string;
    readonly limit?: number;
    readonly signal?: AbortSignal;
  }): AsyncResult<{
    readonly resynced: number;
    readonly changed: number;
    readonly failed: readonly {
      readonly documentId: string;
      readonly message: string;
    }[];
  }>;
}

const refuse = (message: string) =>
  dbError("invalid_request", message, { hint: "KNOWLEDGE_URL_REFUSED" });

const IPV4 = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/;

function privateIpv4(host: string): boolean | undefined {
  const match = IPV4.exec(host);

  if (!match) {
    return undefined;
  }

  const [a = 0, b = 0] = match.slice(1).map(Number);

  return (
    a === 0 ||
    a === 10 ||
    a === 127 ||
    (a === 100 && b >= 64 && b <= 127) ||
    (a === 169 && b === 254) ||
    (a === 172 && b >= 16 && b <= 31) ||
    (a === 192 && b === 168) ||
    (a === 192 && b === 0) ||
    (a === 198 && (b === 18 || b === 19)) ||
    a >= 224
  );
}

function privateIpv6(host: string): boolean {
  const bare = host.slice(1, -1).toLowerCase();

  if (bare === "::" || bare === "::1") {
    return true;
  }

  const mapped =
    /^::ffff:(?:(\d+\.\d+\.\d+\.\d+)|([0-9a-f]{1,4}):([0-9a-f]{1,4}))$/.exec(
      bare,
    );

  if (mapped) {
    if (mapped[1] !== undefined) {
      return privateIpv4(mapped[1]) ?? true;
    }

    const high = Number.parseInt(mapped[2] ?? "0", 16);
    const low = Number.parseInt(mapped[3] ?? "0", 16);

    return (
      privateIpv4(
        `${Math.floor(high / 256)}.${high % 256}.${Math.floor(low / 256)}.${low % 256}`,
      ) ?? true
    );
  }

  // fc00::/7 unique local, fe80::/10 link local, ff00::/8 multicast.
  return /^(f[cd]|fe[89ab]|ff)/.test(bare);
}

/** The reason a URL may not be fetched, or undefined. */
export function refusedUrl(
  value: URL,
  allowedHosts: readonly string[] | undefined,
): string | undefined {
  if (value.protocol !== "https:" && value.protocol !== "http:") {
    return `${value.protocol} URLs are not fetched`;
  }

  if (value.username !== "" || value.password !== "") {
    return "URLs with credentials are not fetched";
  }

  const host = value.hostname.toLowerCase().replace(/\.$/, "");

  if (allowedHosts !== undefined) {
    const allowed = allowedHosts.some((entry) => {
      const name = entry.toLowerCase();

      return host === name || host.endsWith(`.${name}`);
    });

    return allowed ? undefined : `${host} is not an allowed host`;
  }

  const literal = host.startsWith("[");

  const internal =
    host === "localhost" ||
    host.endsWith(".localhost") ||
    host.endsWith(".local") ||
    host.endsWith(".internal") ||
    (!literal && !host.includes("."));

  if (internal || (literal ? privateIpv6(host) : privateIpv4(host) === true)) {
    return `${host} is not a public host`;
  }

  return undefined;
}

const ENTITIES: Readonly<Record<string, string>> = {
  amp: "&",
  lt: "<",
  gt: ">",
  quot: '"',
  apos: "'",
  nbsp: " ",
};

function decodeEntities(text: string): string {
  return text.replaceAll(
    /&(#x[0-9a-f]+|#\d+|[a-z]+);/gi,
    (whole, name: string) => {
      if (name.startsWith("#")) {
        const code =
          name[1] === "x" || name[1] === "X"
            ? Number.parseInt(name.slice(2), 16)
            : Math.trunc(Number(name.slice(1)));

        return Number.isInteger(code) && code > 0 && code <= 0x10_ff_ff
          ? String.fromCodePoint(code)
          : whole;
      }

      return ENTITIES[name.toLowerCase()] ?? whole;
    },
  );
}

/** The readable text of an HTML page, with `#` headings, and its title. */
export function htmlToText(html: string): {
  readonly title: string | undefined;
  readonly text: string;
} {
  const title = /<title[^>]*>([\s\S]*?)<\/title>/i.exec(html)?.[1];

  const text = html
    .replaceAll(/<!--[\s\S]*?-->/g, "")
    .replaceAll(
      /<(script|style|noscript|template|svg|head|title)\b[\s\S]*?<\/\1\s*>/gi,
      "",
    )
    .replaceAll(
      /<h([1-6])\b[^>]*>([\s\S]*?)<\/h\1\s*>/gi,
      (_whole, level: string, inner: string) =>
        `\n\n${"#".repeat(Number(level))} ${inner.replaceAll(/<[^>]+>/g, "")}\n\n`,
    )
    .replaceAll(
      /<\/(p|div|section|article|li|tr|ul|ol|table|pre)\s*>/gi,
      "\n\n",
    )
    .replaceAll(/<(br|hr)\b[^>]*>/gi, "\n")
    .replaceAll(/<[^>]+>/g, "");

  return {
    title:
      title === undefined
        ? undefined
        : decodeEntities(title).replaceAll(/\s+/g, " ").trim(),
    text: decodeEntities(text)
      .replaceAll(/[ \t]+/g, " ")
      .replaceAll(/ ?\n ?/g, "\n")
      .replaceAll(/\n{3,}/g, "\n\n")
      .trim(),
  };
}

async function readCapped(
  response: Response,
  maxBytes: number,
): Promise<Uint8Array> {
  const declared = Number(response.headers.get("content-length"));

  if (Number.isFinite(declared) && declared > maxBytes) {
    throw new RangeError(`The page is larger than ${maxBytes} bytes`);
  }

  if (!response.body) {
    return new Uint8Array();
  }

  const reader = response.body.getReader();
  const parts: Uint8Array[] = [];
  let size = 0;

  for (;;) {
    const { done, value } = await reader.read();

    if (done) {
      break;
    }

    size += value.byteLength;

    if (size > maxBytes) {
      await reader.cancel();
      throw new RangeError(`The page is larger than ${maxBytes} bytes`);
    }

    parts.push(value);
  }

  const data = new Uint8Array(size);
  let at = 0;

  for (const part of parts) {
    data.set(part, at);
    at += part.byteLength;
  }

  return data;
}

/**
 * Ingests web pages as knowledge documents and keeps them current. The source
 * checks every URL, redirect hops included, against the allowed hosts or
 * against private, loopback and link-local addresses, and limits time, size and
 * redirects. It cannot see what a name resolves to, so pass `allowedHosts` when
 * the URL comes from a user.
 */
export function createUrlSource(options: UrlSourceOptions): UrlSource {
  const doFetch = options.fetch ?? fetch;
  const maxBytes = options.maxBytes ?? DEFAULT_MAX_BYTES;
  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const extract = options.extract ?? textExtract;
  const { knowledge } = options;

  const load = (
    address: string,
    signal: AbortSignal | undefined,
  ): AsyncResult<{
    readonly title: string | undefined;
    readonly text: string;
    readonly url: string;
  }> =>
    AsyncResult.from(async () => {
      const timeout = AbortSignal.timeout(timeoutMs);
      const both = signal ? AbortSignal.any([signal, timeout]) : timeout;
      let current: URL;

      try {
        current = new URL(address);
      } catch {
        return err(refuse("The URL is not valid"));
      }

      for (let hop = 0; hop <= MAX_REDIRECTS; hop += 1) {
        const reason = refusedUrl(current, options.allowedHosts);

        if (reason !== undefined) {
          return err(refuse(reason));
        }

        let response: Response;

        try {
          response = await doFetch(current, {
            redirect: "manual",
            signal: both,
            headers: {
              accept:
                "text/html, text/plain, application/json;q=0.9, */*;q=0.1",
              ...options.headers,
            },
          });
        } catch (cause) {
          return err(
            dbError(
              "network",
              `Could not fetch ${current.href}: ${errorText(cause)}`,
            ),
          );
        }

        if (response.status >= 300 && response.status < 400) {
          const location = response.headers.get("location");
          await response.body?.cancel();

          if (location === null) {
            return err(refuse("A redirect had no location"));
          }

          current = new URL(location, current);
          continue;
        }

        if (!response.ok) {
          await response.body?.cancel();

          return err(
            dbError("network", `${current.href} answered ${response.status}`, {
              hint: "KNOWLEDGE_URL_STATUS",
            }),
          );
        }

        const mediaType =
          (response.headers.get("content-type") ?? "text/plain")
            .split(";")[0]
            ?.trim()
            .toLowerCase() ?? "text/plain";

        try {
          const data = await readCapped(response, maxBytes);

          if (HTML_TYPE.test(mediaType)) {
            const { title, text } = htmlToText(new TextDecoder().decode(data));

            return ok({ title, text, url: current.href });
          }

          return ok({
            title: undefined,
            text: await extract({ mediaType }, data),
            url: current.href,
          });
        } catch (cause) {
          return err(
            dbError("invalid_request", errorText(cause), {
              hint: "KNOWLEDGE_URL_UNSUPPORTED",
            }),
          );
        }
      }

      return err(refuse(`More than ${MAX_REDIRECTS} redirects`));
    });

  const ingest = (input: UrlIngestInput): AsyncResult<KnowledgeDocument> =>
    load(input.url, input.signal).andThen((page) =>
      knowledge.ingest.text({
        organizationId: input.organizationId,
        document: {
          ...input.document,
          title: input.document?.title ?? page.title ?? page.url,
          source: input.url,
          metadata: {
            ...input.document?.metadata,
            kind: "url",
            url: input.url,
            fetchedAt: new Date().toISOString(),
          },
          text: page.text,
        },
      }),
    );

  const resync = ({
    documentId,
    signal,
  }: {
    documentId: string;
    signal?: AbortSignal;
  }): AsyncResult<UrlResyncResult> =>
    knowledge.documents.get(documentId).andThen((document) => {
      if (
        document.metadata["kind"] !== "url" ||
        document.source === undefined
      ) {
        return AsyncResult.err<UrlResyncResult>(
          dbError(
            "invalid_request",
            "The document was not ingested from a URL",
            { hint: "KNOWLEDGE_NOT_URL" },
          ),
        );
      }

      return load(document.source, signal).andThen((page) => {
        const chunks = chunk(page.text);

        return knowledge.documents
          .write({ documentId, chunks })
          .map((written) => ({
            document: written,
            changed:
              written.status !== "ready" ||
              written.chunkCount !== document.chunkCount ||
              written.embeddingModel !== document.embeddingModel,
          }));
      });
    });

  const resyncAll: UrlSource["resyncAll"] = ({
    organizationId,
    limit = 50,
    signal,
  }) =>
    AsyncResult.from(async () => {
      const found: KnowledgeDocument[] = [];
      let after: readonly string[] | undefined;

      while (found.length < limit) {
        const page: Awaited<ReturnType<Knowledge["documents"]["page"]>> =
          await knowledge.documents.page({
            organizationId,
            limit: 100,
            ...(after === undefined ? {} : { after }),
          });

        if (!page.ok) {
          return page;
        }

        const { items, nextCursor }: ListPage<KnowledgeDocument> = page.data;

        found.push(...items.filter((item) => item.metadata["kind"] === "url"));

        if (nextCursor === null) {
          break;
        }

        after = nextCursor;
      }

      let resynced = 0;
      let changed = 0;
      const failed: { documentId: string; message: string }[] = [];

      for (const document of found.slice(0, limit)) {
        const result = await resync({
          documentId: document.id,
          ...(signal === undefined ? {} : { signal }),
        });

        if (result.ok) {
          resynced += 1;
          changed += result.data.changed ? 1 : 0;
        } else {
          failed.push({
            documentId: document.id,
            message: result.error.message,
          });
        }
      }

      return ok({ resynced, changed, failed });
    });

  return { ingest, resync, resyncAll };
}
