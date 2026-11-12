"use client";

import type { UseChatHelpers } from "@ai-sdk/react";
import type { FileUIPart, UIMessage } from "ai";

import {
  ArrowUpIcon,
  ChevronLeftIcon,
  ChevronRightIcon,
  CopyIcon,
  PaperclipIcon,
  PencilIcon,
  RefreshCwIcon,
  SquareIcon,
  ThumbsDownIcon,
  ThumbsUpIcon,
  XIcon,
} from "lucide-react";
import { useExtracted } from "next-intl";
import { useSearchParams } from "next/navigation";
import { useRef, useState } from "react";

import { Bubble, BubbleContent } from "@/components/ui/bubble";
import { Button } from "@/components/ui/button";
import {
  Message,
  MessageContent,
  MessageFooter,
} from "@/components/ui/message";
import {
  MessageScroller,
  MessageScrollerButton,
  MessageScrollerContent,
  MessageScrollerItem,
  MessageScrollerProvider,
  MessageScrollerViewport,
} from "@/components/ui/message-scroller";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import { useSupabase } from "@/lib/hooks";

import type { MessageBranch, ModelOption } from "../assistant-queries";

import {
  confirmAttachment,
  rateMessage,
  reserveAttachment,
} from "../assistant-actions";
import { AssistantParts, FileChips, textOf } from "./chat-parts";

const NO_MODELS: readonly ModelOption[] = [];
const NO_BRANCHES: readonly MessageBranch[] = [];

/** What the view reads from `useAssistant`, `useDurableAssistant` or `useChat`. */
export type ChatLike = Pick<
  UseChatHelpers<UIMessage>,
  | "messages"
  | "status"
  | "error"
  | "sendMessage"
  | "regenerate"
  | "addToolApprovalResponse"
  | "addToolOutput"
> & { readonly stop: () => unknown };

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

    if (!reserved.ok) {
      return undefined;
    }

    const { bucket, path, token } = reserved.data;

    const uploaded = await supabase.storage
      .from(bucket)
      .uploadToSignedUrl(path, token, file);

    if (uploaded.error) {
      return undefined;
    }

    const confirmed = await confirmAttachment({ id: reserved.data.id });

    return confirmed.ok ? confirmed.data : undefined;
  } catch {
    return undefined;
  }
}

/** Edit in place: the new text replaces the turn and the answer runs again. */
function EditForm({
  initial,
  onSave,
  onCancel,
}: {
  initial: string;
  onSave: (text: string) => void;
  onCancel: () => void;
}) {
  const t = useExtracted("assistant");
  const [text, setText] = useState(initial);

  return (
    <form
      className="flex w-full flex-col gap-2"
      onSubmit={(event) => {
        event.preventDefault();

        if (text.trim() !== "") {
          onSave(text.trim());
        }
      }}
    >
      <Textarea
        value={text}
        onChange={(event) => {
          setText(event.target.value);
        }}
        aria-label={t("Edit message")}
        rows={3}
      />
      <div className="flex justify-end gap-2">
        <Button type="button" size="sm" variant="ghost" onClick={onCancel}>
          {t("Cancel")}
        </Button>
        <Button type="submit" size="sm">
          {t("Save and run again")}
        </Button>
      </div>
    </form>
  );
}

/** `‹ 2/3 ›` over the alternatives of one turn. */
function BranchSwitch({
  branch,
  onSwitch,
}: {
  branch: MessageBranch;
  onSwitch: (messageId: string) => void;
}) {
  const t = useExtracted("assistant");
  const previous = branch.siblingIds[branch.index - 1];
  const next = branch.siblingIds[branch.index + 1];

  return (
    <span className="flex items-center gap-1 tabular-nums">
      <Button
        size="icon-sm"
        variant="ghost"
        disabled={previous === undefined}
        aria-label={t("Previous version")}
        onClick={() => {
          if (previous !== undefined) {
            onSwitch(previous);
          }
        }}
      >
        <ChevronLeftIcon />
      </Button>
      {branch.index + 1}/{branch.siblingIds.length}
      <Button
        size="icon-sm"
        variant="ghost"
        disabled={next === undefined}
        aria-label={t("Next version")}
        onClick={() => {
          if (next !== undefined) {
            onSwitch(next);
          }
        }}
      >
        <ChevronRightIcon />
      </Button>
    </span>
  );
}

