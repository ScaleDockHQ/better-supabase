import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { DbError, ErrorMapper } from "../../core/errors.ts";
import type { Jwks } from "../../core/jws.ts";
import type { Logger } from "../../core/logger.ts";
import type { ProblemFormat } from "../../core/problem.ts";
import type { Result } from "../../core/result.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { cronRoute } from "../../core/cron-route.ts";
import { dbError } from "../../core/errors.ts";
import { timingSafeEqual } from "../../core/hmac.ts";
import { jwksSource } from "../../core/jwks-cache.ts";
import { JwsError, verifyCompact } from "../../core/jws.ts";
import { problemResponse } from "../../core/problem.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  type BlockTemporalOptions,
  errorText,
  isRecord,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
} from "../shared.ts";
import { createPartnerApi, type PartnerApiOptions } from "./partner-api.ts";

const API = "https://api.vercel.com";
const JWKS = "https://marketplace.vercel.com/.well-known/jwks";
const ISSUER = "https://marketplace.vercel.com";
const SIGNATURE_HEADER = "x-vercel-signature";

const encoder = new TextEncoder();

/** An installation of the integration by a Vercel team. */
export interface MarketplaceInstallation {
  readonly id: string;
  readonly configurationId: string;
  readonly teamId: string | undefined;
  readonly userId: string | undefined;
  /** The app's own tenant for this installation, once the app linked one. */
  readonly tenant: string | undefined;
  /**
   * Whether the installation created its tenant, so removing it may delete the
   * tenant.
   */
  readonly tenantCreated: boolean;
  readonly status: "active" | "suspended" | "removed";
  readonly metadata: Readonly<Record<string, unknown>>;
}

export interface MarketplaceResource {
  readonly id: string;
  readonly installationId: string;
  /** The resource id Vercel uses. */
  readonly externalId: string;
  readonly name: string;
  readonly planId: string | undefined;
  readonly status: "pending" | "ready" | "suspended" | "deleted";
  readonly metadata: Readonly<Record<string, unknown>>;
  /** The app's tenant the provision hook created or chose. */
  readonly tenant: string | undefined;
  readonly tenantCreated: boolean;
  /**
   * The app's handles for the secrets handed out, for the next rotation's
   * revoke.
   */
  readonly secretRefs: readonly string[];
}

export interface MarketplaceInvoice {
  readonly id: string;
  readonly installationId: string;
  readonly externalId: string;
  readonly state: string;
  readonly total: number;
  readonly currency: string;
}

export interface MeterReport {
  readonly id: string;
  readonly installationId: string;
  readonly resourceExternalId: string;
  readonly meterId: string;
  readonly periodStart: string;
  readonly periodEnd: string;
  /** The period's total so far. */
  readonly quantity: number;
  /** The total Vercel accepted; the next report sends the rest as `dayValue`. */
  readonly reportedQuantity: number;
  readonly reported: boolean;
}

/** What a verified Vercel webhook did. */
export interface MarketplaceWebhookResult {
  readonly type: string;
  /** `false` for an event type the block ignores. */
  readonly handled: boolean;
}

/** The claims of the `id_token` Vercel returns from the SSO exchange. */
export interface MarketplaceSsoClaims {
  readonly configurationId: string;
  readonly teamId: string | undefined;
  readonly userId: string | undefined;
  readonly userEmail: string | undefined;
  readonly resourceId: string | undefined;
  readonly path: string | undefined;
  readonly claims: Readonly<Record<string, unknown>>;
}

