"use client";

import type { FileUIPart, UIMessage } from "ai";

import { useAssistant } from "better-supabase/ai-sdk/react";
import {
  ArrowUpIcon,
  FileIcon,
  PaperclipIcon,
  SquareIcon,
  XIcon,
} from "lucide-react";
import { useExtracted } from "next-intl";
import { useRouter } from "next/navigation";
import { useRef, useState } from "react";

import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { useSupabase } from "@/lib/hooks";

import { confirmAttachment, reserveAttachment } from "../assistant-actions";

const textOf = (message: UIMessage): string =>
  message.parts
    .flatMap((part) => (part.type === "text" ? [part.text] : []))
    .join("");

const filesOf = (message: UIMessage): FileUIPart[] =>
  message.parts.flatMap((part) => (part.type === "file" ? [part] : []));

/** Reserves the file, uploads it to its signed URL, then confirms it. */
async function uploadAttachment(
  supabase: ReturnType<typeof useSupabase>,
  file: File,
  chatId: string,
): Promise<FileUIPart | undefined> {
  try {
    const reserved = await reserveAttachment({
      filename: file.name,
      mediaType: file.type === "" ? "application/octet-stream" : file.type,
      size: file.size,
      chatId,
    });
    if (!reserved.ok) return undefined;
    const { bucket, path, token } = reserved.data;
    const uploaded = await supabase.storage
      .from(bucket)
      .uploadToSignedUrl(path, token, file);
    if (uploaded.error) return undefined;
    const confirmed = await confirmAttachment({ id: reserved.data.id });
    return confirmed.ok ? confirmed.data : undefined;
  } catch {
    return undefined;
  }
}

/**
 * One chat on `useAssistant`: the server keeps the history, so a reload
 * shows the stored messages and picks up an answer that is still streaming.
 */
export function AssistantChat({
  id,
  messages,
}: {
  id: string;
  messages: UIMessage[];
}) {
  const t = useExtracted("assistant");
  const router = useRouter();
  const [input, setInput] = useState("");
  const [attachments, setAttachments] = useState<FileUIPart[]>([]);
  const [uploading, setUploading] = useState(false);
  const [uploadFailed, setUploadFailed] = useState(false);
  const picker = useRef<HTMLInputElement>(null);
  const supabase = useSupabase();
  const chat = useAssistant({
    id,
    messages,
    onFinish: () => {
      router.refresh();
    },
  });
  const busy = chat.status === "submitted" || chat.status === "streaming";

  const send = () => {
    const text = input.trim();
    if (text === "" || busy || uploading) return;
    setInput("");
    setAttachments([]);
    void chat.sendMessage({ text, files: attachments });
  };

  const attach = async (picked: readonly File[]) => {
    setUploading(true);
    setUploadFailed(false);
    for (const file of picked) {
      const part = await uploadAttachment(supabase, file, id);
      if (!part) {
        setUploadFailed(true);
        break;
      }
      setAttachments((current) => [...current, part]);
    }
    setUploading(false);
  };

  return (
    <div className="flex min-h-96 flex-col gap-4 rounded-xl border p-4">
      <ol className="flex flex-1 flex-col gap-3" aria-live="polite">
        {chat.messages.map((message) => (
          <li
            key={message.id}
            className={
              message.role === "user"
                ? "bg-primary text-primary-foreground max-w-4/5 self-end rounded-xl px-3 py-2 text-sm"
                : "bg-muted max-w-4/5 self-start rounded-xl px-3 py-2 text-sm"
            }
          >
            {filesOf(message).map((file) => (
              <p key={file.url} className="flex items-center gap-1 text-xs">
                <FileIcon className="size-3" aria-hidden />
                {file.filename ?? file.mediaType}
              </p>
            ))}
            <p className="whitespace-pre-wrap">{textOf(message)}</p>
          </li>
        ))}
      </ol>
      {chat.error ? (
        <p role="alert" className="text-destructive text-sm">
          {t("The answer failed. Try again.")}
        </p>
      ) : null}
      {uploadFailed ? (
        <p role="alert" className="text-destructive text-sm">
          {t("The file could not be attached.")}
        </p>
      ) : null}
      {attachments.length > 0 ? (
        <ul className="flex flex-wrap gap-2" aria-label={t("Attachments")}>
          {attachments.map((file) => (
            <li
              key={file.url}
              className="bg-muted flex items-center gap-1 rounded-md px-2 py-1 text-xs"
            >
              <FileIcon className="size-3" aria-hidden />
              {file.filename ?? file.mediaType}
              <button
                type="button"
                className="ml-1"
                aria-label={t("Remove {name}", {
                  name: file.filename ?? file.mediaType,
                })}
                onClick={() => {
                  setAttachments((current) =>
                    current.filter((entry) => entry.url !== file.url),
                  );
                }}
              >
                <XIcon className="size-3" aria-hidden />
              </button>
            </li>
          ))}
        </ul>
      ) : null}
      <form
        className="flex items-end gap-2"
        onSubmit={(event) => {
          event.preventDefault();
          send();
        }}
      >
        <input
          ref={picker}
          type="file"
          multiple
          hidden
          onChange={(event) => {
            const picked = [...(event.target.files ?? [])];
            event.target.value = "";
            if (picked.length > 0) void attach(picked);
          }}
        />
        <Button
          type="button"
          size="icon"
          variant="ghost"
          disabled={uploading}
          onClick={() => {
            picker.current?.click();
          }}
          aria-label={t("Attach a file")}
        >
          <PaperclipIcon />
        </Button>
        <Textarea
          value={input}
          onChange={(event) => {
            setInput(event.target.value);
          }}
          onKeyDown={(event) => {
            if (event.key === "Enter" && !event.shiftKey) {
              event.preventDefault();
              send();
            }
          }}
          placeholder={t("Ask anything")}
          aria-label={t("Message")}
          rows={2}
        />
        {busy ? (
          <Button
            type="button"
            size="icon"
            variant="outline"
            onClick={() => {
              void chat.stop();
            }}
            aria-label={t("Stop")}
          >
            <SquareIcon />
          </Button>
        ) : (
          <Button type="submit" size="icon" aria-label={t("Send")}>
            <ArrowUpIcon />
          </Button>
        )}
      </form>
    </div>
  );
}
