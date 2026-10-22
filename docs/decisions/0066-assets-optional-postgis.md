# 0066: Store asset coordinates as numbers, with PostGIS as an option

- Status: accepted
- Date: 2026-10-22

## Context

The `assets` block keeps locations (sites, buildings, units) and assets, and
both have a position. Apps need two spatial questions answered: what is near
a point (the closest van, the rooms within 500 meters), and which locations
contain a point (the site a technician is standing on). PostGIS answers both
with indexes, but it is a large extension, it isn't enabled on every
Supabase project, and a block that requires it would make `better-supabase
add assets` fail where it isn't wanted. Every other block installs no
extension beyond `btree_gist` (ADR 0023).

## Decision

Locations and assets always store `latitude` and `longitude` as
`double precision`. Without PostGIS, `assets_near` filters by a bounding box
and orders by the haversine distance on those columns, and
`asset_locations_at` fails with `ASSETS_POSTGIS_REQUIRED`.

The `postgis` option (`blocks.assets.options.postgis`, off by default)
creates the `postgis` extension in the `extensions` schema and adds
`extensions.geography` columns: a `point` on locations and assets, generated
from the two numbers so they can't disagree, and an `area` multipolygon on
locations that the functions take as GeoJSON. Both get GiST indexes.
`assets_near` then uses `ST_DWithin`, and `asset_locations_at` uses
`ST_Covers`. The function signatures and results don't change with the
option, so the client is the same either way.

`sql sync` writes the extension into its own migration before the schema
migration, as it does for other extensions.

## Consequences

- Turning the option on later adds columns and indexes without moving data,
  because the generated `point` is computed from the existing numbers.
  Turning it off drops them, and the areas with them.
- Distances without PostGIS are spherical and exact enough for "near"; they
  scan the bounding box, so large registries should turn PostGIS on.
- The fixture turns the option on, so pgTAP and the integration tests cover
  the PostGIS path; the module's unit tests cover the plain one.
