import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";

import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  type BlockTemporalOptions,
  nullableInstant,
  nullableText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

/** The `app_metadata` key that marks an `auth.users` row as a service principal. */
export const SERVICE_PRINCIPAL_CLAIM = "bs_service_principal";

/** About 100 years: GoTrue refuses every sign-in while the user is banned. */
const BAN_DURATION = "876000h";

/**
 * The part of `supabase.auth.admin` the block uses, typed structurally so
 * any Supabase client fits.
 */
export interface ServicePrincipalAuthAdmin {
  createUser(attributes: {
    email: string;
    email_confirm: boolean;
    ban_duration: string;
    app_metadata: Record<string, unknown>;
    user_metadata: Record<string, unknown>;
  }): PromiseLike<{
    data: { user: { id: string } | null };
    error: { message: string } | null;
  }>;
  deleteUser(id: string): PromiseLike<{ error: { message: string } | null }>;
}

export interface ServicePrincipalsOptions extends BlockTemporalOptions {
  /** A service-role transport: every function but `list` is service only. */
  readonly transport: BlockTransport;
  /** `supabase.auth.admin` of a service-role client. */
  readonly admin: ServicePrincipalAuthAdmin;
  /** `blocks.service-principals.schema`. Defaults to `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

export interface ServicePrincipal {
  readonly id: string;
  readonly name: string;
  readonly role: string;
  readonly isDefault: boolean;
  readonly createdBy: string | null;
  readonly createdAt: Temporal.Instant;
  readonly disabledAt: Temporal.Instant | null;
}

/**
 * Who asks for a change. With `createdBy`, that member needs
 * `service_principals.manage` and may assign the role; without it the
 * service acts on its own.
 */
export interface ServicePrincipalActor {
  readonly createdBy?: string;
}

export interface CreateServicePrincipalOptions extends ServicePrincipalActor {
  /** Makes it the tenant's default, which organization-owned work runs as. */
  readonly default?: boolean;
}

export interface CreatedServicePrincipal {
  readonly id: string;
  readonly organizationId: string;
  readonly name: string;
  readonly role: string;
  readonly isDefault: boolean;
}

/** The `service-principals` SQL module as typed calls. */
export interface ServicePrincipals {
  /**
   * Creates an `auth.users` row that can't sign in (banned, no password,
   * an address under `.invalid`), then registers it with `role` in the
   * organization. A refused registration deletes the user again.
   */
  readonly create: (
    organizationId: string,
    name: string,
    role: string,
    options?: CreateServicePrincipalOptions,
  ) => AsyncResult<CreatedServicePrincipal>;
  readonly setRole: (
    id: string,
    role: string,
    options?: ServicePrincipalActor,
  ) => AsyncResult<boolean>;
  /** Removes its membership and default; `false` when it was already off. */
  readonly disable: (
    id: string,
    options?: ServicePrincipalActor,
  ) => AsyncResult<boolean>;
  /** The organization's default principal, or `null`. */
  readonly defaultFor: (organizationId: string) => AsyncResult<string | null>;
  /** The organization's principals, through the read policy. */
  readonly list: (
    organizationId: string,
  ) => AsyncResult<readonly ServicePrincipal[]>;
}

export function createServicePrincipals(
  options: ServicePrincipalsOptions,
): ServicePrincipals {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const { admin } = options;
  return {
    create: (organizationId, name, role, extra = {}) =>
      AsyncResult.from(async () => {
        const created = await admin.createUser({
          email: `${crypto.randomUUID()}@service-principals.invalid`,
          email_confirm: true,
          ban_duration: BAN_DURATION,
          app_metadata: {
            [SERVICE_PRINCIPAL_CLAIM]: true,
            organization_id: organizationId,
          },
          user_metadata: { name },
        });
        const user = created.data.user;
        if (created.error !== null || user === null) {
          return err(
            dbError(
              "unexpected",
              `Auth refused the service principal user: ${created.error?.message ?? "no user returned"}`,
            ),
          );
        }
        const registered = await call(
          "register_service_principal",
          {
            principal: user.id,
            tenant: organizationId,
            name,
            role,
            is_default: extra.default ?? false,
            created_by: extra.createdBy ?? null,
          },
          (value) => {
            const row = recordOf(value, "register_service_principal");
            return {
              id: textOf(row["id"]),
              organizationId: textOf(row["tenant"]),
              name: textOf(row["name"]),
              role: textOf(row["role"]),
              isDefault: row["isDefault"] === true,
            };
          },
        );
        if (!registered.ok) {
          await admin.deleteUser(user.id);
          return err(registered.error);
        }
        return ok(registered.data);
      }),
    setRole: (id, role, extra = {}) =>
      call(
        "set_service_principal_role",
        { principal: id, role, created_by: extra.createdBy ?? null },
        (value) => value === true,
      ),
    disable: (id, extra = {}) =>
      call(
        "disable_service_principal",
        { principal: id, created_by: extra.createdBy ?? null },
        (value) => value === true,
      ),
    defaultFor: (organizationId) =>
      call("default_service_principal", { tenant: organizationId }, (value) =>
        nullableText(value),
      ),
    list: (organizationId) =>
      call("service_principals_list", { tenant: organizationId }, (value) =>
        recordsOf(value, "service_principals_list").map((row) => ({
          id: textOf(row["id"]),
          name: textOf(row["name"]),
          role: textOf(row["role"]),
          isDefault: row["isDefault"] === true,
          createdBy: nullableText(row["createdBy"]),
          createdAt: requiredInstant(row["createdAt"], "createdAt"),
          disabledAt: nullableInstant(row["disabledAt"]),
        })),
      ),
  };
}
