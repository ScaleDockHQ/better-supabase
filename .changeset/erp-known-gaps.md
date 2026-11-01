---
"better-supabase": patch
---

Four gaps of the ERP import work are closed. A document with no legal entity and a document of the
default entity now share one number series, so they can't hold the same number
(`LEGAL_ENTITY_NUMBER_TAKEN`), and `set_default_legal_entity` refuses a switch that would create a
duplicate. `legalEntities.disableCheck()` lists the numbers that block turning a kind of
`options.on` off, and the restore raises `LEGAL_ENTITIES_DISABLE_COLLISION` instead of a unique
violation. `invoices.recomputeTotals()` repairs the stored totals of invoices issued before the
credit restriction, as a dry run by default, audit logged and without touching posted ledger
entries. `prepareIntrastat` derives arrival lines from purchase receipts that name a member state,
lets a manual line win, and the Intrastat functions join the `api` schema without an
`api.functions` entry. Receipt lines of `receivePurchaseOrder` accept `country` and `netMassKg`. The
new option `blocks.invoices.options.correctionEvents` sends `invoice.totals_corrected` to the
outbox. Run `better-supabase upgrade` and apply the new migration.
