import { Client } from "pg";

/**
 * The table a dynamic route reads, for the pages no list links to with a plain
 * anchor (rows that open through a click handler, boards, cards). The first row
 * of the Acme organization gives the URL.
 */
const TABLE_OF_ROUTE = {
  "/crm/deals/[id]": "deals",
  "/crm/quotes/[id]": "quotes",
  "/crm/pipelines/[id]": "pipelines",
  "/crm/forecasts/[id]": "forecast_snapshots",
  "/crm/segments/[id]": "segments",
  "/crm/queues/[id]": "assignment_queues",
  "/crm/scoring/[id]": "score_models",
  "/crm/contracts/[id]": "contracts",
  "/crm/commissions/statements/[id]": "commission_statements",
  "/crm/sequences/[id]": "sequences",
  "/shop/orders/[id]": "orders",
  "/shop/donations/[id]": "donations",
  "/shop/warranty/[id]": "warranty_claims",
  "/shop/reviews/[id]": "reviews",
  "/shop/collections/[id]": "product_collections",
  "/shop/checkout-sessions/[id]": "checkout_sessions",
  "/shop/passes/[id]": "passes",
  "/warehouse/counts/[id]": "stock_counts",
  "/warehouse/rules/[id]": "putaway_rules",
  "/warehouse/waves/[id]": "pick_waves",
  "/property/leases/[id]": "leases",
  "/risks/[id]": "risks",
  "/content/[id]": "content_entries",
  "/advisories/vulnerabilities/[id]": "vulnerabilities",
  "/care-plans/[id]": "care_plans",
  "/prescriptions/[id]": "prescriptions",
  "/incidents/[id]": "incidents",
  "/deadlines/[id]": "deadlines",
  "/meetings/[id]": "meetings",
  "/settings/option-sets/[id]": "option_sets",
  "/forms/[id]": "forms",
  "/maintenance/meters/[id]": "maintenance_meters",
  "/finance/periods/[id]": "periods",
  "/courses/[courseId]": "courses",
  "/workflows/builder/[definition]": "workflow_definitions",
  // Service and logistics
  "/field/dispatch/[id]": "work_orders",
  "/field/shipments/[id]": "shipments",
  "/cases/[id]": "cases",
  // People
  "/people/[id]": "employees",
  "/people/hiring/[id]": "applications",
} as const satisfies Readonly<Record<string, string>>;

const isKnownRoute = (route: string): route is keyof typeof TABLE_OF_ROUTE =>
  route in TABLE_OF_ROUTE;

/** The URL of the first Acme row behind `route`, or undefined when none exists. */
export async function seededUrl(route: string): Promise<string | undefined> {
  const { SUPABASE_DB_URL: connectionString } = process.env;

  if (!isKnownRoute(route) || connectionString === undefined) {
    return undefined;
  }

  const table = TABLE_OF_ROUTE[route];

  const client = new Client({ connectionString });
  await client.connect();

  try {
    const result = await client.query<{ id: string }>(
      `select id::text from better_supabase.${table} order by 1 limit 1`,
    );

    const id = result.rows[0]?.id;

    return id === undefined ? undefined : route.replace(/\[[^\]]+\]/, id);
  } catch {
    return undefined;
  } finally {
    await client.end();
  }
}

/** The id of the first row of `table` (a seeded table name), or undefined. */
export async function firstRowId(table: string): Promise<string | undefined> {
  const { SUPABASE_DB_URL: connectionString } = process.env;

  if (connectionString === undefined || !/^[a-z_]+$/u.test(table)) {
    return undefined;
  }

  const client = new Client({ connectionString });
  await client.connect();

  try {
    const result = await client.query<{ id: string }>(
      `select id::text from better_supabase.${table} order by 1 limit 1`,
    );

    return result.rows[0]?.id;
  } catch {
    return undefined;
  } finally {
    await client.end();
  }
}
