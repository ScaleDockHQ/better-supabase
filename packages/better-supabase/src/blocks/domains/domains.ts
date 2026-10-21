import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError } from "../../core/errors.ts";
import { err } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  type BlockTemporalOptions,
  errorText,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
  toInstant,
} from "../shared.ts";
import { dohResolver, type TxtResolver } from "../sso/sso.ts";

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
  add(organizationId: string, hostname: string): AsyncResult<Hostname>;
  /** The organization's hostnames, primary first (needs `domains.read`). */
  list(organizationId: string): AsyncResult<readonly Hostname[]>;
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
  const row = recordOf(value, "organization_hostnames");

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organization_id"]),
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

  const client: Domains = {
    add: (organizationId, hostname) =>
      call("add_hostname", { tenant: organizationId, hostname }, hostnameOf),
    list: (organizationId) =>
      call("list_hostnames", { tenant: organizationId }, (value) =>
        recordsOf(value, "list_hostnames").map(hostnameOf),
      ),
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
}

export interface DomainsAdmin {
  /**
   * Looks up the hostname's TXT record and marks it verified when the token is
   * there. With `actorId`, the database checks that they hold `domains.manage`;
   * omit it for app-owned calls.
   */
  verify(
    hostnameId: string,
    options?: { readonly actorId?: string; readonly signal?: AbortSignal },
  ): AsyncResult<Hostname>;
}

/** Hostname verification with a service-role client. */
export function createDomainsAdmin(options: DomainsAdminOptions): DomainsAdmin {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const resolver = options.resolver ?? dohResolver();

  return {
    verify: (hostnameId, request = {}) =>
      call("hostname_by_id", { id: hostnameId }, (value) =>
        isRecord(value) ? hostnameOf(value) : undefined,
      ).andThen(async (found) => {
        if (found === undefined) {
          return err(
            dbError("not_found", "No hostname has this id", {
              hint: "HOSTNAME_NOT_FOUND",
            }),
          );
        }

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
                { hint: "HOSTNAME_RECORD_MISSING" },
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
  };
}
