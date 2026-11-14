import type {
  Count,
  FacetResult,
  ListPage,
  PageOptions,
} from "../../core/block-helpers.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type {
  CountOptions,
  FacetOptions,
  RequiredTenantOption,
} from "../../core/entity-list.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { BlockTemporalOptions } from "../shared.ts";
import type { TxtResolver } from "../sso/sso.ts";
import type {
  DomainProvider,
  DomainProviderCallOptions,
  DomainProviderRecord,
  DomainProviderStatus,
} from "./provider.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { entityList, tenantOrOption } from "../../core/entity-list.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  errorText,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
  toInstant,
} from "../shared.ts";
import { dohResolver } from "../sso/sso.ts";
import { domainProviderOf } from "./provider.ts";
import { hostnameListSurface } from "./lists.ts";

/** The DNS record that proves a custom domain belongs to the organization. */
export interface HostnameRecord {
  readonly type: "TXT";
  readonly name: string;
  readonly value: string;
}

export interface Hostname {
  readonly id: string;
  readonly organizationId: string;
  /** Lowercase, without a trailing dot or a port. */
  readonly hostname: string;
  /**
   * `subdomain` for one label below `blocks.domains.options.platformDomain`,
   * verified when added.
   */
  readonly kind: "custom" | "subdomain";
  readonly verifiedAt: Temporal.Instant | undefined;
  /** The hostname the organization's other hostnames redirect to. */
  readonly primary: boolean;
  readonly createdBy: string | undefined;
  readonly createdAt: Temporal.Instant;
  /** For a hostname not verified yet: publish this TXT record, then verify it. */
  readonly record: HostnameRecord | undefined;
}

/** The organization a request's hostname belongs to. */
export interface HostnameMatch {
  readonly organizationId: string;
  readonly hostname: string;
  readonly primary: boolean;
  /** The organization's primary hostname, to redirect to when this one isn't it. */
  readonly primaryHostname: string | undefined;
}

