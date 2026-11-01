import type { AsyncResult } from "../../core/result.ts";
import type {
  PublishedAdvisory,
  PublishedAdvisorySummary,
  PublishedStatement,
  PublishedVulnerability,
  VexStatus,
} from "./types.ts";

import { cvssSeverity } from "./cvss.ts";

/** The publisher a CSAF document and `provider-metadata.json` name. */
export interface CsafPublisher {
  /** `vendor` for a software vendor. */
  readonly category?:
    | "coordinator"
    | "discoverer"
    | "other"
    | "translator"
    | "user"
    | "vendor";
  readonly name: string;
  /** The publisher's URL, such as `https://example.com`. */
  readonly namespace: string;
  readonly contactDetails?: string;
}

export interface RenderCsafOptions {
  readonly publisher: CsafPublisher;
  /** The document's language. Default: `en`. */
  readonly lang?: string;
  /** The URL of this document, for its `self` reference. */
  readonly url?: string;
  /** Names the product in the tree above its name, default the publisher. */
  readonly vendor?: string;
}

/** The CSAF version the block writes. */
export const CSAF_VERSION = "2.0";

const CVE = /^CVE-\d{4}-\d{4,}$/u;

const NONE = "No remediation is available yet.";

/** The part of a product tree a statement points at. */
interface Tree {
  readonly productId: string;
  readonly versionIds: ReadonlyMap<string, string>;
}

type Json = Readonly<Record<string, unknown>>;

function treeOf(advisory: PublishedAdvisory): Tree {
  const versionIds = new Map<string, string>();
  let index = 1;

  for (const version of advisory.product.versions) {
    index += 1;
    versionIds.set(version, `CSAFPID-${String(index).padStart(4, "0")}`);
  }

  return { productId: "CSAFPID-0001", versionIds };
}

/** The product ids a statement covers: its version, or every one. */
function idsOf(tree: Tree, statement: PublishedStatement): readonly string[] {
  if (statement.version !== undefined) {
    const id = tree.versionIds.get(statement.version);

    return id === undefined ? [] : [id];
  }

  return tree.versionIds.size === 0
    ? [tree.productId]
    : [...tree.versionIds.values()];
}

function productTree(
  advisory: PublishedAdvisory,
  vendor: string,
  tree: Tree,
): Json {
  const versions = [...tree.versionIds.entries()].map(([version, id]) => ({
    category: "product_version",
    name: version,
    product: { name: `${advisory.product.name} ${version}`, product_id: id },
  }));

  return {
    branches: [
      {
        category: "vendor",
        name: vendor,
        branches: [
          {
            category: "product_name",
            name: advisory.product.name,
            ...(versions.length === 0
              ? {
                  product: {
                    name: advisory.product.name,
                    product_id: tree.productId,
                  },
                }
              : { branches: versions }),
          },
        ],
      },
    ],
  };
}

/** Groups the product ids of the statements `pick` keeps by `key`. */
function grouped(
  tree: Tree,
  statements: readonly PublishedStatement[],
  pick: (statement: PublishedStatement) => string | undefined,
): [string, string[]][] {
  const groups = new Map<string, Set<string>>();

  for (const statement of statements) {
    const key = pick(statement);

    if (key === undefined) {
      continue;
    }

    const ids = groups.get(key) ?? new Set<string>();

    for (const id of idsOf(tree, statement)) {
      ids.add(id);
    }

    groups.set(key, ids);
  }

  return [...groups.entries()].map(([key, ids]) => [key, [...ids]]);
}

