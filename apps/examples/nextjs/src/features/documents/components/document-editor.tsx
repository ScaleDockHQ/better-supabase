// #region recipe:document-editor
"use client";

import type {
  DocumentSuggestion,
  Documents,
} from "better-supabase/blocks/documents";
import type {
  DocumentProviderMode,
  DocumentProviderStatus,
} from "better-supabase/yjs";

import { rpcTransport } from "better-supabase/blocks";
import { createDocuments } from "better-supabase/blocks/documents";
import { createDocumentProvider } from "better-supabase/yjs";
import { MessageSquareDiffIcon, TriangleAlertIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";
import { useCallback, useEffect, useId, useRef, useState } from "react";
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
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Field, FieldDescription, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
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
  readonly canSuggest: boolean;
}

type SuggestionsState =
  | { readonly kind: "loading" }
  | { readonly kind: "error" }
  | { readonly kind: "ok"; readonly items: readonly DocumentSuggestion[] };

function isMode(value: unknown): value is DocumentProviderMode {
  return value === "edit" || value === "suggest";
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
  canSuggest,
  onRetry,
}: DocumentTarget & { readonly onRetry: () => void }) {
  const t = useExtracted("documents");
  const fieldId = useId();
  const supabase = useSupabase();
  const editing = useRef<Editing | null>(null);

  const session = useRef<{
    readonly documents: Documents;
    readonly provider: ReturnType<typeof createDocumentProvider>;
  } | null>(null);

  const [status, setStatus] = useState<DocumentProviderStatus>("connecting");
  const [failed, setFailed] = useState(false);
  const [writable, setWritable] = useState(false);
  const [suggestable, setSuggestable] = useState(false);
  const [documentId, setDocumentId] = useState<string | null>(null);

  const [mode, setMode] = useState<DocumentProviderMode>(
    canWrite ? "edit" : "suggest",
  );

  const [hasDraft, setHasDraft] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");

  const [suggestions, setSuggestions] = useState<SuggestionsState>({
    kind: "loading",
  });

  useEffect(() => {
    const doc = new Y.Doc();
    const texts = { title: doc.getText("title"), body: doc.getText("body") };

    const sync = () => {
      setTitle(texts.title.toString());
      setBody(texts.body.toString());
    };

    const documents = createDocuments({
      transport: rpcTransport(supabase),
      schema: blockConfig.documents.api,
    });

    const provider = createDocumentProvider({
      documents,
      client: supabase,
      doc,
      yjs: Y,
      ref: {
        organizationId,
        subjectType: "customer",
        subjectId: customerId,
        name: DOCUMENT_NAME,
      },
      mode: canWrite ? "edit" : "suggest",
      onStatus: setStatus,
    });

    texts.title.observe(sync);
    texts.body.observe(sync);
    editing.current = texts;
    session.current = { documents, provider };

    void provider.connect().then((opened) => {
      if (opened.ok) {
        setWritable(opened.data.canWrite);
        setSuggestable(opened.data.canSuggest);
        setDocumentId(opened.data.id);
        sync();
      } else {
        setFailed(true);
      }

      return opened;
    });

    return () => {
      texts.title.unobserve(sync);
      texts.body.unobserve(sync);
      editing.current = null;
      session.current = null;
      void provider.destroy();
      doc.destroy();
    };
  }, [supabase, organizationId, customerId, canWrite]);

  const loadSuggestions = useCallback(async () => {
    if (documentId === null || session.current === null) {
      return;
    }

    setSuggestions({ kind: "loading" });
    const listed = await session.current.documents.suggestions(documentId);

    setSuggestions(
      listed.ok ? { kind: "ok", items: listed.data } : { kind: "error" },
    );
  }, [documentId]);

  useEffect(() => {
    void loadSuggestions();
  }, [loadSuggestions]);

  const statusLabels: Record<DocumentProviderStatus, string> = {
    connecting: t("Connecting"),
    synced: t("Saved"),
    offline: t("Offline"),
    closed: t("Closed"),
  };

  const editable = canWrite && writable;
  const suggesting = mode === "suggest" && canSuggest && suggestable;
  const readOnly = !(suggesting || (mode === "edit" && editable));

  const changeMode = (next: DocumentProviderMode) => {
    setMode(next);
    session.current?.provider.setMode(next);
  };

  const edit = (text: "title" | "body", value: string) => {
    if (editing.current) {
      replaceText(editing.current[text], value);
    }

    setHasDraft(session.current?.provider.hasDraft ?? false);
  };

  const submit = async () => {
    if (session.current === null) {
      return;
    }

    setSubmitting(true);
    const stored = await session.current.provider.submitSuggestion();
    setSubmitting(false);

    if (stored.ok) {
      setHasDraft(false);
      await loadSuggestions();
    }
  };

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
            : suggesting
              ? t("Your edits become a suggestion that an editor accepts.")
              : t("Changes save as you type and show up for everyone editing.")}
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-6">
        {editable && canSuggest ? (
          <Tabs
            value={mode}
            onValueChange={(value) => {
              if (isMode(value)) {
                changeMode(value);
              }
            }}
          >
            <TabsList>
              <TabsTrigger value="edit">{t("Editing")}</TabsTrigger>
              <TabsTrigger value="suggest">{t("Suggesting")}</TabsTrigger>
            </TabsList>
          </Tabs>
        ) : null}
        {status === "connecting" && title === "" && body === "" ? (
          <div className="flex flex-col gap-4" aria-busy="true">
            <Skeleton className="h-9 w-full" />
            <Skeleton className="h-64 w-full" />
          </div>
        ) : (
          <div className="flex flex-col gap-4">
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
                  edit("title", event.target.value);
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
                  edit("body", event.target.value);
                }}
              />
              <FieldDescription>
                {t(
                  "Plain text. Everyone who can read the customer can read it.",
                )}
              </FieldDescription>
            </Field>
            {suggesting ? (
              <div className="flex items-center justify-end gap-2">
                <Button
                  size="sm"
                  disabled={!hasDraft || submitting}
                  onClick={() => {
                    void submit();
                  }}
                >
                  {t("Submit suggestion")}
                </Button>
              </div>
            ) : null}
          </div>
        )}
        <SuggestionList
          state={suggestions}
          canDecide={editable}
          canSuggest={canSuggest && suggestable}
          onRetry={() => {
            void loadSuggestions();
          }}
          onSuggest={() => {
            changeMode("suggest");
          }}
          onDecide={async (suggestion, decision) => {
            if (session.current === null) {
              return;
            }

            const decided =
              decision === "accepted"
                ? await session.current.provider.acceptSuggestion(suggestion.id)
                : await session.current.documents.decideSuggestion(
                    suggestion.id,
                    "rejected",
                  );

            if (decided.ok) {
              await loadSuggestions();
            }
          }}
        />
      </CardContent>
    </Card>
  );
}

