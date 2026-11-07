import { getIntegrations } from "../integrations-queries";
import { IntegrationSettings } from "./integration-settings";

// skeleton: the page passes the wrapped component's own skeleton to <Suspense>
/** Render inside `<Suspense>`; the fallback is `IntegrationSettingsSkeleton`. */
export async function IntegrationSection() {
  const read = await getIntegrations();

  return <IntegrationSettings read={read} />;
}
