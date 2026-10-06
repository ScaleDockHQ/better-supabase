import type { BlockTransport } from "../../core/block-transport.ts";
import type { DbError, ErrorMapper } from "../../core/errors.ts";

import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok, type Result } from "../../core/result.ts";
import {
  blockCall,
  errorText,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  stringsOf,
  textOf,
  toInstant,
  type BlockTemporalOptions,
  applyTemporal,
} from "../shared.ts";

/** The DNS record that proves a domain belongs to the organization. */
export interface DomainRecord {
  readonly type: "TXT";
  readonly name: string;
  readonly value: string;
}

export interface OrganizationDomain {
  readonly id: string;
  readonly organizationId: string;
  readonly domain: string;
  readonly verifiedAt: Temporal.Instant | undefined;
  /** New users with a confirmed email at the domain join with this role. */
  readonly autoJoinRole: string | undefined;
  /** Sessions of users at the domain need SAML (`sso_access_token_check`). */
  readonly enforceSso: boolean;
  readonly createdBy: string | undefined;
  readonly createdAt: Temporal.Instant;
  /** Publish this TXT record, then call `verifyDomain`. */
  readonly record: DomainRecord;
}

export interface SsoProvider {
  /** The Supabase Auth SSO provider id, for `signInWithSSO({ providerId })`. */
  readonly id: string;
  readonly organizationId: string;
  readonly type: "saml";
  readonly metadataUrl: string | undefined;
  readonly domains: readonly string[];
  readonly createdAt: Temporal.Instant;
}

/** The provider an email address signs in with. */
export interface SsoDomain {
  readonly domain: string;
  readonly organizationId: string;
  readonly providerId: string;
  readonly enforceSso: boolean;
}

export interface SsoOptions extends BlockTemporalOptions {
  /** The caller's transport (`rpcTransport(supabase)`). */
  readonly transport: BlockTransport;
  /** The module schema (`sql.modules.sso.schema`), default `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

export interface Sso {
  /** Claims a domain (needs `sso.manage`); publish its `record`, then verify it. */
  addDomain(
    organizationId: string,
    domain: string,
  ): AsyncResult<OrganizationDomain>;
  domains(organizationId: string): AsyncResult<readonly OrganizationDomain[]>;
  /** Sets auto-join and SSO enforcement; both need a verified domain. */
  updateDomain(
    domainId: string,
    settings: {
      readonly autoJoinRole?: string | null;
      readonly enforceSso?: boolean;
    },
  ): AsyncResult<OrganizationDomain>;
  removeDomain(domainId: string): AsyncResult<boolean>;
  providers(organizationId: string): AsyncResult<readonly SsoProvider[]>;
  /** The SSO provider for an email address, for the sign-in page. Works signed out. */
  domainFor(email: string): AsyncResult<SsoDomain | undefined>;
}

function recordOfDomain(value: unknown): DomainRecord {
  const row = recordOf(value, "organization_domains.record");
  return {
    type: "TXT",
    name: textOf(row["name"]),
    value: textOf(row["value"]),
  };
}

function domainOf(value: unknown): OrganizationDomain {
  const row = recordOf(value, "organization_domains");
  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organization_id"]),
    domain: textOf(row["domain"]),
    verifiedAt: optionalInstant(row["verified_at"]),
    autoJoinRole: optionalText(row["auto_join_role"]),
    enforceSso: row["enforce_sso"] === true,
    createdBy: optionalText(row["created_by"]),
    createdAt: toInstant(textOf(row["created_at"])),
    record: recordOfDomain(row["record"]),
  };
}

function providerOf(value: unknown): SsoProvider {
  const row = recordOf(value, "organization_sso_providers");
  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organization_id"]),
    type: "saml",
    metadataUrl: optionalText(row["metadata_url"]),
    domains: stringsOf(row["domains"]),
    createdAt: toInstant(textOf(row["created_at"])),
  };
}

function ssoDomainOf(value: unknown): SsoDomain | undefined {
  if (!isRecord(value)) return undefined;
  return {
    domain: textOf(value["domain"]),
    organizationId: textOf(value["organizationId"]),
    providerId: textOf(value["providerId"]),
    enforceSso: value["enforceSso"] === true,
  };
}

