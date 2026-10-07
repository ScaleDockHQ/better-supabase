import { DeleteAccountCard } from "@/features/user/components/delete-account-button";
import { TwoFactorCard } from "@/features/user/components/two-factor-card";

export const instant = true;

/** All in the browser: Supabase Auth MFA needs no server render. */
export default function SecuritySettingsPage() {
  return (
    <>
      <TwoFactorCard />
      <DeleteAccountCard />
    </>
  );
}