export interface VercelMarketplaceOptions extends BlockTemporalOptions {
  /** A service-role transport: every function is granted to `service_role` only. */
  readonly transport: BlockTransport;
  /**
   * The integration's client secret: signs webhooks and authenticates the SSO
   * exchange.
   */
  readonly clientSecret: string;
  /** The integration's client id, for the SSO exchange and the `aud` claim. */
  readonly clientId: string;
  /**
   * A bearer token for the Marketplace API on behalf of an installation, for
   * invoices and usage. Default: the token Vercel handed out at installation,
   * which the Partner API seals in Vault.
   */
  readonly accessToken?: (configurationId: string) => Promise<string>;
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /**
   * `withBlockHooks` hooks around the client's methods, such as a check before
   * a resource is provisioned.
   */
  readonly hooks?: BlockHooks<VercelMarketplace>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  readonly fetch?: typeof fetch;
  /** Default `https://api.vercel.com`. */
  readonly apiUrl?: string;
  /** Keys for the SSO `id_token`. Default: Vercel's published JWKS. */
  readonly jwks?: Jwks | URL | (() => Promise<Jwks>);
}

export interface InvoiceItem {
  readonly billingPlanId: string;
  readonly resourceId?: string;
  readonly name: string;
  readonly details?: string;
  /** Minor-unit-free decimal, as Vercel takes it: a string such as `"0.50"`. */
  readonly price: string;
  readonly quantity: number;
  readonly units: string;
  readonly total: string;
}

export interface SubmitInvoiceInput {
  readonly configurationId: string;
  readonly invoiceDate: Temporal.Instant;
  readonly periodStart: Temporal.Instant;
  readonly periodEnd: Temporal.Instant;
  readonly items: readonly InvoiceItem[];
  /** Marks the invoice as a test for Vercel's review. */
  readonly test?: boolean;
}

export interface ReportUsageInput {
  readonly configurationId: string;
  readonly periodStart: Temporal.Instant;
  readonly periodEnd: Temporal.Instant;
  readonly meters: readonly {
    readonly meterId: string;
    readonly quantity: number;
    /** The Vercel resource the quantity belongs to; omit for the installation. */
    readonly resourceId?: string;
  }[];
}

export interface UsageRouteOptions {
  /** The bearer token the cron caller sends, such as `process.env.CRON_SECRET`. */
  readonly secret: string | undefined;
  /** The period totals to report, one entry per installation. */
  readonly usage: () => Promise<readonly ReportUsageInput[]>;
  readonly onError?: (error: DbError, configurationId: string) => void;
  readonly problem?: ProblemFormat;
}