function vulnerabilityOf(
  vulnerability: PublishedVulnerability,
  tree: Tree,
): Json {
  const all =
    tree.versionIds.size === 0
      ? [tree.productId]
      : [...tree.versionIds.values()];

  const cve = [vulnerability.vulnId, ...vulnerability.aliases].find((id) =>
    CVE.test(id),
  );

  const statuses = new Map<VexStatus, Set<string>>();
  const covered = new Set<string>();

  for (const statement of vulnerability.statements) {
    const ids = statuses.get(statement.status) ?? new Set<string>();

    for (const id of idsOf(tree, statement)) {
      ids.add(id);
      covered.add(id);
    }

    statuses.set(statement.status, ids);
  }

  // A version without a statement is still being looked at.
  const open = all.filter((id) => !covered.has(id));

  if (open.length > 0) {
    const ids = statuses.get("under_investigation") ?? new Set<string>();

    for (const id of open) {
      ids.add(id);
    }

    statuses.set("under_investigation", ids);
  }

  const status = (key: VexStatus): string[] | undefined => {
    const ids = statuses.get(key);

    return ids === undefined ? undefined : [...ids];
  };

  const notes = [
    ...(vulnerability.summary === undefined
      ? []
      : [{ category: "summary", text: vulnerability.summary }]),
    ...(vulnerability.details === undefined
      ? []
      : [{ category: "description", text: vulnerability.details }]),
    ...(vulnerability.kevAddedOn === undefined
      ? []
      : [
          {
            category: "other",
            title: "Known exploited",
            text: `The CISA Known Exploited Vulnerabilities catalog has listed this vulnerability since ${vulnerability.kevAddedOn}.`,
          },
        ]),
  ];

  const affected = status("affected");
  const fixed = status("fixed");
  const notAffected = status("not_affected");
  const investigating = status("under_investigation");

  const flags = grouped(tree, vulnerability.statements, (statement) =>
    statement.status === "not_affected" ? statement.justification : undefined,
  ).map(([label, ids]) => ({ label, product_ids: ids }));

  const threats = grouped(tree, vulnerability.statements, (statement) =>
    statement.status === "not_affected" ? statement.impactStatement : undefined,
  ).map(([details, ids]) => ({
    category: "impact",
    details,
    product_ids: ids,
  }));

  const remediations = [
    ...grouped(tree, vulnerability.statements, (statement) =>
      statement.status === "affected"
        ? (statement.actionStatement ?? "")
        : undefined,
    ).map(([details, ids]) =>
      details === ""
        ? { category: "none_available", details: NONE, product_ids: ids }
        : { category: "mitigation", details, product_ids: ids },
    ),
    ...grouped(tree, vulnerability.statements, (statement) =>
      statement.status === "fixed"
        ? (statement.actionStatement ?? "Update to this version.")
        : undefined,
    ).map(([details, ids]) => ({
      category: "vendor_fix",
      details,
      product_ids: ids,
    })),
  ];

  const scored =
    vulnerability.cvssVector !== undefined &&
    vulnerability.cvssScore !== undefined &&
    (vulnerability.cvssVersion === "3.0" ||
      vulnerability.cvssVersion === "3.1");

  return {
    ...(cve === undefined ? {} : { cve }),
    ...(cve === vulnerability.vulnId
      ? {}
      : { ids: [{ system_name: "OSV", text: vulnerability.vulnId }] }),
    title: vulnerability.summary ?? vulnerability.vulnId,
    ...(notes.length === 0 ? {} : { notes }),
    product_status: {
      ...(affected === undefined ? {} : { known_affected: affected }),
      ...(fixed === undefined ? {} : { fixed }),
      ...(notAffected === undefined ? {} : { known_not_affected: notAffected }),
      ...(investigating === undefined
        ? {}
        : { under_investigation: investigating }),
    },
    ...(flags.length === 0 ? {} : { flags }),
    ...(threats.length === 0 ? {} : { threats }),
    ...(remediations.length === 0 ? {} : { remediations }),
    ...(scored
      ? {
          scores: [
            {
              products: all,
              cvss_v3: {
                version: vulnerability.cvssVersion,
                vectorString: vulnerability.cvssVector,
                baseScore: vulnerability.cvssScore,
                baseSeverity: cvssSeverity(
                  vulnerability.cvssScore,
                ).toUpperCase(),
              },
            },
          ],
        }
      : {}),
  };
}

