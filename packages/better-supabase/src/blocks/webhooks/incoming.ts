import type { DbError } from "../../core/errors.ts";
import type { SqlClient } from "../../postgres/executor.ts";

import { dbError, mapDbError } from "../../core/errors.ts";
import {
  type BlockProblemOptions,
  problemResponse,
} from "../../core/problem.ts";
import { AsyncResult, err, ok, toDbError } from "../../core/result.ts";
import { fromPgError } from "../../postgres/executor.ts";
import { isRecord, optionalText } from "../shared.ts";
import { timingSafeEqual, verifyWebhook } from "./verify.ts";

// ---------------------------------------------------------------------------
// Incoming webhook endpoints (SQL module `webhooks-in`)

/** How a delivery proves it came from the sender. */
export type IncomingVerify = "none" | "standard-webhooks" | "hmac-sha256";

export interface IncomingWebhooksOptions extends BlockProblemOptions {
  /** The schema of the `webhooks-in` module. Defaults to `better_supabase`. */
  readonly schema?: string;
  /** The webhook inbox source deliveries are stored under. Defaults to `webhook-in`. */
  readonly source?: string;
  /**
   * Deliveries per endpoint and period, counted with the `rate-limit`
   * module's `hit_rate_limit`. Unset: no limit.
   */
  readonly rateLimit?: {
    readonly max: number;
    /** Seconds, or a Postgres interval such as `1 minute`. */
    readonly period: number | string;
  };
  /** Request headers stored with each delivery. Defaults to none. */
  readonly keepHeaders?: readonly string[];
}

export interface CreateIncomingWebhookInput {
  readonly tenant: string;
  readonly name: string;
  /** Defaults to `none`: the token in the URL is the only credential. */
  readonly verify?: IncomingVerify;
  readonly metadata?: Readonly<Record<string, unknown>>;
  /** The header that carries the HMAC for `hmac-sha256`. Defaults to `x-signature`. */
  readonly signatureHeader?: string;
  /** The record the endpoint belongs to, a type from `options.subjects`. */
  readonly subject?: { readonly type: string; readonly id: string };
}

/** An endpoint as members see it: everything but the token and secret. */
export interface IncomingWebhook {
  readonly id: string;
  readonly tenant: string;
  readonly name: string;
  readonly verify: IncomingVerify;
  readonly signatureHeader: string | null;
  readonly enabled: boolean;
  readonly maxBodyBytes: number;
  readonly receiveCount: number;
  readonly lastReceivedAt: string | null;
  readonly lastStatus: number | null;
  readonly metadata: Readonly<Record<string, unknown>>;
  readonly subject: { readonly type: string; readonly id: string } | null;
  readonly createdBy: string | null;
  readonly createdAt: string;
}

/** A new endpoint: its token (for the URL) and secret are shown once. */
export interface CreatedIncomingWebhook {
  readonly id: string;
  readonly tenant: string;
  readonly name: string;
  readonly verify: IncomingVerify;
  readonly token: string;
  readonly secret: string | null;
  readonly signatureHeader: string | null;
  readonly subject: { readonly type: string; readonly id: string } | null;
}

export interface IncomingWebhooks {
  /**
   * The route for `/hooks/<token>`: finds the endpoint, checks the body
   * size, the rate limit and the signature, stores the delivery in the
   * webhook inbox with the endpoint's tenant and answers 202 (200 for a
   * repeated `webhook-id`). Needs a service connection.
   */
  receive(request: Request, token: string): Promise<Response>;
  /** Creates an endpoint for a tenant; the caller needs `webhooks.manage`. */
  create(
    input: CreateIncomingWebhookInput,
  ): AsyncResult<CreatedIncomingWebhook>;
  /** A new token, and with `rotateSecret` a new secret. */
  rotate(
    id: string,
    options?: { readonly rotateSecret?: boolean },
  ): AsyncResult<{ readonly token: string; readonly secret: string | null }>;
  setEnabled(id: string, enabled: boolean): AsyncResult<boolean>;
  remove(id: string): AsyncResult<boolean>;
  /**
   * A tenant's endpoints, or one subject's, as the caller sees them (the
   * read policy hides endpoints whose subject they can't read).
   */
  list(
    tenant: string,
    subject?: { readonly type: string; readonly id?: string },
  ): AsyncResult<readonly IncomingWebhook[]>;
}

/** The header that carries an endpoint's id on stored deliveries. */
export const INCOMING_ENDPOINT_HEADER = "x-bs-endpoint-id";