/** Organization domains and SSO lookups as the caller. */
export function createSso(options: SsoOptions): Sso {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  return {
    addDomain: (organizationId, domain) =>
      call(
        "add_organization_domain",
        { tenant: organizationId, domain },
        domainOf,
      ),
    domains: (organizationId) =>
      call("list_organization_domains", { tenant: organizationId }, (value) =>
        recordsOf(value, "list_organization_domains").map(domainOf),
      ),
    updateDomain: (domainId, settings) =>
      call("organization_domain", { id: domainId }, (value) =>
        isRecord(value) ? domainOf(value) : undefined,
      ).andThen(async (current) =>
        current === undefined
          ? err(
              dbError("not_found", "No domain you manage has this id", {
                hint: "SSO_DOMAIN_NOT_FOUND",
              }),
            )
          : call(
              "update_organization_domain",
              {
                id: domainId,
                auto_join_role:
                  settings.autoJoinRole === undefined
                    ? (current.autoJoinRole ?? null)
                    : settings.autoJoinRole,
                enforce_sso: settings.enforceSso ?? current.enforceSso,
              },
              domainOf,
            ),
      ),
    removeDomain: (domainId) =>
      call(
        "remove_organization_domain",
        { id: domainId },
        (value) => value === true,
      ),
    providers: (organizationId) =>
      call("list_sso_providers", { tenant: organizationId }, (value) =>
        recordsOf(value, "list_sso_providers").map(providerOf),
      ),
    domainFor: (email) => call("sso_domain_for", { email }, ssoDomainOf),
  };
}

/** Looks up the TXT strings at a name; an empty list when it has none. */
export type TxtResolver = (
  name: string,
  signal?: AbortSignal,
) => Promise<readonly string[]>;

export interface DohResolverOptions {
  /** A DNS-over-HTTPS JSON endpoint. Default Cloudflare's `https://cloudflare-dns.com/dns-query`. */
  readonly endpoint?: string;
  readonly fetch?: typeof fetch;
}

const NXDOMAIN = 3;
const TXT = 16;

/** TXT lookups over DNS-over-HTTPS (the `application/dns-json` API). */
export function dohResolver(options: DohResolverOptions = {}): TxtResolver {
  const endpoint = options.endpoint ?? "https://cloudflare-dns.com/dns-query";
  const fetcher = options.fetch ?? fetch;
  return async (name, signal) => {
    const url = new URL(endpoint);
    url.searchParams.set("name", name);
    url.searchParams.set("type", "TXT");
    const response = await fetcher(url, {
      headers: { accept: "application/dns-json" },
      ...(signal ? { signal } : {}),
    });
    if (!response.ok) {
      throw new Error(`DNS lookup of ${name} failed with ${response.status}`);
    }
    const body: unknown = await response.json();
    if (!isRecord(body))
      throw new Error(`DNS lookup of ${name} returned no JSON`);
    if (body["Status"] === NXDOMAIN) return [];
    if (body["Status"] !== 0) {
      throw new Error(
        `DNS lookup of ${name} failed with status ${String(body["Status"])}`,
      );
    }
    const answers = Array.isArray(body["Answer"]) ? body["Answer"] : [];
    return answers
      .filter((answer) => isRecord(answer) && answer["type"] === TXT)
      .map((answer) =>
        txtValue(textOf(isRecord(answer) ? answer["data"] : "")),
      );
  };
}

/** `"abc" "def"` (one record split into strings) gives `abcdef`. */
function txtValue(data: string): string {
  const parts = [...data.matchAll(/"((?:[^"\\]|\\.)*)"/g)].map((match) =>
    (match[1] ?? "").replaceAll(/\\(.)/g, "$1"),
  );
  return parts.length === 0 ? data : parts.join("");
}

export interface SsoAuthAdmin {
  /** The project URL (`SUPABASE_URL`). */
  readonly url: string;
  /** A secret or service-role key. Server-only. */
  readonly secretKey: string;
  readonly fetch?: typeof fetch;
}