/**
 * Renders a published advisory as a CSAF 2.0 `csaf_security_advisory` document:
 * the document block with its tracking and revision history, a product tree of
 * the product's versions, and one vulnerability per entry with the product
 * status, flags, threats and remediations that the VEX statements give. A
 * version without a statement is `under_investigation`. CVSS 3.x scores are
 * included; 4.0 scores have no place in CSAF 2.0.
 */
export function renderCsaf(
  advisory: PublishedAdvisory,
  options: RenderCsafOptions,
): Readonly<Record<string, unknown>> {
  const tree = treeOf(advisory);
  const { publisher } = options;

  return {
    document: {
      category: "csaf_security_advisory",
      csaf_version: CSAF_VERSION,
      distribution: { tlp: { label: "WHITE" } },
      lang: options.lang ?? "en",
      notes: [{ category: "summary", text: advisory.summary }],
      publisher: {
        category: publisher.category ?? "vendor",
        name: publisher.name,
        namespace: publisher.namespace,
        ...(publisher.contactDetails === undefined
          ? {}
          : { contact_details: publisher.contactDetails }),
      },
      ...(options.url === undefined
        ? {}
        : {
            references: [
              { category: "self", summary: "Canonical URL", url: options.url },
            ],
          }),
      title: advisory.title,
      tracking: {
        current_release_date: advisory.currentReleaseAt.toString(),
        id: advisory.trackingId,
        initial_release_date: advisory.initialReleaseAt.toString(),
        revision_history: advisory.revisionHistory.map((revision) => ({
          date: revision.date.toString(),
          number: revision.number,
          summary: revision.summary,
        })),
        status: advisory.status,
        version: String(advisory.version),
      },
    },
    product_tree: productTree(advisory, options.vendor ?? publisher.name, tree),
    vulnerabilities: advisory.vulnerabilities.map((vulnerability) =>
      vulnerabilityOf(vulnerability, tree),
    ),
  };
}

/** Where `createCsafHandler` reads the published advisories from. */
export interface CsafSource {
  listPublished(): AsyncResult<PublishedAdvisorySummary[]>;
  getPublished(trackingId: string): AsyncResult<PublishedAdvisory | undefined>;
}

export interface CsafHandlerOptions {
  readonly source: CsafSource;
  readonly publisher: CsafPublisher;
  /**
   * The public origin the handler is served from, such as
   * `https://example.com`.
   */
  readonly baseUrl: string;
  /** Where the handler is mounted. Default: `/.well-known/csaf`. */
  readonly basePath?: string;
  /**
   * The role in `provider-metadata.json`. The handler does not sign documents,
   * so the default is `csaf_publisher`.
   */
  readonly role?: "csaf_provider" | "csaf_publisher" | "csaf_trusted_provider";
  readonly lang?: string;
  /** Seconds a client may cache an answer. Default: 300. */
  readonly maxAge?: number;
}

/** The file name CSAF 2.0 section 5.1 gives a tracking id: `acme-sa-2026-001`. */
export const csafFileName = (trackingId: string): string =>
  trackingId.toLowerCase().replaceAll(/[^+\-a-z0-9]/gu, "_");

const folderOf = (summary: PublishedAdvisorySummary): string =>
  `${String(new Date(summary.initialReleaseAt.toString()).getUTCFullYear())}/${csafFileName(summary.trackingId)}`;

/**
 * A `Request` handler for the CSAF distribution of one organization's published
 * advisories under `/.well-known/csaf`: `provider-metadata.json`,
 * `white/index.txt`, `white/changes.csv`, each document at
 * `white/<year>/<file>.json`, and its `.sha256` and `.sha512` hashes. It
 * answers GET and HEAD only and never writes. Mount it on a route that does not
 * need a session, with a `source` that reads as the service role.
 */
