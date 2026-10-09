import { Redirect } from "expo-router";

/** The magic-link and OAuth redirect target; `AppShell` finishes the sign-in from the URL. */
export default function AuthCallback() {
  return <Redirect href="/customers" />;
}