export interface VercelMarketplace {
  /**
   * Whether `signature` is the HMAC-SHA1 of the raw body under the client
   * secret.
   */
  verifyWebhook(body: string, signature: string | null): Promise<boolean>;
  /** Verifies a webhook request and applies it: removals and invoice states. */
  handleWebhook(request: Request): AsyncResult<MarketplaceWebhookResult>;
  /**
   * Exchanges the SSO `code`, verifies the `id_token` and keeps the
   * installation current.
   */
  exchangeSso(input: {
    readonly code: string;
    readonly state?: string;
  }): AsyncResult<MarketplaceSsoClaims>;
  installation(
    configurationId: string,
  ): AsyncResult<MarketplaceInstallation | undefined>;
  /** Records an installation, for the provider's install callback. */
  upsertInstallation(input: {
    readonly configurationId: string;
    readonly teamId?: string;
    readonly userId?: string;
    readonly tenant?: string;
    readonly metadata?: Readonly<Record<string, unknown>>;
  }): AsyncResult<MarketplaceInstallation>;
  upsertPlan(input: {
    readonly id: string;
    readonly name: string;
    readonly kind?: "subscription" | "prepayment";
    readonly details?: Readonly<Record<string, unknown>>;
  }): AsyncResult<void>;
  /** Provisions or updates a resource, for the provider's resource endpoints. */
  upsertResource(input: {
    readonly configurationId: string;
    readonly externalId: string;
    readonly name: string;
    readonly planId?: string;
    readonly status?: MarketplaceResource["status"];
    readonly metadata?: Readonly<Record<string, unknown>>;
  }): AsyncResult<MarketplaceResource>;
  /** Sends an invoice to Vercel for the period. */
  submitInvoice(
    input: SubmitInvoiceInput,
  ): AsyncResult<{ readonly id: string }>;
  /**
   * Stores the period totals, then sends what Vercel has not accepted yet, one
   * request per billing period: `periodValue` is the total and `dayValue` the
   * part not reported before. A failed send leaves the rest stored, so the next
   * call resends it.
   */
  reportUsage(input: ReportUsageInput): AsyncResult<readonly MeterReport[]>;
  /**
   * Marks the installation removed and its resources deleted, and drops its
   * sealed token.
   */
  removeInstallation(
    configurationId: string,
  ): AsyncResult<MarketplaceInstallation | undefined>;
  /** Seals the installation's access token in Vault. */
  sealAccessToken(configurationId: string, token: string): AsyncResult<void>;
  /**
   * Links the app's tenant to an installation; `created` lets removal delete
   * it.
   */
  linkTenant(input: {
    readonly configurationId: string;
    readonly tenant: string;
    readonly created?: boolean;
  }): AsyncResult<MarketplaceInstallation>;
  resource(
    configurationId: string,
    externalId: string,
  ): AsyncResult<MarketplaceResource | undefined>;
  /** The installation's resources that are not deleted. */
  resources(
    configurationId: string,
  ): AsyncResult<readonly MarketplaceResource[]>;
  /** Marks a resource deleted; the row stays for invoices and audit. */
  deleteResource(
    configurationId: string,
    externalId: string,
  ): AsyncResult<MarketplaceResource | undefined>;
  /**
   * The Partner API Vercel calls (installations, resources, secret rotation and
   * plans) as one `Request` to `Response` handler, every request checked
   * against Vercel's OIDC token.
   */
  partnerApi(
    options: PartnerApiOptions,
  ): (request: Request) => Promise<Response>;
  /**
   * A cron route that reports the totals `usage` returns. It answers 200 with
   * the configuration ids it reported, or 502 when one failed; the failed ones
   * are sent again on the next run.
   */
  usageRoute(
    options: UsageRouteOptions,
  ): (request: Request) => Promise<Response>;
}

function installationOf(value: unknown): MarketplaceInstallation {
  const row = recordOf(value, "marketplace_installations");
  const status = row["status"];

  return {
    id: textOf(row["id"]),
    configurationId: textOf(row["configuration_id"]),
    teamId: optionalText(row["team_id"]),
    userId: optionalText(row["user_id"]),
    tenant: optionalText(row["tenant"]),
    tenantCreated: row["tenant_created"] === true,
    status: status === "suspended" || status === "removed" ? status : "active",
    metadata: isRecord(row["metadata"]) ? row["metadata"] : {},
  };
}

function resourceOf(value: unknown): MarketplaceResource {
  const row = recordOf(value, "marketplace_resources");
  const status = row["status"];

  return {
    id: textOf(row["id"]),
    installationId: textOf(row["installation_id"]),
    externalId: textOf(row["external_id"]),
    name: textOf(row["name"]),
    planId: optionalText(row["plan_id"]),
    status:
      status === "pending" || status === "suspended" || status === "deleted"
        ? status
        : "ready",
    metadata: isRecord(row["metadata"]) ? row["metadata"] : {},
    tenant: optionalText(row["tenant"]),
    tenantCreated: row["tenant_created"] === true,
    secretRefs: Array.isArray(row["secret_refs"])
      ? row["secret_refs"].filter(
          (ref): ref is string => typeof ref === "string",
        )
      : [],
  };
}

function meterReportOf(value: unknown): MeterReport {
  const row = recordOf(value, "marketplace_meter_reports");

  return {
    id: textOf(row["id"]),
    installationId: textOf(row["installation_id"]),
    resourceExternalId: textOf(row["resource_external_id"]),
    meterId: textOf(row["meter_id"]),
    periodStart: textOf(row["period_start"]),
    periodEnd: textOf(row["period_end"]),
    quantity: Number(row["quantity"]),
    reportedQuantity: Number(row["reported_quantity"] ?? 0),
    reported: row["reported_at"] !== null && row["reported_at"] !== undefined,
  };
}

