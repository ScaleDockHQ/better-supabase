---
"better-supabase": minor
---

Add the `assets` block: a location hierarchy and an asset registry with assignment, coordinates and optional PostGIS.

- `better-supabase add assets` installs locations in a tree (site, building, unit) without cycles, and assets with a kind, a tag, a serial number, a status (`active`, `maintenance`, `retired`) and an assignment to a member or any record, with its history. `createAssets` from `better-supabase/blocks/assets` manages them, and `assetsSection` shows the assets a record holds on its page.
- `near` finds assets and locations within a radius. The `postgis` option adds geography points and location areas with GiST indexes, and `locationsAt` returns the locations whose area contains a point (ADR 0066).
- With bookings or work items installed, booking resources and work items get an `asset_id` that `link` sets.
- New permissions: `assets.read`, `assets.manage` and `assets.assign`.
