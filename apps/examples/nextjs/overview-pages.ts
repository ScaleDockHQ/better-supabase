import { defineEntityPage } from "better-supabase/list";

/**
 * The hand-written `BlockOverview` pages (EX-607, EX-1265, EX-1267). Each page
 * still renders its own `BlockOverview`; declaring it here makes `gen` write
 * the scale plan check, the indexes and the coverage entry for it. The rows are
 * the ones `example.sql` and the demo seed already create, so no page declares
 * `seed`.
 */
export const overviewPages = [
  defineEntityPage({
    entity: "contacts.person",
    route: "/crm/contacts",
    name: "contacts",
    reads: "$blocks.contacts",
    methods: { page: "personPage", facets: "personFacets" },
    tenantOption: "organizationId",
  }),
  defineEntityPage({
    entity: "contacts.company",
    route: "/crm/companies",
    name: "companies",
    reads: "$blocks.contacts",
    methods: { page: "companyPage", facets: "companyFacets" },
    tenantOption: "organizationId",
  }),
  defineEntityPage({
    entity: "forecasts.forecast_snapshot",
    route: "/crm/forecasts",
    name: "forecasts",
    tenantOption: "organizationId",
  }),
  defineEntityPage({
    entity: "quotes.quote",
    route: "/crm/quotes",
    name: "quotes",
    reads: "$blocks.quotes",
    tenantOption: "organizationId",
  }),
  defineEntityPage({
    entity: "sequences.sequence",
    route: "/crm/sequences",
    name: "sequences",
    methods: { page: "sequencePage", facets: "sequenceFacets" },
  }),
  defineEntityPage({
    entity: "commissions.commission_plan",
    route: "/crm/commissions",
    name: "commission-plans",
    methods: { page: "planPage", facets: "planFacets" },
  }),
  defineEntityPage({
    entity: "commissions.commission_statement",
    route: "/crm/commissions",
    name: "commission-statements",
    methods: { page: "statementPage", facets: "statementFacets" },
  }),
  defineEntityPage({
    entity: "referrals.referral_code",
    route: "/crm/referrals",
    name: "referral-codes",
    methods: { page: "codePage", facets: "codeFacets" },
  }),
  defineEntityPage({
    entity: "rfqs.rfq",
    route: "/rfqs",
    name: "rfqs",
    methods: { page: "rfqPage", facets: "rfqFacets" },
  }),
  defineEntityPage({
    entity: "tills.till",
    route: "/tills",
    name: "tills",
    methods: { page: "tillPage", facets: "tillFacets" },
  }),
  defineEntityPage({
    entity: "tills.till_session",
    route: "/tills",
    name: "till-sessions",
    methods: { page: "sessionPage", facets: "sessionFacets" },
  }),
  defineEntityPage({
    entity: "warehouse.pick_list",
    route: "/warehouse",
    name: "pick-lists",
    methods: { page: "pickListPage", facets: "pickListFacets" },
  }),
  defineEntityPage({
    entity: "warehouse.pick_wave",
    route: "/warehouse",
    name: "pick-waves",
    methods: { page: "pickWavePage", facets: "pickWaveFacets" },
  }),
  defineEntityPage({
    entity: "warehouse.putaway_rule",
    route: "/warehouse",
    name: "putaway-rules",
    methods: { page: "putawayRulePage", facets: "putawayRuleFacets" },
  }),
  defineEntityPage({
    entity: "warehouse.count_plan",
    route: "/warehouse",
    name: "count-plans",
    methods: { page: "countPlanPage", facets: "countPlanFacets" },
  }),
  defineEntityPage({
    entity: "lims.lims_sample",
    route: "/lims",
    name: "lims-samples",
    methods: { page: "samplePage", facets: "sampleFacets" },
  }),
  defineEntityPage({
    entity: "lims.lims_method",
    route: "/lims",
    name: "lims-methods",
    methods: { page: "methodPage", facets: "methodFacets" },
  }),
  defineEntityPage({
    entity: "maintenance.maintenance_plan",
    route: "/maintenance",
    name: "maintenance-plans",
    methods: { page: "planPage", facets: "planFacets" },
  }),
  defineEntityPage({
    entity: "maintenance.maintenance_meter",
    route: "/maintenance",
    name: "maintenance-meters",
    methods: { page: "meterPage", facets: "meterFacets" },
  }),
  defineEntityPage({
    entity: "maintenance.maintenance_calibration",
    route: "/maintenance",
    name: "maintenance-calibrations",
    methods: { page: "calibrationPage", facets: "calibrationFacets" },
  }),
] as const;
