import { isRecord } from "../core/guards.ts";

/** The indicator of a card (CDS Hooks 2.0). */
export type CdsIndicator = "info" | "warning" | "critical";

export interface CdsSource {
  readonly label: string;
  readonly url?: string;
  readonly icon?: string;
}

export interface CdsLink {
  readonly label: string;
  readonly url: string;
  readonly type: "absolute" | "smart";
  readonly appContext?: string;
}

export interface CdsCard {
  readonly uuid?: string;
  /** At most 140 characters. */
  readonly summary: string;
  readonly detail?: string;
  readonly indicator: CdsIndicator;
  readonly source: CdsSource;
  readonly links?: readonly CdsLink[];
}

/** What the EHR posts to a service. */
export interface CdsRequest {
  readonly hook: string;
  readonly hookInstance: string;
  readonly fhirServer?: string;
  readonly context: Readonly<Record<string, unknown>>;
  readonly prefetch?: Readonly<Record<string, unknown>>;
}

export interface CdsResponse {
  readonly cards: readonly CdsCard[];
}

/**
 * One CDS service. Versioned: a breaking change ships a new `apiVersion`.
 * `handle` gets a request whose `hook` already matches `hook`.
 */
export interface CdsService {
  readonly apiVersion: 1;
  /** The path segment, such as `medication-alerts`. */
  readonly id: string;
  /** The hook it answers, such as `order-sign`. */
  readonly hook: string;
  readonly title?: string;
  readonly description: string;
  /**
   * Prefetch templates by key, such as `"patient":
   * "Patient/{{context.patientId}}"`.
   */
  readonly prefetch?: Readonly<Record<string, string>>;
  handle(request: CdsRequest): Promise<CdsResponse>;
}

/** Checks a service's `apiVersion` before the server uses it. */
export function cdsServiceOf(service: CdsService): CdsService {
  const version: unknown = service.apiVersion;

  if (version !== 1) {
    throw new TypeError(
      `CDS service "${service.id}" targets CDS service API ${String(version)}; this better-supabase supports 1. Upgrade better-supabase or use a release of the service for API 1.`,
    );
  }

  return service;
}

/**
 * The shape of a care alert a card is made from. Structural, so no block is
 * imported.
 */
export interface CdsAlertLike {
  readonly id: string;
  readonly severity: string;
  readonly message: string;
  readonly kind?: string;
}

const SEVERITY: Readonly<Record<string, CdsIndicator>> = {
  critical: "critical",
  high: "critical",
  major: "critical",
  warning: "warning",
  moderate: "warning",
  medium: "warning",
};

/** Turns an alert into a card. Unknown severities become `info`. */
export function cdsCardOfAlert(
  alert: CdsAlertLike,
  source: CdsSource,
): CdsCard {
  return {
    uuid: alert.id,
    summary:
      alert.message.length > 140
        ? `${alert.message.slice(0, 137)}...`
        : alert.message,
    ...(alert.message.length > 140 ? { detail: alert.message } : {}),
    indicator: SEVERITY[alert.severity.toLowerCase()] ?? "info",
    source,
  };
}

export interface CdsHooksServerOptions {
  readonly services: readonly CdsService[];
  /**
   * Checks the request before a service runs, such as the EHR's JWT in the
   * `Authorization` header (CDS Hooks requires one for production use). Return
   * `false` to answer 401. Without it every request is accepted, so set it
   * unless the server is only reachable from the EHR's network.
   */
  readonly authorize?: (request: Request) => Promise<boolean>;
  /** The path the services live under. Default `/cds-services`. */
  readonly basePath?: string;
}

function json(status: number, body: unknown): Response {
  return Response.json(body, { status });
}

function requestOf(body: unknown, hook: string): CdsRequest | undefined {
  if (
    !isRecord(body) ||
    body["hook"] !== hook ||
    typeof body["hookInstance"] !== "string" ||
    !isRecord(body["context"])
  ) {
    return undefined;
  }

  return {
    hook,
    hookInstance: body["hookInstance"],
    ...(typeof body["fhirServer"] === "string"
      ? { fhirServer: body["fhirServer"] }
      : {}),
    context: body["context"],
    ...(isRecord(body["prefetch"]) ? { prefetch: body["prefetch"] } : {}),
  };
}

/**
 * A Fetch handler for the CDS Hooks 2.0 service API: `GET <base>` lists the
 * services (discovery) and `POST <base>/<id>` runs one. Mount it in any route
 * that gives you a `Request`. A service that throws answers 500 with no detail,
 * and a request with another hook or a malformed body answers 400.
 */
export function createCdsHooksServer(
  options: CdsHooksServerOptions,
): (request: Request) => Promise<Response> {
  const services = new Map(
    options.services.map((service) => [service.id, cdsServiceOf(service)]),
  );

  const base = (options.basePath ?? "/cds-services").replace(/\/+$/, "");

  return async (request) => {
    if (
      options.authorize !== undefined &&
      !(await options.authorize(request))
    ) {
      return json(401, { error: "unauthorized" });
    }

    const path = new URL(request.url).pathname.replace(/\/+$/, "");

    if (path === base && request.method === "GET") {
      return json(200, {
        services: [...services.values()].map((service) => ({
          hook: service.hook,
          id: service.id,
          description: service.description,
          ...(service.title === undefined ? {} : { title: service.title }),
          ...(service.prefetch === undefined
            ? {}
            : { prefetch: service.prefetch }),
        })),
      });
    }

    const service = path.startsWith(`${base}/`)
      ? services.get(path.slice(base.length + 1))
      : undefined;

    if (service === undefined) {
      return json(404, { error: "not_found" });
    }

    if (request.method !== "POST") {
      return json(405, { error: "method_not_allowed" });
    }

    const payload = requestOf(
      await request.json().catch(() => undefined),
      service.hook,
    );

    if (payload === undefined) {
      return json(400, { error: "invalid_request" });
    }

    try {
      return json(200, await service.handle(payload));
    } catch {
      return json(500, { error: "service_failed" });
    }
  };
}
