# 0127: Count stock in numeric units with lots, bins and allocations

- Status: accepted
- Date: 2026-10-28
- Amends: 0065, 0080, 0082, 0120

## Context

Inventory counted whole items: `stock_levels` and every stock function used
`integer`, so flour by the kilogram or cable by the metre needed a fake unit.
Stock had no lots, serial numbers, expiry dates or bins, and no cost, so a
food or pharmacy app couldn't trace a recall, pick first-expiry-first-out or
value its stock. Reservations hold stock for a cart; a work order or a phone
order had no way to hold stock and wait for a receipt. Orders came only from
carts, and a shipment (ADR 0082) carried packages but no stock, so shipping
didn't take anything out of inventory.

## Decision

Every stock quantity is `numeric(20, 6)`. `stock_items` gives a variant its
unit and scale (0 to 6 decimals), its tracking (`none`, `lot`, `serial`),
whether it tracks expiry, and its costing (`none`, `average`) in one currency.
A quantity with more decimals than the scale is refused
(`INVENTORY_QUANTITY_PRECISION`). The ledger (ADR 0065, 0080) keeps bigint
amounts: a movement posts base units, the quantity times ten to the scale, to
accounts whose code carries the unit and scale when they aren't `item` and 0.
`move_stock` takes a `detail` object with `binId`, `lotId` or `lot` (`code`,
`expiresOn`), `serials` and, for a receipt, `unitCost` and `currency`.

Stock per bin and lot lives in `stock_buckets`; stock outside any bucket is
on hand minus the buckets, so existing levels need no backfill. Without a bin
or lot, stock leaves first-expiry-first-out, and a sale or a transfer out skips
hold bins and expired lots. `held` on the level counts stock in hold bins, and
`available` is on hand minus reserved minus held. Under average costing a
receipt moves the stock's value into the variant's value account and resets
`average_cost`; a sale moves it out to cost of goods sold. `stock_valuation`,
`stock_detail`, `expiring_lots` and `expire_lots` read and age it.

`stock_allocations` hold stock for a document (`document_type`,
`document_id`, `line_id`). An allocation takes what is available and, with
`backorder`, waits for the rest; every movement that adds stock fills open
backorders oldest first. `fulfill_allocation` ships from it and `restore_allocation` puts a
shipped part back.

`order_from_lines` and `order_from_quote` make a `confirmed` order, once per
`origin` (`type`, `id`) or quote, and allocate each shipped line. Order line
quantities stay whole: `order_from_quote` refuses a quote with a fractional
line (`ORDERS_QUANTITY_INVALID`) and fails `ORDERS_QUOTES_MISSING` without the
quotes block. Cancelling the order releases its allocations. An accepted quote
(ADR 0120) orders through `orderFromQuoteAction` without a `create`.

`shipment_lines` carry a shipment's stock. The label takes each outbound line
out, through its allocation or as a sale, and records the lots it came from;
cancelling the shipment puts them back. `receive_shipment_return` records
return lines with a `restock`, `hold` (into a hold bin) or `scrap` disposition,
at most what the shipment carried out. Every new table is adoptable (ADR 0098)
and carries `bsb_tenant_scope` (ADR 0099).

## Alternatives considered

A separate decimal ledger lost: the ledger's bigint amounts and its balance
checks would have to be duplicated, and base units keep them exact. FIFO cost
layers lost to the weighted average for now: they need a layer per receipt and
a consumption record per sale, and the average covers the common case of one
cost per variant. Fractional order lines lost: orders, refunds and taxes count
per whole line, and changing that is its own decision.

## Consequences

An app that declared `before_stock_adjust` or `before_stock_reserve` with an
`integer` quantity must declare it `numeric`. Code that switches over the
order status must handle `confirmed`. Stock functions return quantities as
numeric text in their JSON; the TypeScript clients read them as numbers,
except average costs and shipment line quantities, which stay strings. A shipments
install without inventory refuses lines (`SHIPMENT_INVENTORY_MISSING`).
