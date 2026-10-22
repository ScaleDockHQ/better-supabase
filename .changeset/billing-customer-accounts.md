---
"better-supabase": minor
---

The `billing` block can bill tenants as Stripe Accounts v2 accounts with the `customer` configuration, and the module stores the account next to the customer.

- `createBilling({ customerAccounts })` creates or reuses the tenant's `v2.core.account` (`resolve` returns an existing one, `params` adds `v2.core.accounts.create` parameters) and passes `customer_account` to Checkout and the customer portal. A tenant that already has a v1 customer keeps it. `account(organizationId)` and `ensureAccount(organizationId, details)` are new, and `ensureCustomer` fails with `BILLING_CUSTOMER_PENDING` for an account until Stripe creates its customer.
- `handleStripeEvent` resolves a tenant by its customer or its account, and records the `cus_` id Stripe creates for the account from the first Checkout session, subscription or other event that carries both ids. Outcomes, `billing.*` block events and `BillingStatus` report `accountId`, and the new `billing.account_linked` event is recorded when an account is linked.
- `connectEvents: "ignore"` makes `handleStripeEvent` skip Connect events (`event.account`), for an endpoint that receives platform and connected account events together. The default still handles them.
- The `billing` SQL module is at version 3: `billing_customers` has a nullable `stripe_customer_account_id` (`^acct_`), `stripe_customer_id` is nullable, and a row needs one of the two. `link_billing_account(tenant, account)` and `billing_account(tenant)` are new, `link_billing_customer` records the customer on a row that has only an account, `billing_customer_tenant` matches either id, and `billing_status` returns `account`. Run `better-supabase sql upgrade` and generate a migration.
- `StripeClient` takes an optional `v2.core.accounts`, and the portal session accepts `customer_account`.
- `stripeInboxVerify` and `verifyStripeWebhook` are now tested with Connect events and with the thin event notifications of event destinations, which Stripe signs the same way.