async function sha1Hex(secret: string, body: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-1" },
    false,
    ["sign"],
  );

  const signed = await crypto.subtle.sign("HMAC", key, encoder.encode(body));

  return Array.from(new Uint8Array(signed), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
}

function invalid<T = never>(message: string, hint: string): Result<T> {
  return err(dbError("invalid_request", message, { hint }));
}

/** A string field of a JSON object, or `undefined`. */
function field(value: unknown, name: string): string | undefined {
  return isRecord(value) ? optionalText(value[name]) : undefined;
}

/** The payload object of a Vercel webhook, whose fields sit under `payload`. */
function payloadOf(body: Record<string, unknown>): Record<string, unknown> {
  return isRecord(body["payload"]) ? body["payload"] : {};
}

/** Vercel Marketplace provider state, webhooks, SSO and billing. */
export function createVercelMarketplace(
  options: VercelMarketplaceOptions,
): VercelMarketplace {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const http = options.fetch ?? fetch;
  const base = options.apiUrl ?? API;
  const keys = jwksSource(options.jwks ?? new URL(JWKS), { rsa: true });

  const verifyWebhook = async (
    body: string,
    signature: string | null,
  ): Promise<boolean> =>
    signature !== null &&
    timingSafeEqual(
      await sha1Hex(options.clientSecret, body),
      signature.trim().toLowerCase(),
    );

  const send = async (
    configurationId: string,
    path: string,
    payload: unknown,
  ): Promise<Result<unknown>> => {
    let token: string;

    if (options.accessToken === undefined) {
      const sealed = await call(
        "marketplace_access_token",
        { configuration_id: configurationId },
        (value) => (typeof value === "string" ? value : undefined),
      );

      if (!sealed.ok) {
        return err(sealed.error);
      }

      if (sealed.data === undefined) {
        return invalid(
          "The installation has no sealed access token; pass accessToken or let the Partner API store it",
          "MARKETPLACE_NO_TOKEN",
        );
      }

      token = sealed.data;
    } else {
      try {
        token = await options.accessToken(configurationId);
      } catch (cause) {
        return err(dbError("network", errorText(cause)));
      }
    }

    try {
      const response = await http(
        `${base}/v1/installations/${encodeURIComponent(configurationId)}${path}`,
        {
          method: "POST",
          headers: {
            authorization: `Bearer ${token}`,
            "content-type": "application/json",
          },
          body: JSON.stringify(payload),
        },
      );

      if (!response.ok) {
        return err(
          dbError("network", `Vercel answered ${response.status} for ${path}`, {
            hint: "MARKETPLACE_API_FAILED",
          }),
        );
      }

      const text = await response.text();

      // SAFETY: JSON.parse returns unknown data that callers read through `field`.
      return ok(text === "" ? {} : (JSON.parse(text) as unknown));
    } catch (cause) {
      return err(dbError("network", errorText(cause)));
    }
  };

  const verifySignature = async (
    token: string,
  ): Promise<Result<Readonly<Record<string, unknown>>>> => {
    let verified = await keys(false);

    if (!verified.ok) {
      return err(verified.error);
    }

    try {
      return ok(
        (await verifyCompact(token, verified.data, { algorithms: ["RS256"] }))
          .payload,
      );
    } catch (cause) {
      if (!(cause instanceof JwsError) || cause.code !== "JWS_KEY") {
        return err(
          dbError(
            "unauthorized",
            `Vercel's token does not verify: ${errorText(cause)}`,
            { hint: "MARKETPLACE_TOKEN" },
          ),
        );
      }
    }

    verified = await keys(true);

    if (!verified.ok) {
      return err(verified.error);
    }

    try {
      return ok(
        (await verifyCompact(token, verified.data, { algorithms: ["RS256"] }))
          .payload,
      );
    } catch (cause) {
      return err(
        dbError(
          "unauthorized",
          `Vercel's token does not verify: ${errorText(cause)}`,
          { hint: "MARKETPLACE_TOKEN" },
        ),
      );
    }
  };

  /** Checks a token Vercel signed: signature, issuer, audience and expiry. */
  const verifyToken = async (
    token: string,
  ): Promise<Result<Readonly<Record<string, unknown>>>> => {
    const verified = await verifySignature(token);

    if (!verified.ok) {
      return verified;
    }

    const claims = verified.data;
    const audience = claims["aud"];
    const now = Math.floor(Date.now() / 1000);

    if (
      claims["iss"] !== ISSUER ||
      !(
        audience === options.clientId ||
        (Array.isArray(audience) && audience.includes(options.clientId))
      ) ||
      typeof claims["exp"] !== "number" ||
      claims["exp"] <= now
    ) {
      return err(
        dbError(
          "forbidden",
          "The token is not for this integration or has expired",
          { hint: "MARKETPLACE_TOKEN_CLAIMS" },
        ),
      );
    }

    return ok(claims);
  };

  const client: VercelMarketplace = {
    verifyWebhook,

    handleWebhook: (request) =>
      AsyncResult.from(async () => {
        const body = await request.text();

        if (
          !(await verifyWebhook(body, request.headers.get(SIGNATURE_HEADER)))
        ) {
          return err(
            dbError("invalid_request", "The webhook signature does not match", {
              hint: "MARKETPLACE_SIGNATURE",
            }),
          );
        }

        let event: unknown;

        try {
          event = JSON.parse(body);
        } catch {
          return invalid("The webhook body is not JSON", "MARKETPLACE_BODY");
        }

        if (!isRecord(event) || typeof event["type"] !== "string") {
          return invalid("The webhook has no type", "MARKETPLACE_BODY");
        }

        const type = event["type"];
        const payload = payloadOf(event);

        const configurationId =
          field(payload, "installationId") ??
          field(
            isRecord(payload["configuration"]) ? payload["configuration"] : {},
            "id",
          ) ??
          field(payload, "configurationId");

        if (configurationId === undefined) {
          return ok({ type, handled: false });
        }

        if (type === "integration-configuration.removed") {
          return call(
            "remove_marketplace_installation",
            { configuration_id: configurationId },
            () => undefined,
          ).map(() => ({ type, handled: true }));
        }

        if (type.startsWith("marketplace.invoice.")) {
          const externalId = field(payload, "invoiceId");

          if (externalId === undefined) {
            return invalid(
              "The invoice event has no invoiceId",
              "MARKETPLACE_BODY",
            );
          }

          const createdAt = event["createdAt"];

          return call(
            "record_marketplace_invoice",
            {
              configuration_id: configurationId,
              external_id: externalId,
              state: type.slice("marketplace.invoice.".length),
              event_at:
                typeof createdAt === "number"
                  ? new Date(createdAt).toISOString()
                  : new Date().toISOString(),
            },
            () => undefined,
          ).map(() => ({ type, handled: true }));
        }

        return ok({ type, handled: false });
      }),

    exchangeSso: ({ code, state }) =>
      AsyncResult.from(async () => {
        try {
          const response = await http(`${base}/v1/integrations/sso/token`, {
            method: "POST",
            headers: { "content-type": "application/x-www-form-urlencoded" },
            body: new URLSearchParams({
              code,
              client_id: options.clientId,
              client_secret: options.clientSecret,
              ...(state === undefined ? {} : { state }),
            }),
          });

          if (!response.ok) {
            return err(
              dbError(
                "network",
                `Vercel answered ${response.status} to the code`,
                { hint: "MARKETPLACE_SSO_FAILED" },
              ),
            );
          }

          const token = field(await response.json(), "id_token");

          if (token === undefined) {
            return invalid(
              "Vercel returned no id_token",
              "MARKETPLACE_SSO_FAILED",
            );
          }

          const verified = await verifyToken(token);

          if (!verified.ok) {
            return verified.error.kind === "forbidden"
              ? invalid(
                  "The id_token is not for this integration or has expired",
                  "MARKETPLACE_SSO_CLAIMS",
                )
              : err(verified.error);
          }

          const claims = verified.data;
          const configurationId = textOf(claims["installation_id"]);

          if (configurationId === "") {
            return invalid(
              "The id_token names no installation",
              "MARKETPLACE_SSO_CLAIMS",
            );
          }

          const teamId = optionalText(claims["account_id"]);
          const userId = optionalText(claims["user_id"]);

          const stored = await client.upsertInstallation({
            configurationId,
            ...(teamId === undefined ? {} : { teamId }),
            ...(userId === undefined ? {} : { userId }),
          });

          if (!stored.ok) {
            return err(stored.error);
          }

          return ok({
            configurationId,
            teamId,
            userId,
            userEmail: optionalText(claims["user_email"]),
            resourceId: optionalText(claims["resource_id"]),
            path: optionalText(claims["path"]),
            claims,
          });
        } catch (cause) {
          return err(dbError("network", errorText(cause)));
        }
      }),

    installation: (configurationId) =>
      call(
        "marketplace_installation",
        { configuration_id: configurationId },
        (value) => (isRecord(value) ? installationOf(value) : undefined),
      ),

    upsertInstallation: (input) =>
      call(
        "upsert_marketplace_installation",
        {
          configuration_id: input.configurationId,
          team_id: input.teamId ?? null,
          user_id: input.userId ?? null,
          tenant: input.tenant ?? null,
          metadata: input.metadata ?? {},
        },
        installationOf,
      ),

    upsertPlan: (input) =>
      call(
        "upsert_marketplace_plan",
        {
          id: input.id,
          name: input.name,
          kind: input.kind ?? "subscription",
          details: input.details ?? {},
        },
        () => undefined,
      ),

    upsertResource: (input) =>
      call(
        "upsert_marketplace_resource",
        {
          configuration_id: input.configurationId,
          external_id: input.externalId,
          name: input.name,
          plan_id: input.planId ?? null,
          status: input.status ?? "ready",
          metadata: input.metadata ?? {},
        },
        resourceOf,
      ),

    submitInvoice: (input) =>
      AsyncResult.from(async () => {
        const sent = await send(input.configurationId, "/billing/invoices", {
          externalId: `${input.configurationId}-${input.periodStart.toString()}`,
          invoiceDate: input.invoiceDate.toString(),
          period: {
            start: input.periodStart.toString(),
            end: input.periodEnd.toString(),
          },
          items: input.items,
          ...(input.test === undefined ? {} : { test: input.test }),
        });

        if (!sent.ok) {
          return err(sent.error);
        }

        return ok({ id: field(sent.data, "invoiceId") ?? "" });
      }),

    reportUsage: (input) =>
      AsyncResult.from(async () => {
        const stored: MeterReport[] = [];

        for (const meter of input.meters) {
          const row = await call(
            "record_marketplace_meter_report",
            {
              configuration_id: input.configurationId,
              meter_id: meter.meterId,
              period_start: input.periodStart.toString(),
              period_end: input.periodEnd.toString(),
              quantity: meter.quantity,
              resource_external_id: meter.resourceId ?? "",
            },
            meterReportOf,
          );

          if (!row.ok) {
            return err(row.error);
          }

          stored.push(row.data);
        }

        const pending = await call(
          "unreported_marketplace_meter_reports",
          { configuration_id: input.configurationId },
          (value) => recordsOf(value, "unreported").map(meterReportOf),
        );

        if (!pending.ok) {
          return err(pending.error);
        }

        const periods = new Map<
          string,
          { start: string; end: string; reports: MeterReport[] }
        >();

        for (const report of pending.data) {
          const key = `${report.periodStart}\0${report.periodEnd}`;

          const period = periods.get(key) ?? {
            start: report.periodStart,
            end: report.periodEnd,
            reports: [],
          };

          period.reports.push(report);
          periods.set(key, period);
        }

        const accepted = new Map<string, number>();

        for (const { start, end, reports } of periods.values()) {
          const sent = await send(input.configurationId, "/billing", {
            timestamp: new Date().toISOString(),
            eod: end,
            period: { start, end },
            usage: reports.map((report) => ({
              ...(report.resourceExternalId === ""
                ? {}
                : { resourceId: report.resourceExternalId }),
              name: report.meterId,
              type: "total",
              units: "count",
              dayValue: Math.max(report.quantity - report.reportedQuantity, 0),
              periodValue: report.quantity,
            })),
          });

          if (!sent.ok) {
            return err(sent.error);
          }

          const marked = await call(
            "mark_marketplace_meter_sent",
            {
              reports: reports.map((report) => ({
                id: report.id,
                quantity: report.quantity,
              })),
            },
            () => undefined,
          );

          if (!marked.ok) {
            return err(marked.error);
          }

          for (const report of reports) {
            accepted.set(report.id, report.quantity);
          }
        }

        return ok(
          stored.map((report) => {
            const quantity = accepted.get(report.id);

            return quantity === undefined
              ? report
              : {
                  ...report,
                  reportedQuantity: quantity,
                  reported: quantity === report.quantity,
                };
          }),
        );
      }),

    removeInstallation: (configurationId) =>
      call(
        "remove_marketplace_installation",
        { configuration_id: configurationId },
        (value) => (isRecord(value) ? installationOf(value) : undefined),
      ),

    sealAccessToken: (configurationId, token) =>
      call(
        "seal_marketplace_access_token",
        { configuration_id: configurationId, access_token: token },
        () => undefined,
      ),

    linkTenant: (input) =>
      call(
        "link_marketplace_tenant",
        {
          configuration_id: input.configurationId,
          tenant: input.tenant,
          created: input.created ?? false,
        },
        installationOf,
      ),

    resource: (configurationId, externalId) =>
      call(
        "marketplace_resource",
        { configuration_id: configurationId, external_id: externalId },
        (value) => (isRecord(value) ? resourceOf(value) : undefined),
      ),

    resources: (configurationId) =>
      call(
        "marketplace_resources",
        { configuration_id: configurationId },
        (value) => recordsOf(value, "marketplace_resources").map(resourceOf),
      ),

    deleteResource: (configurationId, externalId) =>
      call(
        "delete_marketplace_resource",
        { configuration_id: configurationId, external_id: externalId },
        (value) => (isRecord(value) ? resourceOf(value) : undefined),
      ),

    usageRoute: (route) =>
      cronRoute(
        { name: "usage", secret: route.secret, problem: route.problem },
        async (_request, instance) => {
          let inputs: readonly ReportUsageInput[];

          try {
            inputs = await route.usage();
          } catch (cause) {
            return problemResponse(dbError("unexpected", errorText(cause)), {
              instance,
              realm: "vercel-marketplace",
              format: route.problem,
            });
          }

          const reported: string[] = [];
          const failed: string[] = [];

          for (const input of inputs) {
            const result = await hooked.reportUsage(input);

            if (result.ok) {
              reported.push(input.configurationId);
            } else {
              failed.push(input.configurationId);
              route.onError?.(result.error, input.configurationId);
            }
          }

          return Response.json(
            { reported, failed },
            { status: failed.length === 0 ? 200 : 502 },
          );
        },
      ),

    partnerApi: (partner) =>
      createPartnerApi({ marketplace: hooked, call, verifyToken }, partner),
  };

  const hooked = withBlockHooks(client, options.hooks, {
    block: "vercel-marketplace",
    ...(options.logger ? { logger: options.logger } : {}),
  });

  return hooked;
}
