import type {
  JsonSchema,
  ModelResponse,
  ModelSecurityScheme,
  SecurityRequirement,
} from "./model.ts";
import type { ErrorResponse } from "./resource.ts";

import { PROBLEM_CONTENT_TYPE, problemType } from "../core/problem.ts";
import { schemaRef } from "./schemas.ts";

/** JSON Schema for RFC 9457 Problem Details as better-supabase sends them. */
export const PROBLEM_SCHEMA: Record<string, unknown> = {
  type: "object",
  required: ["type", "title", "status"],
  properties: {
    type: {
      type: "string",
      format: "uri-reference",
      examples: [problemType("not_found").type],
    },
    title: { type: "string" },
    status: { type: "integer", minimum: 100, maximum: 599 },
    detail: { type: "string" },
    instance: { type: "string" },
    kind: { type: "string" },
    code: { type: "string" },
    hint: { type: "string" },
    constraint: { type: "string" },
    column: { type: "string" },
    columns: { type: "array", items: { type: "string" } },
    required: { type: "string", enum: ["aal1", "aal2"] },
    scopes: { type: "array", items: { type: "string" } },
    permission: { type: "string" },
    approval: {
      type: "object",
      required: ["id"],
      properties: { id: { type: "string" } },
    },
    issues: {
      type: "array",
      items: {
        type: "object",
        required: ["message"],
        properties: {
          message: { type: "string" },
          path: { type: "array", items: { type: ["string", "integer"] } },
        },
      },
    },
  },
};

/** The default error responses: today's Problem Details answers, 400 to 422. */
export const DEFAULT_ERRORS: readonly ErrorResponse[] = [
  { name: "BadRequest", status: 400, description: "The request is invalid." },
  {
    name: "Unauthorized",
    status: 401,
    description: "Missing or invalid credentials.",
  },
  {
    name: "Forbidden",
    status: 403,
    description: "Row-level security or a plugin denied the request.",
  },
  { name: "NotFound", status: 404, description: "No row matches." },
  {
    name: "Conflict",
    status: 409,
    description: "A unique or foreign key constraint failed.",
  },
  {
    name: "Unprocessable",
    status: 422,
    description: "Validation or a check constraint failed.",
  },
];

/** Name of the shared 403 response of operations that declare a permission. */
export const PERMISSION_DENIED = "PermissionDenied";

const problem = (code: string, detail: string, extra: JsonSchema = {}) => ({
  value: {
    ...problemType("forbidden"),
    status: 403,
    kind: "forbidden",
    code,
    detail,
    ...extra,
  },
});

/** The 403 of an operation with a permission, with one example per problem code. */
export function permissionDeniedResponse(): ModelResponse {
  return {
    description:
      "The authorizer denied the permission (`PERMISSION_DENIED`), the token lacks an OAuth scope (`INSUFFICIENT_SCOPE`), the action needs an approval (`APPROVAL_REQUIRED`), or row-level security denied the request.",
    content: {
      [PROBLEM_CONTENT_TYPE]: {
        schema: schemaRef("Problem"),
        examples: {
          permissionDenied: {
            summary: "PERMISSION_DENIED",
            ...problem(
              "PERMISSION_DENIED",
              "Permission invoices.update is required",
              {
                permission: "invoices.update",
              },
            ),
          },
          insufficientScope: {
            summary: "INSUFFICIENT_SCOPE",
            ...problem(
              "INSUFFICIENT_SCOPE",
              "The token lacks a required scope",
              {
                scopes: ["invoices.update"],
              },
            ),
          },
          approvalRequired: {
            summary: "APPROVAL_REQUIRED",
            ...problem(
              "APPROVAL_REQUIRED",
              "invoices.update needs an approval",
              {
                permission: "invoices.update",
                approval: { id: "apr_123" },
              },
            ),
          },
        },
      },
    },
  };
}

export function errorResponse(error: ErrorResponse): ModelResponse {
  return {
    description: error.description,
    content: { [PROBLEM_CONTENT_TYPE]: { schema: schemaRef("Problem") } },
  };
}

/** A security scheme of your own, with the scopes its requirement asks for. */
export interface CustomSecurity {
  /** The component name of the scheme. */
  readonly name: string;
  readonly scheme: ModelSecurityScheme;
  readonly scopes?: readonly string[];
}

/**
 * `bearer`: a Supabase access token (`supabaseJwt`). `oauth2`: the
 * Supabase OAuth 2.1 server (`supabaseOAuth`, needs `supabaseUrl`).
 * `apiKey`: the project's publishable key in the `apikey` header
 * (`supabaseApiKey`). Each preset is one alternative requirement.
 */
export type SecurityPreset = "bearer" | "oauth2" | "apiKey" | CustomSecurity;

/** The scheme name of the `oauth2` preset. */
export const OAUTH_SCHEME = "supabaseOAuth";

export interface ResolvedSecurity {
  readonly schemes: Readonly<Record<string, ModelSecurityScheme>>;
  readonly requirements: readonly SecurityRequirement[];
}

/** Security schemes and top-level requirements for the presets. */
export function resolveSecurity(
  presets: readonly SecurityPreset[],
  supabaseUrl: string | undefined,
  oauthScopes: Readonly<Record<string, string>> = {},
): ResolvedSecurity {
  const schemes: Record<string, ModelSecurityScheme> = {};
  const requirements: SecurityRequirement[] = [];
  for (const preset of presets) {
    if (typeof preset === "object") {
      schemes[preset.name] = preset.scheme;
      requirements.push({ [preset.name]: preset.scopes ?? [] });
      continue;
    }
    switch (preset) {
      case "bearer":
        schemes["supabaseJwt"] = {
          type: "http",
          scheme: "bearer",
          bearerFormat: "JWT",
          description:
            "A Supabase access token. Requests run as that user under row-level security.",
        };
        requirements.push({ supabaseJwt: [] });
        break;
      case "oauth2": {
        if (!supabaseUrl)
          throw new TypeError(
            "better-supabase/spec: oauth2 security needs supabaseUrl",
          );
        const origin = supabaseUrl.replace(/\/$/, "");
        const auth = `${origin}/auth/v1`;
        schemes[OAUTH_SCHEME] = {
          type: "oauth2",
          description: "The Supabase OAuth 2.1 server.",
          flows: {
            authorizationCode: {
              authorizationUrl: `${auth}/oauth/authorize`,
              tokenUrl: `${auth}/oauth/token`,
              scopes: oauthScopes,
            },
          },
          metadataUrl: `${origin}/.well-known/oauth-authorization-server/auth/v1`,
        };
        requirements.push({ [OAUTH_SCHEME]: [] });
        break;
      }
      case "apiKey":
        schemes["supabaseApiKey"] = {
          type: "apiKey",
          name: "apikey",
          in: "header",
          description: "The project's publishable key.",
        };
        requirements.push({ supabaseApiKey: [] });
        break;
      default: {
        const exhaustive: never = preset;
        throw new TypeError(`Unknown security preset "${String(exhaustive)}"`);
      }
    }
  }
  return { schemes, requirements };
}