/** The message actions: copy, rate, regenerate, edit and branch. */
function MessageActions({
  chatId,
  message,
  last,
  busy,
  rating,
  branch,
  onEdit,
  onRegenerate,
  onSwitch,
}: {
  chatId: string;
  message: UIMessage;
  last: boolean;
  busy: boolean;
  rating: boolean;
  branch: MessageBranch | undefined;
  onEdit: () => void;
  onRegenerate: () => void;
  onSwitch: (messageId: string) => void;
}) {
  const t = useExtracted("assistant");
  const [rated, setRated] = useState<-1 | 0 | 1>(0);

  const rate = (value: -1 | 1) => {
    const next = rated === value ? 0 : value;
    setRated(next);
    void rateMessage({ chatId, messageId: message.id, rating: next });
  };

  return (
    <MessageFooter className="gap-1">
      {branch === undefined ? null : (
        <BranchSwitch branch={branch} onSwitch={onSwitch} />
      )}
      {message.role === "user" ? (
        <Button
          size="icon-sm"
          variant="ghost"
          disabled={busy}
          aria-label={t("Edit message")}
          onClick={onEdit}
        >
          <PencilIcon />
        </Button>
      ) : (
        <>
          <Button
            size="icon-sm"
            variant="ghost"
            aria-label={t("Copy answer")}
            onClick={() => {
              void navigator.clipboard.writeText(textOf(message));
            }}
          >
            <CopyIcon />
          </Button>
          {rating ? (
            <>
              <Button
                size="icon-sm"
                variant="ghost"
                aria-pressed={rated === 1}
                aria-label={t("Good answer")}
                onClick={() => {
                  rate(1);
                }}
              >
                <ThumbsUpIcon />
              </Button>
              <Button
                size="icon-sm"
                variant="ghost"
                aria-pressed={rated === -1}
                aria-label={t("Bad answer")}
                onClick={() => {
                  rate(-1);
                }}
              >
                <ThumbsDownIcon />
              </Button>
            </>
          ) : null}
          {last ? (
            <Button
              size="icon-sm"
              variant="ghost"
              disabled={busy}
              aria-label={t("Regenerate")}
              onClick={onRegenerate}
            >
              <RefreshCwIcon />
            </Button>
          ) : null}
        </>
      )}
    </MessageFooter>
  );
}

/**
 * The thread and composer of one chat, built from the AI Elements parts:
 * `MessageScroller` keeps the end in view, each turn is a `Message` with a
 * `Bubble`, and tool calls, reasoning and questions render as traces. The
 * caller picks the hook (`useAssistant`, `useDurableAssistant` or a scripted
 * `useChat`), so the same view serves the stored chat and the scripted tour.
 */
