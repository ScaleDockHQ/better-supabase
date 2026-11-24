import { Client } from "pg";

/**
 * The table a dynamic route reads, for the pages no list links to with a plain
 * anchor (rows that open through a click handler, boards, cards). The first
 * row of the Acme organization gives the URL.
 */
const TABLE_OF_ROUTE: Readonly<Record<string, string>> = {
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
  "/incidents/[id]": "incidents",
  "/settings/option-sets/[id]": "option_sets",
  "/forms/[id]": "forms",
  "/maintenance/meters/[id]": "maintenance_meters",
  "/finance/periods/[id]": "accounting_periods",
  "/courses/[courseId]": "courses",
  "/workflows/builder/[definition]": "workflow_definitions",
};

/** The URL of the first Acme row behind `route`, or undefined when none exists. */
export async function seededUrl(route: string): Promise<string | undefined> {
  const table = TABLE_OF_ROUTE[route];
  const connectionString = process.env["SUPABASE_DB_URL"];

  if (table === undefined || connectionString === undefined) {
    return undefined;
  }

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
