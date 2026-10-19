"use client";

import { useActionState } from "react";

import { sendContact, type ContactState } from "@/app/contact/actions";
import { Alert, AlertDescription } from "@/components/reui/alert";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

const initial: ContactState = {
  status: "idle",
  values: { name: "", email: "", message: "" },
};

export function ContactForm() {
  const [state, action, pending] = useActionState(sendContact, initial);

  return (
    <form action={action} className="flex flex-col gap-4">
      <div className="flex flex-col gap-2">
        <Label htmlFor="contact-name">Name</Label>
        <Input
          id="contact-name"
          name="name"
          autoComplete="name"
          required
          maxLength={120}
          defaultValue={state.values.name}
          key={`name-${state.status}`}
        />
      </div>
      <div className="flex flex-col gap-2">
        <Label htmlFor="contact-email">Email</Label>
        <Input
          id="contact-email"
          name="email"
          type="email"
          autoComplete="email"
          required
          maxLength={200}
          defaultValue={state.values.email}
          key={`email-${state.status}`}
        />
      </div>
      <div className="flex flex-col gap-2">
        <Label htmlFor="contact-message">Message</Label>
        <textarea
          id="contact-message"
          name="message"
          required
          minLength={10}
          maxLength={5000}
          rows={6}
          defaultValue={state.values.message}
          key={`message-${state.status}`}
          className="min-h-32 w-full rounded-md border border-input bg-transparent px-2.5 py-2 text-sm shadow-xs transition-colors outline-none placeholder:text-muted-foreground focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 dark:bg-input/30"
        />
      </div>
      <div aria-hidden="true" className="hidden">
        <label>
          Company
          <input name="company" tabIndex={-1} autoComplete="off" />
        </label>
      </div>
      {state.message ? (
        <Alert variant={state.status === "sent" ? "success" : "destructive"}>
          <AlertDescription>{state.message}</AlertDescription>
        </Alert>
      ) : null}
      <Button type="submit" size="lg" disabled={pending} className="self-start">
        {pending ? "Sending" : "Send message"}
      </Button>
    </form>
  );
}
