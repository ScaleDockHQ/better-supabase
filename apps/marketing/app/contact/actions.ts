"use server";

import * as v from "valibot";

import { env } from "@/env";
import { site } from "@/lib/site";

export interface ContactState {
  readonly status: "idle" | "sent" | "error";
  readonly message?: string;
  readonly values: { name: string; email: string; message: string };
}

const ContactSchema = v.object({
  name: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(120)),
  email: v.pipe(v.string(), v.trim(), v.email(), v.maxLength(200)),
  message: v.pipe(v.string(), v.trim(), v.minLength(10), v.maxLength(5000)),
  // Hidden field: real people leave it empty.
  company: v.optional(v.literal("")),
});

function field(data: FormData, key: string): string {
  return String(data.get(key) ?? "");
}

// oxlint-disable-next-line react-doctor/server-auth-actions -- a public contact form: visitors are anonymous, and the honeypot and schema limit abuse
export async function sendContact(
  _previous: ContactState,
  data: FormData,
): Promise<ContactState> {
  const values = {
    name: field(data, "name"),
    email: field(data, "email"),
    message: field(data, "message"),
  };

  const parsed = v.safeParse(ContactSchema, {
    ...values,
    company: field(data, "company"),
  });

  if (!parsed.success) {
    return {
      status: "error",
      message:
        "Check your name, a valid email and a message of 10+ characters.",
      values,
    };
  }

  if (!env.RESEND_API_KEY) {
    return {
      status: "error",
      message: `The form is not configured yet. Email ${site.contactEmail} instead.`,
      values,
    };
  }

  const { name, email, message } = parsed.output;

  try {
    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: env.CONTACT_FROM_EMAIL,
        to: [site.contactEmail],
        reply_to: email,
        subject: `Contact from ${name}`,
        text: `From: ${name} <${email}>\n\n${message}`,
      }),
    });

    if (!response.ok) {
      return {
        status: "error",
        message: `We could not send your message. Email ${site.contactEmail} instead.`,
        values,
      };
    }
  } catch {
    return {
      status: "error",
      message: `We could not send your message. Email ${site.contactEmail} instead.`,
      values,
    };
  }

  return {
    status: "sent",
    message: "Thanks, your message is on its way. We reply by email.",
    values: { name: "", email: "", message: "" },
  };
}
