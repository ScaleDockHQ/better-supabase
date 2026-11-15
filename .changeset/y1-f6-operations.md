---
"better-supabase": minor
---

The operations blocks follow the block list contract (ADR 1077). `tills`,
`lims`, `maintenance`, `warehouse` and `manufacturing` gain `page`, `facets`,
`count` and `get` methods for tills, lims methods, maintenance meters, pick
waves, count plans, putaway rules, bills of materials and work centers, and
`rfqs`, `shipments`, `lims`, `maintenance` and `manufacturing` accept `q` on
their existing lists. The array methods stay as deprecated aliases until 0.70.

| Deprecated                | Use                                                      |
| ------------------------- | -------------------------------------------------------- |
| `listTills`               | `tillPage`, `tillFacets`, `tillCount`, `getTill`         |
| `lims.listMethods`        | `methodPage`, `methodFacets`, `methodCount`, `getMethod` |
| `maintenance.listMeters`  | `meterPage`, `meterFacets`, `meterCount`, `getMeter`     |
| `listPickWaves`           | `pickWavePage` and `getPickWave`                         |
| `listCountPlans`          | `countPlanPage` and `getCountPlan`                       |
| `listPutawayRules`        | `putawayRulePage` and `getPutawayRule`                   |
| `listBoms`, `workCenters` | `bomPage`, `workCenterPage` and `getWorkCenter`          |

New SQL functions are `page_lims_methods`, `get_lims_method`,
`page_maintenance_meters`, `get_maintenance_meter`, `page_pick_waves`,
`get_pick_wave`, `page_count_plans`, `get_count_plan`, `get_putaway_rule`,
`page_boms`, `page_work_centers`, `get_work_center` and `get_till`.
`list_tills` and `list_putaway_rules` return a page when `paged` is true and
the array otherwise. Run `better-supabase upgrade` and apply the migration.
