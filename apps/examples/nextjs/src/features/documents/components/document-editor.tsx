// #region recipe:document-editor
"use client";

import type { DocumentProviderStatus } from "better-supabase/yjs";

import { rpcTransport } from "better-supabase/blocks";
import { createDocuments } from "better-supabase/blocks/documents";
import { createDocumentProvider } from "better-supabase/yjs";
import { TriangleAlertIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useEffect, useId, useRef, useState } from "react";
import * as Y from "yjs";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Field, FieldDescription, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Textarea } from "@/components/ui/textarea";
import { useSupabase } from "@/lib/hooks";
import { blockConfig } from "@/lib/supabase/blocks.generated";

const DOCUMENT_NAME = "notes";
const LOCAL = Symbol("local edit");

/**
 * Replaces the text with `next` by deleting and inserting only the changed
 * middle, so an edit merges with another editor's edit elsewhere in it.
 */
function replaceText(text: Y.Text, next: string) {
  const current = text.toString();

  if (current === next) {
    return;
  }

  let start = 0;

  while (
    start < current.length &&
    start < next.length &&
    current[start] === next[start]
  ) {
    start += 1;
  }

  let end = 0;

  while (
    end < current.length - start &&
    end < next.length - start &&
    current[current.length - 1 - end] === next[next.length - 1 - end]
  ) {
    end += 1;
  }

  text.doc?.transact(() => {
    text.delete(start, current.length - start - end);
    text.insert(start, next.slice(start, next.length - end));
  }, LOCAL);
}

interface Editing {
  readonly title: Y.Text;
  readonly body: Y.Text;
}

interface DocumentTarget {
  readonly organizationId: string;
  readonly customerId: string;
  readonly customerName: string;
  readonly canWrite: boolean;
}

/**
 * The customer's notes as a Yjs document: a title and a body. Edits are stored
 * as updates through the documents block and reach the other editors over the
 * document's realtime topic.
 */
export function DocumentEditor(target: DocumentTarget) {
  const [attempt, setAttempt] = useState(0);

  return (
    <DocumentSession
      key={attempt}
      {...target}
      onRetry={() => {
        setAttempt((current) => current + 1);
      }}
    />
  );
}

/** One connection to the document; Retry remounts it with fresh state. */
function DocumentSession({
  organizationId,
  customerId,
  customerName,
  canWrite,
  onRetry,
}: DocumentTarget & { readonly onRetry: () => void }) {
  const t = useExtracted("documents");
  const fieldId = useId();
  const supabase = useSupabase();
  const editing = useRef<Editing | null>(null);
  const [status, setStatus] = useState<DocumentProviderStatus>("connecting");
  const [failed, setFailed] = useState(false);
  const [writable, setWritable] = useState(false);
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");

  useEffect(() => {
    const doc = new Y.Doc();
    const texts = { title: doc.getText("title"), body: doc.getText("body") };

    const sync = () => {
      setTitle(texts.title.toString());
      setBody(texts.body.toString());
    };

    const provider = createDocumentProvider({
      documents: createDocuments({
        transport: rpcTransport(supabase),
        schema: blockConfig.documents.api,
      }),
      client: supabase,
      doc,
      yjs: Y,
      ref: {
        organizationId,
        subjectType: "customer",
        subjectId: customerId,
        name: DOCUMENT_NAME,
      },
      onStatus: setStatus,
    });

    texts.title.observe(sync);
    texts.body.observe(sync);
    editing.current = texts;

    void provider.connect().then((opened) => {
      if (opened.ok) {
        setWritable(opened.data.canWrite);
        sync();
      } else {
        setFailed(true);
      }
    });

    return () => {
      texts.title.unobserve(sync);
      texts.body.unobserve(sync);
      editing.current = null;
      void provider.destroy();
      doc.destroy();
    };
  }, [supabase, organizationId, customerId]);

  const statusLabels: Record<DocumentProviderStatus, string> = {
    connecting: t("Connecting"),
    synced: t("Saved"),
    offline: t("Offline"),
    closed: t("Closed"),
  };

  const readOnly = !canWrite || !writable;

  if (failed) {
    return (
      <Alert variant="destructive" data-recipe="document-editor">
        <TriangleAlertIcon />
        <AlertTitle>{t("The document didn't open")}</AlertTitle>
        <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
        <AlertAction>
          <Button size="sm" variant="outline" onClick={onRetry}>
            {t("Retry")}
          </Button>
        </AlertAction>
      </Alert>
    );
  }

  return (
    <Card data-recipe="document-editor">
      <CardHeader>
        <div className="flex items-center justify-between gap-2">
          <CardTitle>{t("Notes for {name}", { name: customerName })}</CardTitle>
          <Badge variant={statusVariant(status)}>{statusLabels[status]}</Badge>
        </div>
        <CardDescription>
          {readOnly
            ? t("You can read this document. Ask an admin for edit access.")
            : t("Changes save as you type and show up for everyone editing.")}
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        {status === "connecting" && title === "" && body === "" ? (
          <div className="flex flex-col gap-4" aria-busy="true">
            <Skeleton className="h-9 w-full" />
            <Skeleton className="h-64 w-full" />
          </div>
        ) : (
          <>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-title`}>{t("Title")}</FieldLabel>
              <Input
                id={`${fieldId}-title`}
                value={title}
                readOnly={readOnly}
                maxLength={200}
                placeholder={t("Untitled")}
                onChange={(event) => {
                  setTitle(event.target.value);

                  if (editing.current) {
                    replaceText(editing.current.title, event.target.value);
                  }
                }}
              />
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-body`}>{t("Body")}</FieldLabel>
              <Textarea
                id={`${fieldId}-body`}
                value={body}
                readOnly={readOnly}
                rows={16}
                placeholder={t("Write the notes here.")}
                onChange={(event) => {
                  setBody(event.target.value);

                  if (editing.current) {
                    replaceText(editing.current.body, event.target.value);
                  }
                }}
              />
              <FieldDescription>
                {t(
                  "Plain text. Everyone who can read the customer can read it.",
                )}
              </FieldDescription>
            </Field>
          </>
        )}
      </CardContent>
    </Card>
  );
}

function statusVariant(
  status: DocumentProviderStatus,
): "success-light" | "warning-light" | "secondary" | "info-light" {
  switch (status) {
    case "synced": {
      return "success-light";
    }

    case "offline": {
      return "warning-light";
    }

    case "connecting": {
      return "info-light";
    }

    case "closed": {
      return "secondary";
    }

    default: {
      const unhandled: never = status;

      return unhandled;
    }
  }
}
// #endregion recipe:document-editor