interface SuggestionListProps {
  readonly state: SuggestionsState;
  readonly canDecide: boolean;
  readonly canSuggest: boolean;
  readonly onRetry: () => void;
  readonly onSuggest: () => void;
  readonly onDecide: (
    suggestion: DocumentSuggestion,
    decision: "accepted" | "rejected",
  ) => Promise<void>;
}

/** The open suggestions; editors accept them into the document or reject them. */
function SuggestionList({
  state,
  canDecide,
  canSuggest,
  onRetry,
  onSuggest,
  onDecide,
}: SuggestionListProps) {
  const t = useExtracted("documents");
  const format = useFormatter();
  const [busy, setBusy] = useState<string | null>(null);

  if (state.kind === "loading") {
    return (
      <div className="flex flex-col gap-2" aria-busy="true">
        <Skeleton className="h-5 w-32" />
        <Skeleton className="h-14 w-full" />
      </div>
    );
  }

  if (state.kind === "error") {
    return (
      <Alert variant="destructive">
        <TriangleAlertIcon />
        <AlertTitle>{t("The suggestions didn't load")}</AlertTitle>
        <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
        <AlertAction>
          <Button size="sm" variant="outline" onClick={onRetry}>
            {t("Retry")}
          </Button>
        </AlertAction>
      </Alert>
    );
  }

  if (state.items.length === 0) {
    return (
      <Empty className="border">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <MessageSquareDiffIcon />
          </EmptyMedia>
          <EmptyTitle>{t("No open suggestions")}</EmptyTitle>
          <EmptyDescription>
            {t("Suggested edits wait here until an editor accepts them.")}
          </EmptyDescription>
        </EmptyHeader>
        {canSuggest ? (
          <EmptyContent>
            <Button size="sm" variant="outline" onClick={onSuggest}>
              {t("Suggest a change")}
            </Button>
          </EmptyContent>
        ) : null}
      </Empty>
    );
  }

  return (
    <section className="flex flex-col gap-2">
      <h3 className="text-sm font-medium tracking-tight">{t("Suggestions")}</h3>
      <ul className="flex flex-col divide-y">
        {state.items.map((suggestion) => (
          <li
            key={suggestion.id}
            className="flex items-center justify-between gap-4 py-3"
          >
            <div className="flex flex-col gap-0.5">
              <span className="text-sm">
                {suggestion.summary ?? t("Suggested edit")}
              </span>
              <span className="text-xs text-muted-foreground">
                {format.relativeTime(
                  new Date(suggestion.createdAt.epochMilliseconds),
                )}
              </span>
            </div>
            {canDecide ? (
              <div className="flex items-center gap-2">
                <Button
                  size="sm"
                  variant="outline"
                  disabled={busy !== null}
                  onClick={() => {
                    setBusy(suggestion.id);
                    void onDecide(suggestion, "rejected").finally(() => {
                      setBusy(null);
                    });
                  }}
                >
                  {t("Reject")}
                </Button>
                <Button
                  size="sm"
                  disabled={busy !== null}
                  onClick={() => {
                    setBusy(suggestion.id);
                    void onDecide(suggestion, "accepted").finally(() => {
                      setBusy(null);
                    });
                  }}
                >
                  {t("Accept")}
                </Button>
              </div>
            ) : null}
          </li>
        ))}
      </ul>
    </section>
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
