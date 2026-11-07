import { getProviderKeys } from "../ai-providers-queries";
import { AiProviderSettings } from "./ai-provider-settings";

// skeleton: the page passes the wrapped component's own skeleton to <Suspense>
/** Render inside `<Suspense>`; the fallback is `AiProviderSettingsSkeleton`. */
export async function AiProviderSection() {
  const read = await getProviderKeys();

  return <AiProviderSettings read={read} />;
}
