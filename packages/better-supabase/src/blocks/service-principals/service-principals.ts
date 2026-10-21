import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";

import {
  type BlockFields,
  blockFields,
  type FieldsOf,
  readAllFields,
  readFields,
  type RowFields,
  rowFields,
} from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
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
 * The part of `supabase.auth.admin` the block uses, typed structurally so any
 * Supabase client fits.
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

export interface ServicePrincipalsOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  /** A service-role transport: every function but `list` is service only. */
  readonly transport: BlockTransport;
  /** `supabase.auth.admin` of a service-role client. */
  readonly admin: ServicePrincipalAuthAdmin;
  /**
   * The module schema, or its API schema: `defineBlocks` passes it from
   * `blocks.generated.ts`. Default `better_supabase`.
   */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<ServicePrincipals<FieldsOf<S>>>>;
  /**
   * A Standard Schema for the extra columns of the principals table
   * (`blocks.service-principals.options.extraColumns`): writes are validated,
   * reads parsed.
   */
  readonly fields?: S;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

export interface ServicePrincipal<F extends object = Record<never, never>> {
  readonly id: string;
  readonly name: string;
  readonly role: string;
  readonly isDefault: boolean;
  readonly createdBy: string | null;
  readonly createdAt: Temporal.Instant;
  readonly disabledAt: Temporal.Instant | null;
  /** The app's extra columns (`options.extraColumns`), by column name. */
  readonly fields: RowFields<F>;
}

/**
 * Who asks for a change. With `createdBy`, that member needs
 * `service_principals.manage` and may assign the role; without it the service
 * acts on its own.
 */
export interface ServicePrincipalActor {
  readonly createdBy?: string;
}

export interface CreateServicePrincipalOptions<
  F extends object = Record<never, never>,
> extends ServicePrincipalActor {
  /** Makes it the tenant's default, which organization-owned work runs as. */
  readonly default?: boolean;
  /** Values for the app's extra columns (`options.extraColumns`). */
  readonly fields?: Partial<F> & Readonly<Record<string, unknown>>;
}

export interface CreatedServicePrincipal<
  F extends object = Record<never, never>,
> {
  readonly id: string;
  readonly organizationId: string;
  readonly name: string;
  readonly role: string;
  readonly isDefault: boolean;
  /** The app's extra columns (`options.extraColumns`), by column name. */
  readonly fields: RowFields<F>;
}

/** The `service-principals` SQL module as typed calls. */
export interface ServicePrincipals<F extends object = Record<never, never>> {
  /**
   * Creates an `auth.users` row that can't sign in (banned, no password, an
   * address under `.invalid`), then registers it with `role` in the
   * organization. A refused registration deletes the user again.
   */
  readonly create: (
    organizationId: string,
    name: string,
    role: string,
    options?: CreateServicePrincipalOptions<F>,
  ) => AsyncResult<CreatedServicePrincipal<F>>;
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
  ) => AsyncResult<readonly ServicePrincipal<F>[]>;
}

export function createServicePrincipals<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: ServicePrincipalsOptions<S>): ServicePrincipals<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const fields: BlockFields<F> = blockFields(
    options.fields,
    "service principal fields",
  );

  const { admin } = options;

  const client: ServicePrincipals<F> = {
    create: (organizationId, name, role, extra = {}) =>
      AsyncResult.from(async () => {
        const checked =
          extra.fields === undefined
            ? ok(undefined)
            : await fields.write({ ...extra.fields });

        if (!checked.ok) {
          return checked;
        }

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
            fields: checked.data,
          },
          (value) => {
            const row = recordOf(value, "register_service_principal");

            return {
              id: textOf(row["id"]),
              organizationId: textOf(row["tenant"]),
              name: textOf(row["name"]),
              role: textOf(row["role"]),
              isDefault: row["isDefault"] === true,
              fields: rowFields(row["fields"]),
            };
          },
        );

        if (!registered.ok) {
          await admin.deleteUser(user.id);

          return err(registered.error);
        }

        return readFields(fields, registered.data);
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
          fields: rowFields(row["fields"]),
        })),
      ).andThen((principals) => readAllFields(fields, principals)),
  };

  return withBlockHooks(client, options.hooks, {
    block: "service-principals",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
