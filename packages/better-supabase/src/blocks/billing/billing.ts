import type {
  BillingEventData,
  BlockEventType,
} from "../../core/block-events.ts";
import type { Result } from "../../core/result.ts";
import type { StripeClient } from "../stripe.ts";
import type { BillingEvents } from "./events.ts";
import type { BillingParty } from "./stripe-helpers.ts";
import type {
  Billing,
  BillingOptions,
  CustomerAccountOptions,
  CustomerDetails,
  PlatformListOptions,
  SeatSync,
  StripeEvent,
  StripeEventOutcome,
  StripeRow,
  SubscriptionItem,
  TenantStripeRow,
} from "./types.ts";

import { blockEmitter } from "../../core/block-events.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import { entitlementMembers } from "../entitlements/entitlements.ts";
import {
  applyTemporal,
  blockCall,
  isRecord,
  optionalInstant,
  optionalText,
  pageOf,
  recordOf,
  textOf,
} from "../shared.ts";
import { lazyStripe } from "../stripe.ts";
import { billingReads } from "./reads.ts";
import {
  ORGANIZATION_KEY,
  SEAT_EVENT,
  accountParams,
  checkoutParams,
  customerIdOf,
  isStripeEvent,
  metadataTenant,
  stripeCall,
  subscriptionItemOf,
  syncedTaxId,
  checkoutBlockedError,
  subscriptionRecord,
} from "./stripe-helpers.ts";

/**
 * Stripe customers, checkout, the portal and seat sync over the `billing`
 * module.
 */
