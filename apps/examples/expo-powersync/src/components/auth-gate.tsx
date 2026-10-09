import type { ReactNode } from "react";

import { useAuth } from "better-supabase/react";
import { ActivityIndicator } from "react-native";

import { usePushRegistration } from "../lib/push";
import { SignInScreen } from "./sign-in-screen";

/** Shows the sign-in screen until a session exists, then the app. */
export function AuthGate({ children }: { readonly children: ReactNode }) {
  const auth = useAuth();
  switch (auth.status) {
    case "loading":
      return <ActivityIndicator style={{ flex: 1 }} />;
    case "signed-out":
      return <SignInScreen />;
    case "signed-in":
      return <SignedIn>{children}</SignedIn>;
    default: {
      const unhandled: never = auth;
      throw new TypeError(`Unhandled auth state ${JSON.stringify(unhandled)}`);
    }
  }
}

function SignedIn({ children }: { readonly children: ReactNode }) {
  usePushRegistration();
  return children;
}
