"use client";

import type { Session } from "@supabase/supabase-js";
import type { ReactNode, SubmitEvent } from "react";

import { useEveAgent } from "eve/react";
import { useEffect, useState } from "react";

import { browserClient } from "@/lib/supabase";

async function authorization(): Promise<Record<string, string>> {
  const { data } = await browserClient().auth.getSession();
  return data.session
    ? { authorization: `Bearer ${data.session.access_token}` }
    : {};
}

function Chat(): ReactNode {
  const agent = useEveAgent({ headers: authorization });
  const busy = agent.status === "submitted" || agent.status === "streaming";
  const resuming = agent.status === "resuming";

  const onSubmit = (event: SubmitEvent<HTMLFormElement>): void => {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const message = String(form.get("message") ?? "").trim();
    if (message.length === 0 || resuming) return;
    void agent.send(message, busy ? { turnPolicy: "steer" } : undefined);
    event.currentTarget.reset();
  };

  return (
    <form onSubmit={onSubmit}>
      {agent.data.messages.map((message) => (
        <article key={message.id}>
          <strong>{message.role}</strong>
          {message.parts.map((part, index) =>
            part.type === "text" ? (
              <p key={part.id ?? index}>{part.text}</p>
            ) : null,
          )}
        </article>
      ))}
      <input aria-label="Message" disabled={resuming} name="message" />
      <button disabled={resuming} type="submit">
        Send
      </button>
    </form>
  );
}

function SignIn(): ReactNode {
  const [error, setError] = useState<string>();

  const onSubmit = async (
    event: SubmitEvent<HTMLFormElement>,
  ): Promise<void> => {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const result = await browserClient().auth.signInWithPassword({
      email: String(form.get("email") ?? ""),
      password: String(form.get("password") ?? ""),
    });
    setError(result.error?.message);
  };

  return (
    <form
      onSubmit={(event) => {
        void onSubmit(event);
      }}
    >
      <input
        aria-label="Email"
        defaultValue="member@acme.test"
        name="email"
        type="email"
      />
      <input
        aria-label="Password"
        defaultValue="password123"
        name="password"
        type="password"
      />
      <button type="submit">Sign in</button>
      {error === undefined ? null : <p role="alert">{error}</p>}
    </form>
  );
}

export function Assistant(): ReactNode {
  const [session, setSession] = useState<Session | null>(null);

  useEffect(() => {
    const auth = browserClient().auth;
    void auth.getSession().then(({ data }) => {
      setSession(data.session);
    });
    const { data } = auth.onAuthStateChange((_event, next) => {
      setSession(next);
    });
    return () => {
      data.subscription.unsubscribe();
    };
  }, []);

  return session ? <Chat key={session.user.id} /> : <SignIn />;
}
