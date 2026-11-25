import type {
  BlockFields,
  FieldsOf,
  RowFields,
} from "../../core/block-fields.ts";
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
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import {
  blockFields,
  getAllFields,
  getFields,
  rowFields,
} from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { entityList, tenantOrOption } from "../../core/entity-list.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  nullableInstant,
  nullableText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";
import { principalListSurface } from "./lists.ts";

/** The `app_metadata` key that marks an `auth.users` row as a service principal. */
export const SERVICE_PRINCIPAL_CLAIM = "bsb_service_principal";

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

export interface ServiceAccountsOptions<
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
  readonly hooks?: NoInfer<BlockHooks<ServiceAccounts<FieldsOf<S>>>>;
  /**
   * A Standard Schema for the extra columns of the principals table (the
   * columns your schema files add): writes are validated, reads parsed.
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
  /**
   * The app's extra columns (the columns the app's schema files add), by column
   * name.
   */
  readonly fields: RowFields<F>;
}

/**
 * Who asks for a change. With `createdBy`, that member needs
 * `service_accounts.manage` and may assign the role; without it the service
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
  /**
   * Values for the app's extra columns (the columns the app's schema files
   * add).
   */
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
  /**
   * The app's extra columns (the columns the app's schema files add), by column
   * name.
   */
  readonly fields: RowFields<F>;
}

/** The `service-accounts` SQL module as typed calls. */
export interface ServiceAccounts<F extends object = Record<never, never>> {
  /**
   * Creates an `auth.users` row that can't sign in (banned, no password, an
   * address under `.invalid`), then registers it with `role` in the
   * organization. A refused registration deletes the user again.
   */
  readonly create: (
    input: {
      organizationId: string;
      name: string;
      role: string;
    } & CreateServicePrincipalOptions<F>,
  ) => AsyncResult<CreatedServicePrincipal<F>>;
  readonly setRole: (
    input: { id: string; role: string } & ServicePrincipalActor,
  ) => AsyncResult<boolean>;
  /** Removes its membership and default; `false` when it was already off. */
  readonly disable: (
    input: { id: string } & ServicePrincipalActor,
  ) => AsyncResult<boolean>;
  /** The organization's default principal, or `null`. */
  readonly defaultFor: (organizationId: string) => AsyncResult<string | null>;
  /**
   * One keyset page of the organization's principals, through the read policy.
   * `filters` takes `role`, `isDefault` and `disabled` as lists.
   */
  readonly principalPage: (
    options: PageOptions & RequiredTenantOption,
  ) => AsyncResult<ListPage<ServicePrincipal<F>>>;
  /**
   * The values of each facet (`role`, `isDefault`, `disabled`) and how many
   * rows hold each.
   */
  readonly principalFacets: (
    options: FacetOptions & RequiredTenantOption,
  ) => AsyncResult<readonly FacetResult[]>;
  /** How many principals match the page's filters. */
  readonly principalCount: (
    options: CountOptions & RequiredTenantOption,
  ) => AsyncResult<Count>;
  /**
   * The organization's principals, through the read policy.
   *
   * @deprecated Use `principalPage`, which pages by keyset and takes `q`,
   * sorts, array filters and a count (ADR 1077).
   */
  readonly list: (
    organizationId: string,
    options?: { readonly limit?: number },
  ) => AsyncResult<readonly ServicePrincipal<F>[]>;
}

function principalOf(value: unknown) {
  const row = recordOf(value, "service_principals");

  return {
    id: textOf(row["id"]),
    name: textOf(row["name"]),
    role: textOf(row["role"]),
    isDefault: row["isDefault"] === true,
    createdBy: nullableText(row["createdBy"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    disabledAt: nullableInstant(row["disabledAt"]),
    fields: rowFields(row["fields"]),
  };
}

export function createServiceAccounts<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: ServiceAccountsOptions<S>): ServiceAccounts<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);

  const fields: BlockFields<F> = blockFields(
    options.fields,
    "service principal fields",
  );

  const { admin } = options;

  const principals = entityList<
    ReturnType<typeof principalOf>,
    RequiredTenantOption
  >({
    entity: "service principal",
    surface: principalListSurface,
    call,
    tenant: tenantOrOption(undefined),
    fn: "page_service_principals",
    rowOf: (row) => principalOf(row),
  });

  const finished = <
    T extends { readonly items: readonly ReturnType<typeof principalOf>[] },
  >(
    page: AsyncResult<T>,
  ) =>
    page.andThen((found) =>
      getAllFields(fields, found.items).map((items) => ({ ...found, items })),
    );

  const client: ServiceAccounts<F> = {
    principalPage: (page) => finished(principals.page(page)),
    principalFacets: (facets) => principals.facets(facets),
    principalCount: (count) => principals.count(count),
    create: ({ organizationId, name, role, ...extra }) =>
      AsyncResult.from(async () => {
        const checked =
          extra.fields === undefined
            ? ok(undefined)
            : await fields.write({ ...extra.fields });

        if (!checked.ok) {
          return checked;
        }

        const created = await admin.createUser({
          email: `${crypto.randomUUID()}@service-accounts.invalid`,
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

        return getFields(fields, registered.data);
      }),
    setRole: ({ id, role, ...extra }) =>
      call(
        "set_service_principal_role",
        { principal: id, role, created_by: extra.createdBy ?? null },
        (value) => value === true,
      ),
    disable: ({ id, ...extra }) =>
      call(
        "disable_service_principal",
        { principal: id, created_by: extra.createdBy ?? null },
        (value) => value === true,
      ),
    defaultFor: (organizationId) =>
      call("default_service_principal", { tenant: organizationId }, (value) =>
        nullableText(value),
      ),
    // oxlint-disable-next-line typescript/no-deprecated -- the deprecated alias is still implemented until 0.70 (ADR 1077)
    list: (organizationId, options) =>
      call("service_principals_list", { tenant: organizationId }, (value) => {
        const rows = recordsOf(value, "service_principals_list").map(
          principalOf,
        );

        return options?.limit === undefined
          ? rows
          : rows.slice(0, options.limit);
      }).andThen((principals) => getAllFields(fields, principals)),
  };

  return withBlockHooks(client, options.hooks, {
    block: "service-accounts",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
