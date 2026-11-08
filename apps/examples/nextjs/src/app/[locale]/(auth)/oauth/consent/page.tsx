import { DataProviders } from "@/app/data-providers";
import { OAuthConsentForm } from "@/features/auth/components/oauth-consent-form";

export default function OAuthConsentPage() {
  return (
    <DataProviders>
      <OAuthConsentForm />
    </DataProviders>
  );
}