export function createBilling(options: BillingOptions): Billing {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const stripe = lazyStripe(options.stripe);

  const withStripe = <T>(
    work: (client: StripeClient) => Promise<T>,
  ): AsyncResult<T> => stripeCall(async () => work(await stripe()));

  const emitEvent = blockEmitter<BillingEvents>(options);

  const emit = (
    type: BlockEventType<BillingEvents>,
    data: BillingEventData,
  ): void => {
    emitEvent(
      type,
      data,
      `organizations/${data.organizationId}`,
      data.organizationId,
    );
  };

  const customer = (organizationId: string): AsyncResult<string | undefined> =>
    call("billing_customer", { tenant: organizationId }, optionalText);

  const link = (
    organizationId: string,
    customerId: string,
  ): AsyncResult<string> =>
    call(
      "link_billing_customer",
      { tenant: organizationId, customer: customerId },
      textOf,
    );

  const missing = (what: string): Result<never> =>
    err(
      dbError("invalid_request", `The Stripe client has no ${what}`, {
        hint: "BILLING_STRIPE_CLIENT",
      }),
    );

  const accountMode =
    options.customerAccounts !== undefined &&
    options.customerAccounts !== false;

  const accountOptions: CustomerAccountOptions =
    typeof options.customerAccounts === "object"
      ? options.customerAccounts
      : {};

  const account = (organizationId: string): AsyncResult<string | undefined> =>
    call("billing_account", { tenant: organizationId }, optionalText);

  const linkAccount = (
    organizationId: string,
    accountId: string,
  ): AsyncResult<string> =>
    call(
      "link_billing_account",
      { tenant: organizationId, account: accountId },
      textOf,
    );

  const ensureAccount = ({
    organizationId,
    details = {},
  }: {
    organizationId: string;
    details?: CustomerDetails | undefined;
  }): AsyncResult<string> =>
    account(organizationId).andThen(async (existing) => {
      if (existing !== undefined) {
        return ok(existing);
      }

      const resolved = await stripeCall(async () =>
        accountOptions.resolve?.(organizationId),
      );

      if (!resolved.ok) {
        return resolved;
      }

      let accountId = resolved.data;

      if (accountId === undefined) {
        const created = await withStripe(async (client) =>
          client.v2?.core.accounts.create(
            accountParams(organizationId, details, accountOptions.params),
            // Two first calls racing for one organization get one account.
            { idempotencyKey: `account:${organizationId}` },
          ),
        );

        if (!created.ok) {
          return created;
        }

        if (created.data === undefined) {
          return missing("v2.core.accounts");
        }

        accountId = created.data.id;
      }

      const linked = await linkAccount(organizationId, accountId);

      if (linked.ok && linked.data === accountId) {
        emit("billing.account_linked", { organizationId, accountId });
      }

      return linked;
    });

  const ensureCustomer = ({
    organizationId,
    details = {},
  }: {
    organizationId: string;
    details?: CustomerDetails | undefined;
  }): AsyncResult<string> =>
    customer(organizationId).andThen(async (existing) => {
      if (existing !== undefined) {
        return ok(existing);
      }

      if (accountMode) {
        const ensured = await ensureAccount({ organizationId, details });

        return ensured.ok
          ? err(
              dbError(
                "not_found",
                "Stripe creates the account's customer at its first checkout",
                { hint: "BILLING_CUSTOMER_PENDING" },
              ),
            )
          : ensured;
      }

      const created = await withStripe((client) =>
        client.customers.create(
          {
            ...(details.email === undefined ? {} : { email: details.email }),
            ...(details.name === undefined ? {} : { name: details.name }),
            metadata: { [ORGANIZATION_KEY]: organizationId },
          },
          // Two first calls racing for one organization get one customer.
          { idempotencyKey: `customer:${organizationId}` },
        ),
      );

      if (!created.ok) {
        return created;
      }

      const linked = await link(organizationId, created.data.id);

      if (linked.ok && linked.data === created.data.id) {
        emit("billing.customer_linked", {
          organizationId,
          customerId: linked.data,
        });
      }

      return linked;
    });

  /**
   * Whom Stripe bills for the tenant, without creating anyone: the account
   * first with `customerAccounts`, the customer first without.
   */
  const partyOf = (
    organizationId: string,
  ): AsyncResult<BillingParty | undefined> =>
    customer(organizationId).andThen(
      async (customerId): Promise<Result<BillingParty | undefined>> => {
        if (customerId !== undefined && !accountMode) {
          return ok({ customer: customerId });
        }

        const accountId = await account(organizationId);

        if (!accountId.ok) {
          return accountId;
        }

        if (accountId.data !== undefined) {
          return ok({ customer_account: accountId.data });
        }

        return ok(
          customerId === undefined ? undefined : { customer: customerId },
        );
      },
    );

  const checkoutParty = (
    organizationId: string,
    details: CustomerDetails,
  ): AsyncResult<BillingParty> =>
    accountMode
      ? partyOf(organizationId).andThen(async (found) =>
          found === undefined
            ? ensureAccount({ organizationId, details }).map(
                (accountId): BillingParty => ({ customer_account: accountId }),
              )
            : ok(found),
        )
      : ensureCustomer({ organizationId, details }).map(
          (customerId): BillingParty => ({ customer: customerId }),
        );

  const tenantOf = (id: string): AsyncResult<string | undefined> =>
    call("billing_customer_tenant", { customer: id }, optionalText);

  const seats = (organizationId: string): AsyncResult<number> =>
    call("billing_seat_count", { tenant: organizationId }, (value) =>
      Number(value ?? 0),
    );

  const item = (
    organizationId: string,
  ): AsyncResult<SubscriptionItem | undefined> =>
    call(
      "billing_subscription_item",
      { tenant: organizationId, price: options.seatPrice },
      subscriptionItemOf,
    );

  const syncSeats = ({
    organizationId,
    ...sync
  }: { organizationId: string } & {
    readonly key?: string;
  }): AsyncResult<SeatSync> =>
    seats(organizationId).andThen(
      async (quantity): Promise<Result<SeatSync>> => {
        const current = await item(organizationId);

        if (!current.ok) {
          return current;
        }

        const found = current.data;

        if (found === undefined || found.quantity === quantity) {
          return ok({
            quantity,
            previousQuantity: found?.quantity,
            changed: false,
          });
        }

        const key = `seats:${found.itemId}:${String(found.quantity)}:${String(quantity)}:${sync.key ?? crypto.randomUUID()}`;

        const updated = await withStripe((client) =>
          client.subscriptionItems.update(
            found.itemId,
            {
              quantity,
              proration_behavior:
                options.prorationBehavior ?? "create_prorations",
            },
            { idempotencyKey: key },
          ),
        );

        if (!updated.ok) {
          return updated;
        }

        emit("billing.seats_synced", {
          organizationId,
          subscriptionId: found.subscriptionId,
          quantity,
          previousQuantity: found.quantity,
        });

        return ok({
          quantity,
          previousQuantity: found.quantity,
          changed: true,
        });
      },
    );

  const invalidate = async (event: StripeEvent): Promise<readonly string[]> => {
    if (!options.sessions) {
      return [];
    }

    const members = await entitlementMembers(options.sessions.sql, event);

    if (!members.ok) {
      return [];
    }

    for (const userId of members.data) {
      options.sessions.invalidate(userId);
    }

    return members.data;
  };

  const handleStripeEvent = (input: unknown): AsyncResult<StripeEventOutcome> =>
    AsyncResult.from(async () => {
      const ignored: StripeEventOutcome = {
        event: undefined,
        organizationId: undefined,
        customerId: undefined,
        accountId: undefined,
        invalidated: [],
      };

      if (!isStripeEvent(input)) {
        return ok(ignored);
      }

      if (
        options.connectEvents === "ignore" &&
        typeof input.account === "string" &&
        input.account !== ""
      ) {
        return ok(ignored);
      }

      const object = input.data.object;

      if (!isRecord(object)) {
        return ok(ignored);
      }

      const customerId = customerIdOf(object["customer"]);
      const accountId = customerIdOf(object["customer_account"]);
      const unlinked = { ...ignored, customerId, accountId };

      if (input.type === "checkout.session.completed") {
        const organizationId =
          metadataTenant(object) ?? optionalText(object["client_reference_id"]);

        if (
          organizationId === undefined ||
          (customerId === undefined && accountId === undefined)
        ) {
          return ok(unlinked);
        }

        if (accountId !== undefined) {
          const linked = await linkAccount(organizationId, accountId);

          if (!linked.ok) {
            return linked;
          }

          if (linked.data !== accountId) {
            return ok(unlinked);
          }
        }

        let linkedCustomer: string | undefined;

        if (customerId !== undefined) {
          const linked = await link(organizationId, customerId);

          if (!linked.ok) {
            return linked;
          }

          linkedCustomer = linked.data;
        }

        emit("billing.checkout_completed", {
          organizationId,
          ...(linkedCustomer === undefined
            ? {}
            : { customerId: linkedCustomer }),
          ...(accountId === undefined ? {} : { accountId }),
          stripeEventId: input.id,
          ...(typeof object["subscription"] === "string"
            ? { subscriptionId: object["subscription"] }
            : {}),
        });

        return ok({
          event: "billing.checkout_completed",
          organizationId,
          customerId: linkedCustomer,
          accountId,
          invalidated: [],
        });
      }

      const type = (
        {
          "customer.subscription.created": "billing.subscription_created",
          "customer.subscription.updated": "billing.subscription_updated",
          "customer.subscription.deleted": "billing.subscription_deleted",
        } as const
      )[input.type];

      if (type === undefined) {
        if (accountId === undefined || customerId === undefined) {
          return ok(ignored);
        }

        const tenant = await tenantOf(accountId);

        if (!tenant.ok) {
          return tenant;
        }

        if (tenant.data !== undefined) {
          const linked = await link(tenant.data, customerId);

          if (!linked.ok) {
            return linked;
          }
        }

        return ok({ ...unlinked, organizationId: tenant.data });
      }

      if (customerId === undefined && accountId === undefined) {
        return ok(ignored);
      }

      const tenant =
        customerId === undefined ? ok(undefined) : await tenantOf(customerId);

      if (!tenant.ok) {
        return tenant;
      }

      let organizationId = tenant.data;

      if (organizationId === undefined && accountId !== undefined) {
        const byAccount = await tenantOf(accountId);

        if (!byAccount.ok) {
          return byAccount;
        }

        organizationId = byAccount.data;

        if (organizationId !== undefined && customerId !== undefined) {
          const linked = await link(organizationId, customerId);

          if (!linked.ok) {
            return linked;
          }
        }
      }

      const claimed = metadataTenant(object);

      if (organizationId === undefined && claimed !== undefined) {
        let matches = true;

        if (accountId !== undefined) {
          const linked = await linkAccount(claimed, accountId);

          if (!linked.ok) {
            return linked;
          }

          matches = linked.data === accountId;
        }

        if (matches && customerId !== undefined) {
          const linked = await link(claimed, customerId);

          if (!linked.ok) {
            return linked;
          }

          matches = linked.data === customerId;
        }

        if (matches) {
          organizationId = claimed;
        }
      }

      if (organizationId === undefined) {
        return ok(unlinked);
      }

      if (options.subscriptions === "webhook") {
        const stored = await call(
          "upsert_billing_subscription",
          subscriptionRecord(organizationId, object, input.created),
          (value) => value === true,
        );

        if (!stored.ok) {
          return stored;
        }
      }

      emit(type, {
        organizationId,
        ...(customerId === undefined ? {} : { customerId }),
        ...(accountId === undefined ? {} : { accountId }),
        subscriptionId: textOf(object["id"]),
        stripeEventId: input.id,
        ...(typeof object["status"] === "string"
          ? { status: object["status"] }
          : {}),
      });

      return ok({
        event: type,
        organizationId,
        customerId,
        accountId,
        invalidated: await invalidate(input),
      });
    });

  const checkoutBlock = (organizationId: string): AsyncResult<undefined> =>
    AsyncResult.from(async () => {
      const external = await options.external?.(organizationId);

      if (external !== undefined) {
        return checkoutBlockedError(`BILLING_EXTERNAL:${external}`);
      }

      if (options.subscriptions !== "webhook") {
        return ok(undefined);
      }

      const blocked = await call(
        "billing_checkout_block",
        { tenant: organizationId },
        optionalText,
      );

      if (!blocked.ok) {
        return blocked;
      }

      return blocked.data === undefined
        ? ok(undefined)
        : checkoutBlockedError(blocked.data);
    });

  const priceOf = (choice: {
    readonly price?: string;
    readonly plan?: string;
    readonly interval?: string;
    readonly variant?: string;
  }): AsyncResult<string> => {
    const given = choice.price;

    if (given !== undefined) {
      return AsyncResult.from<string>(() => Promise.resolve(ok(given)));
    }

    if (choice.plan === undefined) {
      return AsyncResult.from<string>(() =>
        Promise.resolve(
          err(
            dbError("invalid_input", "Pass a price or a plan", {
              hint: "BILLING_PRICE_REQUIRED",
            }),
          ),
        ),
      );
    }

    const plan = choice.plan;

    return call(
      "billing_plan_price",
      { plan, billing_interval: choice.interval, variant: choice.variant },
      optionalText,
    ).andThen((price) =>
      Promise.resolve(
        price === undefined
          ? err(
              dbError("not_found", `No price for plan "${plan}"`, {
                hint: "BILLING_PLAN_UNKNOWN",
              }),
            )
          : ok(price),
      ),
    );
  };

  const subscription = (
    organizationId: string,
  ): AsyncResult<SubscriptionItem> =>
    call(
      "billing_subscription_item",
      { tenant: organizationId },
      subscriptionItemOf,
    ).andThen((found) =>
      Promise.resolve(
        found === undefined
          ? err(
              dbError("not_found", "This tenant has no active subscription", {
                hint: "BILLING_NO_SUBSCRIPTION",
              }),
            )
          : ok(found),
      ),
    );

  const rows = (value: unknown): readonly StripeRow[] =>
    Array.isArray(value) ? value.filter(isRecord) : [];

  const tenantRows =
    (key: string) =>
    (value: unknown): readonly TenantStripeRow[] =>
      rows(value).flatMap((entry) => {
        const row = entry[key];

        return isRecord(row)
          ? [
              {
                organizationId: textOf(entry["tenant"]),
                customerId: textOf(entry["customer"]),
                row,
              },
            ]
          : [];
      });

  const platformArgs = (list: PlatformListOptions = {}) => ({
    for_status: list.status,
    max_rows: list.limit ?? 100,
    before_created: pageOf(list).cursor,
  });

  const invoices = ({
    organizationId,
    ...list
  }: { organizationId: string } & { readonly limit?: number }): AsyncResult<
    readonly StripeRow[]
  > =>
    call(
      "billing_invoices",
      { tenant: organizationId, max_rows: list.limit ?? 50 },
      rows,
    );

  const ownInvoice = (
    organizationId: string,
    invoiceId: string,
  ): AsyncResult<string> =>
    invoices({ organizationId, limit: 500 }).andThen((list) =>
      Promise.resolve(
        list.some((row) => row["id"] === invoiceId)
          ? ok(invoiceId)
          : err(
              dbError("not_found", "This tenant has no such invoice", {
                hint: "BILLING_INVOICE_NOT_FOUND",
              }),
            ),
      ),
    );

  const client: Billing = {
    customer,
    account,
    ensureCustomer,
    ensureAccount,
    changePlan: ({ organizationId, change }) =>
      priceOf(change).andThen((price) =>
        subscription(organizationId).andThen(async (found) => {
          const updated = await withStripe(async (client) =>
            client.subscriptions.update?.(
              found.subscriptionId,
              {
                items: [{ id: found.itemId, price }],
                proration_behavior:
                  change.prorationBehavior ?? "create_prorations",
                ...(change.resume === false
                  ? {}
                  : { cancel_at_period_end: false }),
              },
              change.idempotencyKey === undefined
                ? undefined
                : { idempotencyKey: change.idempotencyKey },
            ),
          );

          if (!updated.ok) {
            return updated;
          }

          if (updated.data === undefined) {
            return missing("subscriptions.update");
          }

          emit("billing.subscription_updated", {
            organizationId,
            subscriptionId: found.subscriptionId,
          });

          return ok({ ...found, price });
        }),
      ),
    cancelAtPeriodEnd: ({ organizationId, cancel }) =>
      subscription(organizationId).andThen(async (found) => {
        const updated = await withStripe(async (client) =>
          client.subscriptions.update?.(found.subscriptionId, {
            cancel_at_period_end: cancel,
          }),
        );

        if (!updated.ok) {
          return updated;
        }

        return updated.data === undefined
          ? missing("subscriptions.update")
          : ok(updated.data.id);
      }),
    invoices,
    paymentMethods: (organizationId) =>
      call("billing_payment_methods", { tenant: organizationId }, rows),
    voidInvoice: ({ organizationId, invoiceId }) =>
      ownInvoice(organizationId, invoiceId).andThen(async () => {
        const voided = await withStripe(async (client) =>
          client.invoices?.voidInvoice(invoiceId),
        );

        if (!voided.ok) {
          return voided;
        }

        return voided.data === undefined
          ? missing("invoices.voidInvoice")
          : ok(voided.data.id);
      }),
    markInvoiceUncollectible: ({ organizationId, invoiceId }) =>
      ownInvoice(organizationId, invoiceId).andThen(async () => {
        const marked = await withStripe(async (client) =>
          client.invoices?.markUncollectible(invoiceId),
        );

        if (!marked.ok) {
          return marked;
        }

        return marked.data === undefined
          ? missing("invoices.markUncollectible")
          : ok(marked.data.id);
      }),
    customerDetails: (organizationId) =>
      call("billing_customer_details", { tenant: organizationId }, (value) =>
        isRecord(value) ? value : undefined,
      ),
    taxIds: ({ organizationId, options: taxOptions = {} }) =>
      taxOptions.from === "sync"
        ? call("billing_tax_ids", { tenant: organizationId }, (value) =>
            Array.isArray(value) ? value.filter(isRecord).map(syncedTaxId) : [],
          )
        : customer(organizationId).andThen(async (customerId) => {
            if (customerId === undefined) {
              return ok([]);
            }

            const listed = await withStripe(async (client) =>
              client.customers.listTaxIds?.(customerId, { limit: 100 }),
            );

            if (!listed.ok) {
              return listed;
            }

            return listed.data === undefined
              ? missing("customers.listTaxIds")
              : ok(listed.data.data);
          }),
    addTaxId: ({ organizationId, taxId }) =>
      ensureCustomer({ organizationId }).andThen(async (customerId) => {
        const created = await withStripe(async (client) =>
          client.customers.createTaxId?.(customerId, {
            type: taxId.type,
            value: taxId.value,
          }),
        );

        if (!created.ok) {
          return created;
        }

        return created.data === undefined
          ? missing("customers.createTaxId")
          : ok(created.data);
      }),
    removeTaxId: ({ organizationId, taxId }) =>
      customer(organizationId).andThen(async (customerId) => {
        if (customerId === undefined) {
          return err(
            dbError("not_found", "This tenant has no Stripe customer yet", {
              hint: "BILLING_NO_CUSTOMER",
            }),
          );
        }

        const deleted = await withStripe(async (client) =>
          client.customers.deleteTaxId?.(customerId, taxId),
        );

        if (!deleted.ok) {
          return deleted;
        }

        return deleted.data === undefined
          ? missing("customers.deleteTaxId")
          : ok(deleted.data.id);
      }),
    updateCustomer: ({ organizationId, update }) =>
      ensureCustomer({ organizationId }).andThen(async (customerId) => {
        const updated = await withStripe(async (client) =>
          client.customers.update?.(customerId, {
            ...(update.email === undefined ? {} : { email: update.email }),
            ...(update.name === undefined ? {} : { name: update.name }),
            ...(update.phone === undefined ? {} : { phone: update.phone }),
            ...(update.address === undefined
              ? {}
              : { address: update.address }),
            ...update.params,
          }),
        );

        if (!updated.ok) {
          return updated;
        }

        return updated.data === undefined
          ? missing("customers.update")
          : ok(updated.data.id);
      }),
    checkout: ({ organizationId, options: checkout }) =>
      checkoutBlock(organizationId)
        .andThen(() => priceOf(checkout))
        .andThen((price) =>
          checkoutParty(organizationId, checkout).andThen(async (party) => {
            const quantity =
              checkout.quantity === "seats"
                ? await seats(organizationId)
                : ok(checkout.quantity ?? 1);

            if (!quantity.ok) {
              return quantity;
            }

            const lineItems = [{ price, quantity: quantity.data }];

            for (const extra of checkout.items ?? []) {
              const extraPrice = await priceOf(extra);

              if (!extraPrice.ok) {
                return extraPrice;
              }

              lineItems.push({
                price: extraPrice.data,
                quantity: extra.quantity ?? 1,
              });
            }

            const mode = checkout.mode ?? "subscription";

            return withStripe(async (client) => {
              const params = checkoutParams(
                {
                  mode,
                  client_reference_id: organizationId,
                  line_items: lineItems,
                  success_url: checkout.successUrl,
                  ...(checkout.cancelUrl === undefined
                    ? {}
                    : { cancel_url: checkout.cancelUrl }),
                },
                checkout.params,
                organizationId,
                party,
              );

              const session = await client.checkout.sessions.create(
                params,
                checkout.idempotencyKey === undefined
                  ? undefined
                  : { idempotencyKey: checkout.idempotencyKey },
              );

              return { id: session.id, url: session.url ?? undefined };
            });
          }),
        ),
    portal: ({ organizationId, options: portal }) =>
      partyOf(organizationId).andThen(async (party) => {
        if (party === undefined) {
          return err(
            dbError("not_found", "This tenant has no Stripe customer yet", {
              hint: "BILLING_NO_CUSTOMER",
            }),
          );
        }

        return withStripe(async (client) => {
          const session = await client.billingPortal.sessions.create({
            ...party,
            return_url: portal.returnUrl,
          });

          return { url: session.url };
        });
      }),
    status: (organizationId) =>
      call("billing_status", { tenant: organizationId }, (value) => {
        const row = recordOf(value, "billing_status");

        return {
          customerId: optionalText(row["customer"]),
          accountId: optionalText(row["account"]),
          seats: Number(row["seats"] ?? 0),
          subscription: subscriptionItemOf(row["subscription"]),
        };
      }),
    syncSeats,
    ...billingReads(call),
    subscription: (organizationId) =>
      call("billing_subscription", { tenant: organizationId }, (value) =>
        isRecord(value) ? value : undefined,
      ),
    allInvoices: (list) =>
      call("billing_all_invoices", platformArgs(list), tenantRows("invoice")),
    allCustomers: () =>
      call("billing_all_customers", {}, (value) =>
        (Array.isArray(value) ? value : [])
          .filter(isRecord)
          .map((row) => ({
            organizationId: textOf(row["tenant"]),
            customerId: textOf(row["customer"]),
            email: optionalText(row["email"]),
            name: optionalText(row["name"]),
            created: optionalInstant(row["created"]),
          })),
      ),
    allSubscriptions: (list) =>
      call(
        "billing_all_subscriptions",
        platformArgs(list),
        tenantRows("subscription"),
      ),
    cancelSubscription: (organizationId) =>
      item(organizationId).andThen(async (found) => {
        if (found === undefined) {
          return ok(undefined);
        }

        const cancelled = await withStripe((client) =>
          client.subscriptions.cancel(found.subscriptionId),
        );

        return cancelled.ok ? ok(cancelled.data.id) : cancelled;
      }),
    seatSink: () => ({
      async send(events) {
        const latest = new Map<string, string>();

        for (const event of events) {
          const tenant = optionalText(event["partitionkey"]);

          if (tenant !== undefined && SEAT_EVENT.test(event.type)) {
            latest.set(tenant, event.id);
          }
        }

        for (const [tenant, id] of latest) {
          await syncSeats({ organizationId: tenant, key: id }).orThrow();
        }
      },
    }),
    startTrial: ({ organizationId, options: trial }) => {
      const { days, ...checkout } = trial;

      const subscriptionData = {
        ...(isRecord(checkout.params?.["subscription_data"])
          ? checkout.params["subscription_data"]
          : {}),
        trial_period_days: days,
      };

      return hooked.checkout({
        organizationId,
        options: {
          ...checkout,
          mode: "subscription",
          params: { ...checkout.params, subscription_data: subscriptionData },
        },
      });
    },
    handleStripeEvent,
  };

  // Helpers call the hooked client, so app hooks see each step.
  const hooked: Billing = withBlockHooks(client, options.hooks, {
    block: "billing",
    ...(options.logger ? { logger: options.logger } : {}),
  });

  return hooked;
}
