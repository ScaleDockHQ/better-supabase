import { signInWithOAuthBrowser } from "better-supabase/client/native";
import { useSignIn } from "better-supabase/react";
import * as Linking from "expo-linking";
import * as WebBrowser from "expo-web-browser";
import { useState } from "react";
import { Button, Text, TextInput, View } from "react-native";

import { supabase } from "../lib/supabase/native";

const redirectTo = Linking.createURL("auth/callback");

/** Magic link or GitHub. Add `redirectTo` to the Auth redirect allow list. */
export function SignInScreen() {
  const signIn = useSignIn();
  const [email, setEmail] = useState("");
  const [sent, setSent] = useState(false);
  const [oauthError, setOauthError] = useState<string>();

  const sendLink = async () => {
    const failure = await signIn.otp({
      email,
      options: { emailRedirectTo: redirectTo },
    });
    setSent(failure === undefined);
  };

  const github = async () => {
    const result = await signInWithOAuthBrowser(
      supabase,
      WebBrowser,
      "github",
      {
        redirectTo,
      },
    );
    setOauthError(result.type === "error" ? result.error.message : undefined);
  };

  return (
    <View style={{ flex: 1, justifyContent: "center", padding: 24, gap: 12 }}>
      <TextInput
        value={email}
        onChangeText={setEmail}
        placeholder="you@example.com"
        autoCapitalize="none"
        autoComplete="email"
        keyboardType="email-address"
      />
      <Button
        title={sent ? "Check your email" : "Email me a sign-in link"}
        disabled={signIn.pending || email.length === 0}
        onPress={() => void sendLink()}
      />
      <Button
        title="Continue with GitHub"
        disabled={signIn.pending}
        onPress={() => void github()}
      />
      {signIn.error || oauthError ? (
        <Text>{signIn.error?.message ?? oauthError}</Text>
      ) : null}
    </View>
  );
}
