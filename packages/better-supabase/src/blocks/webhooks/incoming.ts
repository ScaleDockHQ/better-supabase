import type { DbError } from "../../core/errors.ts";
import type {
  EndpointRow,
  IncomingVerify,
  IncomingWebhook,
  IncomingWebhooks,
  IncomingWebhooksOptions,
} from "./incoming-types.ts";

import {
  asDbError,
  blockCall,
  DEFAULT_BLOCK_SCHEMA,
} from "../../core/block-helpers.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { sqlTransport } from "../../core/block-transport.ts";
import { dbError } from "../../core/errors.ts";
import { methodNotAllowed, problemResponse } from "../../core/problem.ts";
import {
  hmacHex,
  timingSafeEqual,
  verifyWebhook,
} from "../../core/signatures.ts";
import { hitRateLimit } from "../queue/rate-limit.ts";
import {
  applyTemporal,
  isRecord,
  optionalText,
  readBodyCapped,
  recordOf,
  recordsOf,
  toInstant,
} from "../shared.ts";
import { inboxDestination } from "./destinations.ts";

/** The header that carries an endpoint's id on stored deliveries. */
export const INCOMING_ENDPOINT_HEADER = "x-bsb-endpoint-id";

const IDENT = /^[a-z_][a-z0-9_]*$/;

const VERIFY_MODES: readonly IncomingVerify[] = [
  "none",
  "standard-webhooks",
  "hmac-sha256",
  "shared-secret",
];

function verifyOf(value: unknown): IncomingVerify {
  const mode = VERIFY_MODES.find((entry) => entry === value);

  if (mode === undefined) {
    throw new TypeError(`Unknown verification mode ${String(value)}`);
  }

  return mode;
}

/**
 * Tenant-owned trigger URLs over the `webhooks-in` SQL module: create
 * endpoints, then route `/hooks/<token>` to `receive`. Deliveries land in the
 * webhook inbox (`createWebhookInbox`), where a worker processes them, or in
 * `options.destination`.
 */