export function ChatView({
  id,
  chat,
  models = NO_MODELS,
  model,
  onModelChange,
  branches = NO_BRANCHES,
  onSwitchBranch,
  uploads = false,
  rating = false,
}: {
  id: string;
  chat: ChatLike;
  models?: readonly ModelOption[];
  model?: string;
  onModelChange?: (model: string) => void;
  branches?: readonly MessageBranch[];
  onSwitchBranch?: (messageId: string) => void;
  uploads?: boolean;
  rating?: boolean;
}) {
  const t = useExtracted("assistant");
  // The command center sends a question as `?ask=`; it fills the composer without sending.
  const ask = useSearchParams().get("ask") ?? "";
  const [input, setInput] = useState(() => ask);
  const [editing, setEditing] = useState<string | undefined>();
  const [attachments, setAttachments] = useState<FileUIPart[]>([]);
  const [uploading, setUploading] = useState(false);
  const [uploadFailed, setUploadFailed] = useState(false);
  const picker = useRef<HTMLInputElement>(null);
  const supabase = useSupabase();
  const busy = chat.status === "submitted" || chat.status === "streaming";
  const lastId = chat.messages.at(-1)?.id;

  const send = () => {
    const text = input.trim();

    if (text === "" || busy || uploading) {
      return;
    }

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

  const modelItems = models.map((entry) => ({
    value: entry.id,
    label: entry.name,
  }));

  return (
    <div className="flex min-h-96 flex-col gap-4 rounded-xl border p-4">
      <MessageScrollerProvider>
        <MessageScroller className="h-[28rem]">
          <MessageScrollerViewport aria-label={t("Messages")}>
            <MessageScrollerContent>
              {chat.messages.map((message) => {
                const isUser = message.role === "user";
                const streaming = busy && message.id === lastId;

                return (
                  <MessageScrollerItem
                    key={message.id}
                    messageId={message.id}
                    scrollAnchor={isUser}
                  >
                    <Message align={isUser ? "end" : "start"}>
                      <MessageContent>
                        <FileChips files={filesOf(message)} />
                        {editing === message.id ? (
                          <EditForm
                            initial={textOf(message)}
                            onCancel={() => {
                              setEditing(undefined);
                            }}
                            onSave={(text) => {
                              setEditing(undefined);
                              void chat.sendMessage({
                                text,
                                messageId: message.id,
                              });
                            }}
                          />
                        ) : (
                          <Bubble
                            variant={isUser ? "default" : "ghost"}
                            align={isUser ? "end" : "start"}
                          >
                            <BubbleContent>
                              {isUser ? (
                                <p className="whitespace-pre-wrap">
                                  {textOf(message)}
                                </p>
                              ) : (
                                <AssistantParts
                                  message={message}
                                  chat={chat}
                                  animating={streaming}
                                />
                              )}
                            </BubbleContent>
                          </Bubble>
                        )}
                        {streaming && !isUser ? null : (
                          <MessageActions
                            chatId={id}
                            message={message}
                            last={message.id === lastId}
                            busy={busy}
                            rating={rating}
                            branch={branches.find(
                              (entry) => entry.messageId === message.id,
                            )}
                            onEdit={() => {
                              setEditing(message.id);
                            }}
                            onRegenerate={() => {
                              void chat.regenerate();
                            }}
                            onSwitch={(messageId) => {
                              onSwitchBranch?.(messageId);
                            }}
                          />
                        )}
                      </MessageContent>
                    </Message>
                  </MessageScrollerItem>
                );
              })}
            </MessageScrollerContent>
          </MessageScrollerViewport>
          <MessageScrollerButton />
        </MessageScroller>
      </MessageScrollerProvider>
      {chat.error ? (
        <p role="alert" className="text-sm text-destructive">
          {t("The answer failed. Try again.")}
        </p>
      ) : null}
      {uploadFailed ? (
        <p role="alert" className="text-sm text-destructive">
          {t("The file could not be attached.")}
        </p>
      ) : null}
      <FileChipsRemovable
        files={attachments}
        onRemove={(url) => {
          setAttachments((current) =>
            current.filter((entry) => entry.url !== url),
          );
        }}
      />
      <form
        className="flex items-end gap-2"
        onSubmit={(event) => {
          event.preventDefault();
          send();
        }}
      >
        {uploads ? (
          <>
            <input
              ref={picker}
              type="file"
              multiple
              hidden
              onChange={(event) => {
                const picked = [...(event.target.files ?? [])];
                event.target.value = "";

                if (picked.length > 0) {
                  void attach(picked);
                }
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
          </>
        ) : null}
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
        {modelItems.length > 0 && model !== undefined ? (
          <Select
            value={model}
            items={modelItems}
            onValueChange={(value) => {
              if (value !== null) {
                onModelChange?.(value);
              }
            }}
          >
            <SelectTrigger size="sm" className="w-44" aria-label={t("Model")}>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {modelItems.map((item) => (
                <SelectItem key={item.value} value={item.value}>
                  {item.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        ) : null}
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

/** The files waiting to be sent, each with a remove button. */
function FileChipsRemovable({
  files,
  onRemove,
}: {
  files: readonly FileUIPart[];
  onRemove: (url: string) => void;
}) {
  const t = useExtracted("assistant");

  if (files.length === 0) {
    return null;
  }

  return (
    <ul className="flex flex-wrap gap-2" aria-label={t("Attachments")}>
      {files.map((file) => (
        <li
          key={file.url}
          className="flex items-center gap-1 text-xs text-muted-foreground"
        >
          {file.filename ?? file.mediaType}
          <Button
            size="icon-sm"
            variant="ghost"
            aria-label={t("Remove {name}", {
              name: file.filename ?? file.mediaType,
            })}
            onClick={() => {
              onRemove(file.url);
            }}
          >
            <XIcon />
          </Button>
        </li>
      ))}
    </ul>
  );
}
