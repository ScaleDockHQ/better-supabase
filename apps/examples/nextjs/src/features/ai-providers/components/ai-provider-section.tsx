import { getProviderKeys } from "../ai-provider-queries";
import { AiProviderSettings } from "./ai-provider-settings";

/** Render inside `<Suspense>`; the fallback is `AiProviderSettingsSkeleton`. */
export async function AiProviderSection() {
  const read = await getProviderKeys();

  return <AiProviderSettings read={read} />;
}