export function createCsafHandler(
  options: CsafHandlerOptions,
): (request: Request) => Promise<Response> {
  const basePath = (options.basePath ?? "/.well-known/csaf").replace(
    /\/+$/u,
    "",
  );

  const origin = options.baseUrl.replace(/\/+$/u, "");
  const maxAge = options.maxAge ?? 300;
  const directory = `${origin}${basePath}/white/`;

  const reply = (body: string, type: string, status = 200): Response =>
    new Response(body, {
      status,
      headers: {
        "content-type": type,
        "cache-control": `public, max-age=${String(maxAge)}`,
        "x-content-type-options": "nosniff",
      },
    });

  const missing = (): Response =>
    reply(JSON.stringify({ error: "not found" }), "application/json", 404);

  return async (request) => {
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response(null, {
        status: 405,
        headers: { allow: "GET, HEAD" },
      });
    }

    const { pathname } = new URL(request.url);

    if (!pathname.startsWith(`${basePath}/`)) {
      return missing();
    }

    const path = pathname.slice(basePath.length + 1);
    const listed = await options.source.listPublished();

    if (!listed.ok) {
      return reply(
        JSON.stringify({ error: "the advisories could not be read" }),
        "application/json",
        503,
      );
    }

    const published = listed.data.toSorted(
      (a, b) =>
        b.currentReleaseAt.epochMilliseconds -
        a.currentReleaseAt.epochMilliseconds,
    );

    let response: Response | undefined;

    if (path === "provider-metadata.json") {
      const updated =
        published[0]?.currentReleaseAt.toString() ?? new Date().toISOString();

      response = reply(
        JSON.stringify({
          canonical_url: `${origin}${basePath}/provider-metadata.json`,
          distribution: [{ directory_url: directory }],
          last_updated: updated,
          list_on_CSAF_aggregators: false,
          metadata_version: "2.0",
          mirror_on_CSAF_aggregators: false,
          publisher: {
            category: options.publisher.category ?? "vendor",
            name: options.publisher.name,
            namespace: options.publisher.namespace,
            ...(options.publisher.contactDetails === undefined
              ? {}
              : { contact_details: options.publisher.contactDetails }),
          },
          role: options.role ?? "csaf_publisher",
        }),
        "application/json",
      );
    } else if (path === "white/index.txt") {
      response = reply(
        published.map((entry) => `${folderOf(entry)}.json\n`).join(""),
        "text/plain; charset=utf-8",
      );
    } else if (path === "white/changes.csv") {
      response = reply(
        published
          .map(
            (entry) =>
              `"${folderOf(entry)}.json","${entry.currentReleaseAt.toString()}"\n`,
          )
          .join(""),
        "text/csv; charset=utf-8",
      );
    } else {
      const match =
        /^white\/(\d{4})\/([+\-_a-z0-9]+)\.json(\.sha256|\.sha512)?$/u.exec(
          path,
        );

      const entry =
        match === null
          ? undefined
          : published.find(
              (item) =>
                `${folderOf(item)}.json` ===
                `${match[1] ?? ""}/${match[2] ?? ""}.json`,
            );

      if (match !== null && entry !== undefined) {
        const found = await options.source.getPublished(entry.trackingId);

        if (found.ok && found.data !== undefined) {
          const body = JSON.stringify(
            renderCsaf(found.data, {
              publisher: options.publisher,
              ...(options.lang === undefined ? {} : { lang: options.lang }),
              url: `${directory}${folderOf(entry)}.json`,
            }),
          );

          const hash = match[3];

          if (hash === undefined) {
            response = reply(body, "application/json");
          } else {
            const digest = await digestHex(
              hash === ".sha256" ? "SHA-256" : "SHA-512",
              body,
            );

            response = reply(
              `${digest}  ${csafFileName(entry.trackingId)}.json\n`,
              "text/plain; charset=utf-8",
            );
          }
        }
      }
    }

    const answer = response ?? missing();

    return request.method === "HEAD"
      ? new Response(null, { status: answer.status, headers: answer.headers })
      : answer;
  };
}

async function digestHex(
  algorithm: "SHA-256" | "SHA-512",
  value: string,
): Promise<string> {
  const digest = await crypto.subtle.digest(
    algorithm,
    new TextEncoder().encode(value),
  );

  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}