interface EndpointRow {
  readonly id: string;
  readonly tenant: string;
  readonly enabled: boolean;
  readonly verify: IncomingVerify;
  readonly secret: string | null;
  readonly signature_header: string | null;
  readonly max_body_bytes: number;
}

const IDENT = /^[a-z_][a-z0-9_]*$/;

const encoder = /* @__PURE__ */ new TextEncoder();

async function hmacHex(secret: string, body: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = new Uint8Array(
    await crypto.subtle.sign("HMAC", key, encoder.encode(body)),
  );
  return Array.from(mac, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function asDbError(cause: unknown): DbError {
  const raw = fromPgError(cause);
  return raw ? mapDbError(raw) : toDbError(cause);
}

const attempt = <T>(fn: () => Promise<T>): AsyncResult<T> =>
  AsyncResult.from(async () => {
    try {
      return ok(await fn());
    } catch (cause) {
      return err(asDbError(cause));
    }
  });

/**
 * Tenant-owned trigger URLs over the `webhooks-in` SQL module: create
 * endpoints, then route `/hooks/<token>` to `receive`. Deliveries land in
 * the webhook inbox (`createInbox`), where a worker processes them.
 */
export function createIncomingWebhooks(
  sql: SqlClient,
  options: IncomingWebhooksOptions = {},
): IncomingWebhooks {
  const schema = options.schema ?? "better_supabase";
  if (!IDENT.test(schema)) {
    throw new TypeError(
      `createIncomingWebhooks: "${schema}" is not a schema name`,
    );
  }
  const source = options.source ?? "webhook-in";
  const fn = (name: string) => `"${schema}"."${name}"`;

  const value = async <T>(text: string, params: unknown[]): Promise<T> => {
    const [row] = await sql.queryRaw<{ value: T }>(text, params);
    return row!.value;
  };

  return {
    async receive(request, token) {
      const instance = new URL(request.url).pathname;
      if (request.method !== "POST") {
        return new Response(null, { status: 405, headers: { allow: "POST" } });
      }
      const problem = (error: DbError, endpoint?: string) =>
        (endpoint === undefined
          ? Promise.resolve()
          : sql
              .queryRaw(`select ${fn("record_incoming_webhook")}($1, $2)`, [
                endpoint,
                error.status,
              ])
              .then(() => undefined)
        ).then(() =>
          problemResponse(error, { instance, format: options.problem }),
        );
      try {
        const [endpoint] = await sql.queryRaw<EndpointRow>(
          `select * from ${fn("incoming_webhook_by_token")}($1)`,
          [token],
        );
        if (!endpoint?.enabled) {
          return await problem(
            dbError("not_found", "No such webhook endpoint"),
          );
        }
        const length = Number(request.headers.get("content-length") ?? 0);
        const body =
          length > endpoint.max_body_bytes ? undefined : await request.text();
        if (
          body === undefined ||
          encoder.encode(body).length > endpoint.max_body_bytes
        ) {
          return await problem(
            {
              ...dbError("invalid_input", "The body is too large", {
                code: "WEBHOOK_TOO_LARGE",
              }),
              status: 413,
            },
            endpoint.id,
          );
        }
        if (options.rateLimit) {
          const [hit] = await sql.queryRaw<{
            allowed: boolean;
            retry_after: number;
          }>(
            "select * from better_supabase.hit_rate_limit($1, $2, $3, $4::interval)",
            [
              `${source}:endpoint`,
              endpoint.id,
              options.rateLimit.max,
              typeof options.rateLimit.period === "number"
                ? `${String(options.rateLimit.period)} seconds`
                : options.rateLimit.period,
            ],
          );
          if (hit && !hit.allowed) {
            return await problem(
              dbError("rate_limited", "Too many deliveries", {
                retryAfter: Math.max(1, hit.retry_after),
              }),
              endpoint.id,
            );
          }
        }
        let messageId =
          request.headers.get("webhook-id") ?? crypto.randomUUID();
        if (endpoint.verify === "standard-webhooks") {
          const verified = await verifyWebhook(
            { headers: request.headers, body },
            endpoint.secret ?? "",
          );
          if (!verified.ok) return await problem(verified.error, endpoint.id);
          messageId = verified.data.id;
        } else if (endpoint.verify === "hmac-sha256") {
          const given =
            request.headers.get(endpoint.signature_header ?? "x-signature") ??
            "";
          const expected = await hmacHex(endpoint.secret ?? "", body);
          if (!timingSafeEqual(given.replace(/^sha256=/, ""), expected)) {
            return await problem(
              dbError("unauthorized", "Invalid webhook signature", {
                code: "WEBHOOK_INVALID_SIGNATURE",
              }),
              endpoint.id,
            );
          }
        }
        let payload: unknown = body;
        try {
          const parsed: unknown = body === "" ? {} : JSON.parse(body);
          payload = parsed;
        } catch {
          payload = { body };
        }
        const kept: [string, string][] = (options.keepHeaders ?? []).flatMap(
          (name): [string, string][] => {
            const header = request.headers.get(name);
            return header === null ? [] : [[name.toLowerCase(), header]];
          },
        );
        const headers = Object.fromEntries([
          ...kept,
          [INCOMING_ENDPOINT_HEADER, endpoint.id],
        ]);
        const [stored] = await sql.queryRaw<{
          id: string | number;
          duplicate: boolean;
        }>(
          "select * from better_supabase.receive_webhook($1, $2, $3, $4, $5, $6)",
          [
            source,
            `${endpoint.id}:${messageId}`,
            typeof payload === "object" &&
            payload !== null &&
            "type" in payload &&
            typeof payload.type === "string"
              ? payload.type
              : null,
            JSON.stringify(payload),
            JSON.stringify(headers),
            endpoint.tenant,
          ],
        );
        const status = stored?.duplicate ? 200 : 202;
        await sql.queryRaw(`select ${fn("record_incoming_webhook")}($1, $2)`, [
          endpoint.id,
          status,
        ]);
        return Response.json(
          { id: Number(stored?.id), duplicate: stored?.duplicate ?? false },
          { status },
        );
      } catch (cause) {
        return problemResponse(asDbError(cause), {
          instance,
          format: options.problem,
        });
      }
    },
    create: (input) =>
      attempt(async () => {
        const created = await value<{
          id: string;
          tenant: string | number;
          name: string;
          verify: IncomingVerify;
          token: string;
          secret: string | null;
          signatureHeader: string | null;
          subjectType: string | null;
          subjectId: string | null;
        }>(
          `select ${fn("create_incoming_webhook")}($1, $2, $3, $4, $5, $6, $7) as value`,
          [
            input.tenant,
            input.name,
            input.verify ?? "none",
            JSON.stringify(input.metadata ?? {}),
            input.signatureHeader ?? null,
            input.subject?.type ?? null,
            input.subject?.id ?? null,
          ],
        );
        const { subjectType, subjectId, ...rest } = created;
        return {
          ...rest,
          tenant: String(created.tenant),
          subject:
            subjectType && subjectId
              ? { type: subjectType, id: subjectId }
              : null,
        };
      }),
    list: (tenant, subject) =>
      attempt(async () => {
        const rows = await value<readonly Record<string, unknown>[]>(
          `select ${fn("list_incoming_webhooks")}($1, $2, $3) as value`,
          [tenant, subject?.type ?? null, subject?.id ?? null],
        );
        return rows.map((row): IncomingWebhook => ({
          id: String(row["id"]),
          tenant: String(row["tenant"]),
          name: String(row["name"]),
          // SAFETY: the table's check constraint limits verify to IncomingVerify.
          verify: row["verify"] as IncomingVerify,
          signatureHeader: optionalText(row["signature_header"]) ?? null,
          enabled: row["enabled"] === true,
          maxBodyBytes: Number(row["max_body_bytes"]),
          receiveCount: Number(row["receive_count"]),
          lastReceivedAt: optionalText(row["last_received_at"]) ?? null,
          lastStatus:
            row["last_status"] === null ? null : Number(row["last_status"]),
          metadata: isRecord(row["metadata"]) ? row["metadata"] : {},
          subject:
            typeof row["subject_type"] === "string" &&
            typeof row["subject_id"] === "string"
              ? { type: row["subject_type"], id: row["subject_id"] }
              : null,
          createdBy: optionalText(row["created_by"]) ?? null,
          createdAt: String(row["created_at"]),
        }));
      }),
    rotate: (id, rotateOptions = {}) =>
      attempt(async () => {
        const rotated = await value<{ token: string; secret: string | null }>(
          `select ${fn("rotate_incoming_webhook")}($1, $2) as value`,
          [id, rotateOptions.rotateSecret ?? false],
        );
        return { token: rotated.token, secret: rotated.secret };
      }),
    setEnabled: (id, enabled) =>
      attempt(() =>
        value<boolean>(
          `select ${fn("set_incoming_webhook_enabled")}($1, $2) as value`,
          [id, enabled],
        ),
      ),
    remove: (id) =>
      attempt(() =>
        value<boolean>(`select ${fn("delete_incoming_webhook")}($1) as value`, [
          id,
        ]),
      ),
  };
}