export interface DomainsOptions extends BlockTemporalOptions {
  /** The caller's transport (`rpcTransport(supabase)`). */
  readonly transport: BlockTransport;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`. Default `better_supabase`.
   */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /**
   * `withBlockHooks` hooks around the client's methods, such as a rule on which
   * hostnames a plan may add.
   */
  readonly hooks?: BlockHooks<Domains>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

export interface Domains {
  /**
   * Adds a hostname (needs `domains.manage`); a custom domain comes back with
   * its `record`.
   */
  add(input: {
    organizationId: string;
    hostname: string;
  }): AsyncResult<Hostname>;
  /** The organization's hostnames, primary first (needs `domains.read`). */
  list(organizationId: string): AsyncResult<readonly Hostname[]>;
  /**
   * One keyset page of the organization's hostnames, the primary first. Sort by
   * `hostname` or `createdAt`, filter by `kind` and `verified` (`true` or
   * `false`). Needs `domains.read`.
   */
  page(
    options: PageOptions & RequiredTenantOption,
  ): AsyncResult<ListPage<Hostname>>;
  /**
   * The values of each facet (`kind`, `verified`) and how many hostnames hold
   * each.
   */
  facets(
    options: FacetOptions & RequiredTenantOption,
  ): AsyncResult<readonly FacetResult[]>;
  /** How many hostnames match the page's filters. */
  count(options: CountOptions & RequiredTenantOption): AsyncResult<Count>;
  /** Makes a verified hostname the primary one. */
  setPrimary(hostnameId: string): AsyncResult<Hostname>;
  /** `false` when the caller manages no hostname with this id. */
  remove(hostnameId: string): AsyncResult<boolean>;
  /**
   * The organization that serves `host`, such as a request's `Host` header (the
   * port is ignored). `undefined` unless it is verified. Works signed out, for
   * the proxy.
   */
  resolve(host: string): AsyncResult<HostnameMatch | undefined>;
}

/**
 * A `Host` header as a hostname: lowercase, without the port and the trailing
 * dot. An IPv6 literal comes back in its brackets.
 */
export function normalizeHostname(host: string): string {
  const value = host.trim().toLowerCase();

  if (value.startsWith("[")) {
    const end = value.indexOf("]");

    return end === -1 ? value : value.slice(0, end + 1);
  }

  const colon = value.indexOf(":");
  const name = colon === -1 ? value : value.slice(0, colon);

  return name.endsWith(".") ? name.slice(0, -1) : name;
}

function recordFor(value: unknown): HostnameRecord | undefined {
  if (!isRecord(value)) {
    return undefined;
  }

  return {
    type: "TXT",
    name: textOf(value["name"]),
    value: textOf(value["value"]),
  };
}

function hostnameOf(value: unknown): Hostname {
  const row = recordOf(value, "hostnames");

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["tenant_id"]),
    hostname: textOf(row["hostname"]),
    kind: row["kind"] === "subdomain" ? "subdomain" : "custom",
    verifiedAt: optionalInstant(row["verified_at"]),
    primary: row["is_primary"] === true,
    createdBy: optionalText(row["created_by"]),
    createdAt: toInstant(textOf(row["created_at"])),
    record: recordFor(row["record"]),
  };
}

function matchOf(value: unknown): HostnameMatch | undefined {
  if (!isRecord(value)) {
    return undefined;
  }

  return {
    organizationId: textOf(value["organizationId"]),
    hostname: textOf(value["hostname"]),
    primary: value["primary"] === true,
    primaryHostname: optionalText(value["primaryHostname"]),
  };
}

/** An organization's hostnames as the caller, and the lookup for the proxy. */
export function createDomains(options: DomainsOptions): Domains {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const entries = entityList<Hostname, RequiredTenantOption>({
    entity: "hostname",
    surface: hostnameListSurface,
    call,
    tenant: tenantOrOption(undefined),
    fn: "list_hostnames",
    rowOf: hostnameOf,
  });

  const client: Domains = {
    add: ({ organizationId, hostname }) =>
      call("add_hostname", { tenant: organizationId, hostname }, hostnameOf),
    list: (organizationId) =>
      call("list_hostnames", { tenant: organizationId }, (value) =>
        recordsOf(value, "list_hostnames").map(hostnameOf),
      ),
    page: entries.page,
    facets: entries.facets,
    count: entries.count,
    setPrimary: (hostnameId) =>
      call("set_primary_hostname", { id: hostnameId }, hostnameOf),
    remove: (hostnameId) =>
      call("remove_hostname", { id: hostnameId }, (value) => value === true),
    resolve: (host) =>
      call("resolve_hostname", { hostname: normalizeHostname(host) }, matchOf),
  };

  return withBlockHooks(client, options.hooks, {
    block: "domains",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}

export interface DomainsAdminOptions extends BlockTemporalOptions {
  /**
   * A service-role transport: `verify_hostname` is granted to `service_role`
   * only.
   */
  readonly transport: BlockTransport;
  /** TXT lookups for `verify`. Default `dohResolver()`. */
  readonly resolver?: TxtResolver;
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /**
   * The hosting platform that serves the hostnames, such as
   * `vercelDomainProvider(...)`. With it, `verify` also needs the platform to
   * verify the hostname, and `add`, `remove` and `status` work.
   */
  readonly provider?: DomainProvider;
}

export interface DomainsAdmin {
  /**
   * Looks up the hostname's TXT record and marks it verified when the token is
   * there. With `actorId`, the database checks that they hold `domains.manage`;
   * omit it for app-owned calls. With a `provider`, the platform must verify
   * the hostname too (`DOMAIN_PROVIDER_UNVERIFIED` until it does).
   */
  verify(
    input: { hostnameId: string } & {
      readonly actorId?: string;
      readonly signal?: AbortSignal;
    },
  ): AsyncResult<Hostname>;
  /**
   * Adds the hostname to the `provider`'s project, with the platform's own
   * records to publish. Call it from a `hostname.added` handler, once
   * `domains.add` has stored the hostname.
   */
  add(input: {
    readonly hostnameId: string;
    readonly signal?: AbortSignal;
  }): AsyncResult<DomainProviderStatus>;
  /**
   * Removes the hostname from the `provider`'s project; `false` when it wasn't
   * there. Takes the hostname, not its id, because a `hostname.deleted` handler
   * runs after the row is gone.
   */
  remove(input: {
    readonly hostname: string;
    readonly signal?: AbortSignal;
  }): AsyncResult<boolean>;
  /** The hostname on the `provider`'s project; `undefined` when it isn't there. */
  status(input: {
    readonly hostnameId: string;
    readonly signal?: AbortSignal;
  }): AsyncResult<DomainProviderStatus | undefined>;
}

const callOptions = (
  signal: AbortSignal | undefined,
): DomainProviderCallOptions => (signal === undefined ? {} : { signal });

function recordsText(records: readonly DomainProviderRecord[]): string {
  return records
    .map((record) => `${record.type} ${record.name} ${record.value}`)
    .join(", ");
}

/** Hostname verification with a service-role client. */
export function createDomainsAdmin(options: DomainsAdminOptions): DomainsAdmin {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const resolver = options.resolver ?? dohResolver();

  const provider =
    options.provider === undefined
      ? undefined
      : domainProviderOf(options.provider);

  const byId = (hostnameId: string): AsyncResult<Hostname> =>
    call("hostname_by_id", { id: hostnameId }, (value) =>
      isRecord(value) ? hostnameOf(value) : undefined,
    ).andThen((found) =>
      Promise.resolve(
        found === undefined
          ? err(
              dbError("not_found", "No hostname has this id", {
                hint: "DOMAIN_NOT_FOUND",
              }),
            )
          : ok(found),
      ),
    );

  const withProvider = <T>(
    body: (provider: DomainProvider) => AsyncResult<T>,
  ): AsyncResult<T> =>
    provider === undefined
      ? AsyncResult.err(
          dbError(
            "invalid_request",
            "createDomainsAdmin was called without a provider",
            { hint: "DOMAIN_PROVIDER_MISSING" },
          ),
        )
      : body(provider);

  return {
    verify: ({ hostnameId, ...request }) =>
      byId(hostnameId).andThen(async (found) => {
        if (found.record !== undefined) {
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
                { hint: "DOMAIN_RECORD_MISSING" },
              ),
            );
          }
        }

        if (provider !== undefined) {
          const platform = await provider.verify(
            found.hostname,
            callOptions(request.signal),
          );

          if (!platform.ok) {
            return err(platform.error);
          }

          if (!platform.data.verified) {
            const { records } = platform.data;

            return err(
              dbError(
                "invalid_request",
                records.length === 0
                  ? `${provider.name} has not verified ${found.hostname} yet`
                  : `${provider.name} has not verified ${found.hostname} yet; publish ${recordsText(records)}`,
                { hint: "DOMAIN_PROVIDER_UNVERIFIED" },
              ),
            );
          }
        }

        return call(
          "verify_hostname",
          { id: hostnameId, actor: request.actorId ?? null },
          hostnameOf,
        );
      }),
    add: ({ hostnameId, signal }) =>
      withProvider((platform) =>
        byId(hostnameId).andThen((found) =>
          platform.add(found.hostname, callOptions(signal)),
        ),
      ),
    remove: ({ hostname, signal }) =>
      withProvider((platform) =>
        platform.remove(normalizeHostname(hostname), callOptions(signal)),
      ),
    status: ({ hostnameId, signal }) =>
      withProvider((platform) =>
        byId(hostnameId).andThen((found) =>
          platform.status(found.hostname, callOptions(signal)),
        ),
      ),
  };
}