export function createIncomingWebhooks(
  options: IncomingWebhooksOptions,
): IncomingWebhooks {
  applyTemporal(options);
  const { sql } = options;
  const schema = options.schema ?? DEFAULT_BLOCK_SCHEMA;

  if (!IDENT.test(schema)) {
    throw new TypeError(
      `createIncomingWebhooks: "${schema}" is not a schema name`,
    );
  }

  const source = options.source ?? "webhook-in";
  const destination = options.destination ?? inboxDestination(sql);
  const fn = (name: string) => `"${schema}"."${name}"`;

  const call = blockCall(
    options.transport ?? sqlTransport(sql),
    schema,
    options.mappers,
  );

  const client: IncomingWebhooks = {
    async receive(request, token) {
      const instance = new URL(request.url).pathname;

      if (request.method !== "POST") {
        return methodNotAllowed(["POST"]);
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

        const body = await readBodyCapped(request, endpoint.max_body_bytes);

        if (body === undefined) {
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
          const hit = await hitRateLimit(
            sql,
            `${source}:endpoint`,
            endpoint.id,
            options.rateLimit.max,
            typeof options.rateLimit.period === "number"
              ? `${String(options.rateLimit.period)} seconds`
              : options.rateLimit.period,
          );

          if (!hit.allowed) {
            return await problem(
              dbError("rate_limited", "Too many deliveries", {
                retryAfter: Math.max(1, hit.retryAfter),
              }),
              endpoint.id,
            );
          }
        }

        let messageId =
          request.headers.get("webhook-id") ??
          request.headers.get("svix-id") ??
          crypto.randomUUID();

        if (endpoint.verify === "standard-webhooks") {
          let verified = await verifyWebhook(
            { headers: request.headers, body },
            endpoint.secret ?? "",
          );

          if (!verified.ok && endpoint.previous_secret) {
            const previous = await verifyWebhook(
              { headers: request.headers, body },
              endpoint.previous_secret,
            );

            if (previous.ok) {
              verified = previous;
            }
          }

          if (!verified.ok) {
            return await problem(verified.error, endpoint.id);
          }

          messageId = verified.data.id;
        } else if (endpoint.verify === "shared-secret") {
          const given =
            request.headers.get(
              endpoint.signature_header ?? "x-webhook-secret",
            ) ?? "";

          const matches =
            (endpoint.secret !== null &&
              timingSafeEqual(given, endpoint.secret)) ||
            (endpoint.previous_secret !== null &&
              endpoint.previous_secret !== undefined &&
              timingSafeEqual(given, endpoint.previous_secret));

          if (given === "" || !matches) {
            return await problem(
              dbError("unauthorized", "Invalid webhook secret", {
                code: "WEBHOOK_INVALID_SIGNATURE",
              }),
              endpoint.id,
            );
          }
        } else if (endpoint.verify === "hmac-sha256") {
          const given =
            request.headers.get(endpoint.signature_header ?? "x-signature") ??
            "";

          const signature = given.replace(/^sha256=/, "");
          let expected = await hmacHex(endpoint.secret ?? "", body);

          if (
            !timingSafeEqual(signature, expected) &&
            endpoint.previous_secret
          ) {
            const previous = await hmacHex(endpoint.previous_secret, body);

            if (timingSafeEqual(signature, previous)) {
              expected = previous;
            }
          }

          if (!timingSafeEqual(signature, expected)) {
            return await problem(
              dbError("unauthorized", "Invalid webhook signature", {
                code: "WEBHOOK_INVALID_SIGNATURE",
              }),
              endpoint.id,
            );
          }

          // The signature covers only the body, so an id header could be
          // changed to replay it. The HMAC itself is the id: a replayed
          // body is a duplicate.
          messageId = `hmac:${expected}`;
        }

        let payload: unknown = body;

        try {
          const parsed: unknown = body === "" ? {} : JSON.parse(body);
          payload = parsed;
        } catch {
          payload = { body };
        }

        const secretHeader =
          endpoint.verify === "shared-secret"
            ? (endpoint.signature_header ?? "x-webhook-secret").toLowerCase()
            : undefined;

        const kept: [string, string][] = (options.keepHeaders ?? []).flatMap(
          (name): [string, string][] => {
            if (name.toLowerCase() === secretHeader) {
              return [];
            }

            const header = request.headers.get(name);

            return header === null ? [] : [[name.toLowerCase(), header]];
          },
        );

        const headers = Object.fromEntries([
          ...kept,
          [INCOMING_ENDPOINT_HEADER, endpoint.id],
        ]);

        const stored = await destination.deliver({
          endpoint: {
            id: endpoint.id,
            tenant: endpoint.tenant,
            metadata: isRecord(endpoint.metadata) ? endpoint.metadata : {},
          },
          source,
          messageId,
          type:
            typeof payload === "object" &&
            payload !== null &&
            "type" in payload &&
            typeof payload.type === "string"
              ? payload.type
              : null,
          payload,
          headers,
        });

        const status = stored.duplicate ? 200 : 202;
        await sql.queryRaw(`select ${fn("record_incoming_webhook")}($1, $2)`, [
          endpoint.id,
          status,
        ]);

        return Response.json(
          { id: stored.id, duplicate: stored.duplicate },
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
      call(
        "create_incoming_webhook",
        {
          tenant: input.tenant,
          name: input.name,
          verify: input.verify ?? "none",
          metadata: input.metadata ?? {},
          signature_header: input.signatureHeader ?? null,
          subject_type: input.subject?.type ?? null,
          subject_id: input.subject?.id ?? null,
        },
        (value) => {
          const created = recordOf(value, "create_incoming_webhook");
          const subjectType = optionalText(created["subjectType"]);
          const subjectId = optionalText(created["subjectId"]);

          return {
            id: String(created["id"]),
            tenant: String(created["tenant"]),
            name: String(created["name"]),
            verify: verifyOf(created["verify"]),
            token: String(created["token"]),
            secret: optionalText(created["secret"]) ?? null,
            signatureHeader: optionalText(created["signatureHeader"]) ?? null,
            subject:
              subjectType && subjectId
                ? { type: subjectType, id: subjectId }
                : null,
          };
        },
      ),
    list: (tenant, subject) =>
      call(
        "list_incoming_webhooks",
        {
          tenant,
          subject_type: subject?.type ?? null,
          subject_id: subject?.id ?? null,
        },
        (value) =>
          recordsOf(value, "list_incoming_webhooks").map(
            (row): IncomingWebhook => ({
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
            }),
          ),
      ),
    rotate: (id, rotateOptions = {}) =>
      call(
        "rotate_incoming_webhook",
        { endpoint: id, rotate_secret: rotateOptions.rotateSecret ?? false },
        (value) => {
          const rotated = recordOf(value, "rotate_incoming_webhook");

          return {
            token: String(rotated["token"]),
            secret: optionalText(rotated["secret"]) ?? null,
          };
        },
      ),
    rotateSecret: (id, rotateOptions = {}) =>
      call(
        "rotate_incoming_webhook_secret",
        {
          endpoint: id,
          grace:
            rotateOptions.grace === undefined
              ? null
              : String(rotateOptions.grace),
        },
        (value) => {
          const rotated = recordOf(value, "rotate_incoming_webhook_secret");
          const expires = optionalText(rotated["previousSecretExpiresAt"]);

          return {
            secret: String(rotated["secret"]),
            previousSecretExpiresAt:
              expires === undefined ? null : toInstant(expires),
          };
        },
      ),
    update: (id, input) =>
      call(
        "update_incoming_webhook",
        {
          endpoint: id,
          name: input.name ?? null,
          metadata: input.metadata ?? null,
          verify: input.verify ?? null,
          signature_header: input.signatureHeader ?? null,
        },
        (value) => {
          const updated = recordOf(value, "update_incoming_webhook");

          return {
            id: String(updated["id"]),
            tenant: String(updated["tenant"]),
            name: String(updated["name"]),
            verify: verifyOf(updated["verify"]),
            secret: optionalText(updated["secret"]) ?? null,
            signatureHeader: optionalText(updated["signatureHeader"]) ?? null,
            metadata: isRecord(updated["metadata"]) ? updated["metadata"] : {},
          };
        },
      ),
    setEnabled: (id, enabled) =>
      call(
        "set_incoming_webhook_enabled",
        { endpoint: id, enabled },
        (value) => value === true,
      ),
    remove: (id) =>
      call(
        "delete_incoming_webhook",
        { endpoint: id },
        (value) => value === true,
      ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "incoming-webhooks",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
