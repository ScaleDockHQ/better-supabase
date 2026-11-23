# 1219: Staff orders carry back-office fields and a keyset list

- Status: accepted
- Date: 2026-11-23
- Extends: [0665](0665-staff-orders-take-draft-and-on-hold-states.md)

## Context

The scale report (BS-09) listed what a back office kept next to the orders
block because the block had no place for it: the sales channel, the id of an
order in the system it was imported from, how and when to invoice, a delivery
method, the quote an order came from, a discount on the whole order, a
deposit that must be paid before shipping, and the company or contact the
order is for. Lines needed a unit, a description, a type and the app's own
columns, and quantities of hours or kilograms needed decimals. Staff screens
listed orders through `order_status_board` or their own queries, with no
keyset page.

## Decision

The orders block moves to version 5.

- `orders` gains `channel`, `source`, `external_id`, `invoicing_policy`
  (`on_order` or `on_delivery`), `delivery_method`, `quote_id`,
  `order_discount`, `promotion_id`, `payment_required`, `deposit_amount`,
  `party_type` and `party_id`. `external_id` is unique per tenant and source,
  needs a source, and makes `order_from_lines` idempotent the way `origin`
  does. `quote_id` is a plain link, outside the quotes block's revision chain.
  The party pair references a contact or company without a foreign key, the
  way invoices reference a party.
- `order_lines` gains `unit`, `description` and `line_type` (`item`,
  `service` or `fee`), and the extra columns an app adds are written from
  `fields` and returned in `fields`.
- Quantities of order, fulfillment and return lines become
  `numeric(18, quantityScale)`. `quantityScale` defaults to 0, so existing
  values and checks stay whole numbers. Line money is the unit price times the
  quantity, rounded to a minor unit.
- `order_discount` comes off the net subtotal after the line discounts and is
  part of `discount_total`. `fromQuote` refuses it: a quote's totals are
  copied as they are.
- With `payment_required`, `create_fulfillment` refuses until `paid_total`
  covers the deposit, or the total without one (`ORDERS_PAYMENT_REQUIRED`).
- `page_orders` is the block's list read under the list contract of ADR 1077.

The plan named `page_orders(tenant, filter, after, limit)`. The list contract
gives every list function `(tenant, filters jsonb)`, with the cursor, limit,
sort, facet and count inside the object, so `page_orders` follows the
contract and the client reads it through `entityList` like every other block
list. It runs as the caller, so the select policy decides which orders
appear, and it is granted to `authenticated`. It needs no new permission key:
the orders read policy covers it, so `OPERATIONS`, scopes and default roles
are unchanged.

## Consequences

Breaking for an app that added a column of one of these names to `orders` or
`order_lines`, and for SQL of its own that reads a quantity as `integer`. The
0.84 to 0.85 guide lists both. A block over the app's own tables maps the new
columns or leaves them unmapped, and a call that sets an unmapped one fails
with `ORDERS_FIELD_UNSUPPORTED`. `supabase/tests/database/orders_staff_fields.test.sql`
covers the fields, the discount totals, idempotency, the payment gate, the
list filters and tenant isolation.