export interface SsoAdminOptions extends BlockTemporalOptions {
  /** A service-role transport: these functions are granted to `service_role` only. */
  readonly transport: BlockTransport;
  /** Supabase Auth's admin API, for SAML providers. */
  readonly auth?: SsoAuthAdmin;
  /** TXT lookups for `verifyDomain`. Default `dohResolver()`. */
  readonly resolver?: TxtResolver;
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

/** Who asked, so the database checks `sso.manage`; omit for app-owned calls. */
export interface SsoActor {
  readonly actorId?: string;
}

export type SamlMetadata =
  | { readonly metadataUrl: string; readonly metadataXml?: never }
  | { readonly metadataXml: string; readonly metadataUrl?: never };

export type SamlProviderInput = SamlMetadata & {
  /** Verified domains of the organization whose users sign in with this provider. */
  readonly domains: readonly string[];
  /** Supabase Auth's `attribute_mapping`, such as `{ keys: { email: { name: "mail" } } }`. */
  readonly attributeMapping?: Readonly<Record<string, unknown>>;
  readonly nameIdFormat?: string;
};

export interface SsoAdmin {
  /** Looks up the domain's TXT record and marks it verified when the token is there. */
  verifyDomain(
    domainId: string,
    options?: SsoActor & { readonly signal?: AbortSignal },
  ): AsyncResult<OrganizationDomain>;
  /** Creates a SAML provider in Supabase Auth and records it for the organization. */
  addSamlProvider(
    organizationId: string,
    input: SamlProviderInput,
    options?: SsoActor,
  ): AsyncResult<SsoProvider>;
  updateSamlProvider(
    providerId: string,
    input: Partial<SamlProviderInput> & { readonly domains: readonly string[] },
    options?: SsoActor,
  ): AsyncResult<SsoProvider>;
  /** Deletes the provider from Supabase Auth; `undefined` when the organization has no such provider. */
  removeSamlProvider(
    providerId: string,
    options?: SsoActor,
  ): AsyncResult<SsoProvider | undefined>;
}

function authStatusError(status: number, message: string): DbError {
  if (status === 400 || status === 422)
    return dbError("invalid_input", message);
  if (status === 401) return dbError("unauthorized", message);
  if (status === 403) return dbError("forbidden", message);
  if (status === 404) return dbError("not_found", message);
  if (status === 409) return dbError("conflict", message);
  if (status === 429) return dbError("rate_limited", message);
  return dbError("network", message);
}

/** Domain verification and SAML providers with a service-role client. */
export function createSsoAdmin(options: SsoAdminOptions): SsoAdmin {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const resolver = options.resolver ?? dohResolver();

  const auth = (
    method: "POST" | "PUT" | "DELETE",
    path: string,
    body?: unknown,
  ): AsyncResult<Record<string, unknown>> =>
    AsyncResult.from(async (): Promise<Result<Record<string, unknown>>> => {
      const admin = options.auth;
      if (!admin) {
        return err(
          dbError(
            "invalid_request",
            "Pass auth to createSsoAdmin to manage SAML providers",
          ),
        );
      }
      const fetcher = admin.fetch ?? fetch;
      let response: Response;
      try {
        response = await fetcher(
          `${admin.url.replace(/\/+$/, "")}/auth/v1/admin/sso/providers${path}`,
          {
            method,
            headers: {
              apikey: admin.secretKey,
              authorization: `Bearer ${admin.secretKey}`,
              "content-type": "application/json",
            },
            ...(body === undefined ? {} : { body: JSON.stringify(body) }),
          },
        );
      } catch (cause) {
        return err(dbError("network", errorText(cause)));
      }
      const text = await response.text();
      let json: unknown;
      try {
        json = text.length > 0 ? JSON.parse(text) : {};
      } catch {
        json = {};
      }
      if (!response.ok) {
        const message = isRecord(json)
          ? (optionalText(json["msg"]) ??
            optionalText(json["message"]) ??
            optionalText(json["error_description"]))
          : undefined;
        return err(
          authStatusError(
            response.status,
            message ?? `Supabase Auth answered ${response.status}`,
          ),
        );
      }
      return ok(isRecord(json) ? json : {});
    });

  const providerBody = (
    input: Partial<SamlProviderInput>,
  ): Record<string, unknown> => ({
    type: "saml",
    ...(input.metadataUrl === undefined
      ? {}
      : { metadata_url: input.metadataUrl }),
    ...(input.metadataXml === undefined
      ? {}
      : { metadata_xml: input.metadataXml }),
    ...(input.domains === undefined ? {} : { domains: [...input.domains] }),
    ...(input.attributeMapping === undefined
      ? {}
      : { attribute_mapping: input.attributeMapping }),
    ...(input.nameIdFormat === undefined
      ? {}
      : { name_id_format: input.nameIdFormat }),
  });

  const register = (
    organizationId: string,
    providerId: string,
    domains: readonly string[],
    metadataUrl: string | undefined,
    actor: SsoActor,
  ): AsyncResult<SsoProvider> =>
    call(
      "register_sso_provider",
      {
        tenant: organizationId,
        provider: providerId,
        domains,
        metadata_url: metadataUrl ?? null,
        actor: actor.actorId ?? null,
      },
      providerOf,
    );

  const providerFor = (
    providerId: string,
    actor: SsoActor,
  ): AsyncResult<SsoProvider | undefined> =>
    call(
      "sso_provider",
      { provider: providerId, actor: actor.actorId ?? null },
      (value) => (isRecord(value) ? providerOf(value) : undefined),
    );
  const missing = (): Result<never> =>
    err(
      dbError("not_found", "No SSO provider has this id", {
        hint: "SSO_PROVIDER_NOT_FOUND",
      }),
    );
  const path = (providerId: string): string =>
    `/${encodeURIComponent(providerId)}`;

  return {
    verifyDomain: (domainId, request = {}) =>
      call("organization_domain", { id: domainId }, (value) =>
        isRecord(value) ? domainOf(value) : undefined,
      ).andThen(async (found) => {
        if (found === undefined) {
          return err(
            dbError("not_found", "No domain has this id", {
              hint: "SSO_DOMAIN_NOT_FOUND",
            }),
          );
        }
        if (found.verifiedAt === undefined) {
          let values: readonly string[];
          try {
            values = await resolver(found.record.name, request.signal);
          } catch (cause) {
            return err(dbError("network", errorText(cause)));
          }
          if (!values.includes(found.record.value)) {
            return err(
              dbError(
                "invalid_request",
                `No TXT record ${found.record.name} with the verification value yet`,
                { hint: "SSO_DOMAIN_RECORD_MISSING" },
              ),
            );
          }
        }
        return call(
          "verify_organization_domain",
          { id: domainId, actor: request.actorId ?? null },
          domainOf,
        );
      }),
    addSamlProvider: (organizationId, input, actor = {}) =>
      call(
        "check_sso_provider",
        {
          tenant: organizationId,
          domains: input.domains,
          actor: actor.actorId ?? null,
        },
        () => undefined,
      )
        .andThen(() => auth("POST", "", providerBody(input)))
        .andThen(async (created) => {
          const providerId = textOf(created["id"]);
          const recorded = await register(
            organizationId,
            providerId,
            input.domains,
            input.metadataUrl,
            actor,
          );
          if (!recorded.ok) await auth("DELETE", path(providerId));
          return recorded;
        }),
    updateSamlProvider: (providerId, input, actor = {}) =>
      providerFor(providerId, actor).andThen(async (found) => {
        if (found === undefined) return missing();
        const checked = await call(
          "check_sso_provider",
          {
            tenant: found.organizationId,
            domains: input.domains,
            actor: actor.actorId ?? null,
          },
          () => undefined,
        );
        if (!checked.ok) return checked;
        const updated = await auth(
          "PUT",
          path(providerId),
          providerBody(input),
        );
        if (!updated.ok) return updated;
        const metadataUrl =
          input.metadataXml === undefined
            ? (input.metadataUrl ?? found.metadataUrl)
            : undefined;
        return register(
          found.organizationId,
          providerId,
          input.domains,
          metadataUrl,
          actor,
        );
      }),
    removeSamlProvider: (providerId, actor = {}) =>
      providerFor(providerId, actor).andThen(async (found) => {
        if (found === undefined) return ok(undefined);
        const deleted = await auth("DELETE", path(providerId));
        if (!deleted.ok && deleted.error.kind !== "not_found") return deleted;
        return call(
          "unregister_sso_provider",
          { provider: providerId, actor: actor.actorId ?? null },
          () => found,
        );
      }),
  };
}
