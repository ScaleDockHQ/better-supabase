import { getIntegrations } from "../integration-queries";
import { IntegrationSettings } from "./integration-settings";

/** Render inside `<Suspense>`; the fallback is `IntegrationSettingsSkeleton`. */
export async function IntegrationSection() {
  const read = await getIntegrations();

  return <IntegrationSettings read={read} />;
}
