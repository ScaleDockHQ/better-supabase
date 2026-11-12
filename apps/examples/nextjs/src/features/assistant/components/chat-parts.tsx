"use client";

import type {
  DynamicToolUIPart,
  FileUIPart,
  ReasoningUIPart,
  ToolUIPart,
  UIMessage,
} from "ai";

import { getToolName, isToolUIPart } from "ai";
import {
  BrainIcon,
  CheckIcon,
  CircleAlertIcon,
  FileIcon,
  LoaderCircleIcon,
  ShieldQuestionIcon,
  WrenchIcon,
  XIcon,
} from "lucide-react";
import { useExtracted } from "next-intl";

import {
  Attachment,
  AttachmentContent,
  AttachmentGroup,
  AttachmentMedia,
  AttachmentTitle,
} from "@/components/ui/attachment";
import { Button } from "@/components/ui/button";
import {
  Questionnaire,
  QuestionnaireActions,
  QuestionnaireChoice,
  QuestionnaireChoices,
  QuestionnaireDescription,
  QuestionnaireItem,
  QuestionnaireNext,
  QuestionnairePrevious,
  QuestionnaireProgress,
  QuestionnaireSubmit,
  QuestionnaireTitle,
} from "@/components/ui/questionnaire";
import {
  Trace,
  TraceCollapsible,
  TraceCollapsibleContent,
  TraceCollapsibleTrigger,
  TraceIcon,
  TraceLine,
  TraceTitle,
} from "@/components/ui/trace";

import { MessageTextLazy } from "./message-text-lazy";

/** What the parts need from the chat: the two answers a paused tool waits for. */
export interface ChatPartsActions {
  readonly addToolApprovalResponse: (response: {
    readonly id: string;
    readonly approved: boolean;
  }) => unknown;
  readonly addToolOutput: (output: {
    readonly tool: string;
    readonly toolCallId: string;
    readonly output: unknown;
  }) => unknown;
}

type ToolPart = DynamicToolUIPart | ToolUIPart;

/** The tool the model calls to ask the user clarifying questions. */
const QUESTIONS_TOOL = "askQuestions";

export interface Question {
  readonly name: string;
  readonly title: string;
  readonly description?: string;
  readonly choices: readonly string[];
  readonly multiple?: boolean;
}

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null;

/** The questions an `askQuestions` call carries; a malformed input yields none. */
export function questionsOf(input: unknown): readonly Question[] {
  if (!isRecord(input) || !Array.isArray(input["questions"])) {
    return [];
  }

  return input["questions"].flatMap((entry): Question[] => {
    if (
      !isRecord(entry) ||
      typeof entry["name"] !== "string" ||
      typeof entry["title"] !== "string" ||
      !Array.isArray(entry["choices"])
    ) {
      return [];
    }

    return [
      {
        name: entry["name"],
        title: entry["title"],
        ...(typeof entry["description"] === "string"
          ? { description: entry["description"] }
          : {}),
        choices: entry["choices"].filter(
          (choice): choice is string => typeof choice === "string",
        ),
        multiple: entry["multiple"] === true,
      },
    ];
  });
}

/** The text of a message, parts joined. */
export const textOf = (message: UIMessage): string =>
  message.parts
    .flatMap((part) => (part.type === "text" ? [part.text] : []))
    .join("");

const stringify = (value: unknown): string => {
  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return String(value);
  }
};

/** The reasoning of the model, folded away until the user opens it. */
function ReasoningPart({
  part,
  streaming,
}: {
  part: ReasoningUIPart;
  streaming: boolean;
}) {
  const t = useExtracted("assistant");

  return (
    <TraceCollapsible>
      <TraceCollapsibleTrigger>
        <TraceLine {...(streaming ? { status: "running" as const } : {})}>
          <TraceIcon>
            <BrainIcon />
          </TraceIcon>
          <TraceTitle>{streaming ? t("Thinking") : t("Reasoning")}</TraceTitle>
        </TraceLine>
      </TraceCollapsibleTrigger>
      <TraceCollapsibleContent>
        <p className="text-sm whitespace-pre-wrap">{part.text}</p>
      </TraceCollapsibleContent>
    </TraceCollapsible>
  );
}

/** The clarifying questions of one `askQuestions` call, answered in place. */
function QuestionsPart({
  part,
  chat,
}: {
  part: ToolPart;
  chat: ChatPartsActions;
}) {
  const t = useExtracted("assistant");
  const questions = questionsOf(part.input);
  const name = getToolName(part);

  if (part.state === "output-available") {
    return (
      <Trace>
        <TraceLine>
          <TraceIcon>
            <CheckIcon />
          </TraceIcon>
          <TraceTitle>
            {t("Answered {count, number} questions", {
              count: questions.length,
            })}
          </TraceTitle>
        </TraceLine>
      </Trace>
    );
  }

  if (questions.length === 0) {
    return null;
  }

  return (
    <Questionnaire
      items={questions.map((question) => ({
        name: question.name,
        required: true,
        choices: question.choices.map((value) => ({ value })),
      }))}
      onSubmit={(event) => {
        event.preventDefault();
        const form = new FormData(event.currentTarget);

        const answers = Object.fromEntries(
          questions.map((question) => [
            question.name,
            question.multiple === true
              ? form.getAll(question.name).map(String)
              : String(form.get(question.name) ?? ""),
          ]),
        );

        void chat.addToolOutput({
          tool: name,
          toolCallId: part.toolCallId,
          output: { answers },
        });
      }}
    >
      <QuestionnaireProgress />
      {questions.map((question) => (
        <QuestionnaireItem
          key={question.name}
          name={question.name}
          multiple={question.multiple === true}
          required
        >
          <QuestionnaireTitle>{question.title}</QuestionnaireTitle>
          {question.description === undefined ? null : (
            <QuestionnaireDescription>
              {question.description}
            </QuestionnaireDescription>
          )}
          <QuestionnaireChoices>
            {question.choices.map((choice) => (
              <QuestionnaireChoice key={choice} value={choice}>
                {choice}
              </QuestionnaireChoice>
            ))}
          </QuestionnaireChoices>
        </QuestionnaireItem>
      ))}
      <QuestionnaireActions>
        <QuestionnairePrevious>{t("Back")}</QuestionnairePrevious>
        <QuestionnaireNext>{t("Next")}</QuestionnaireNext>
        <QuestionnaireSubmit>{t("Send answers")}</QuestionnaireSubmit>
      </QuestionnaireActions>
    </Questionnaire>
  );
}

/** A tool that waits for the user's decision, with the input it would run on. */
function ApprovalPart({
  part,
  chat,
}: {
  part: ToolPart & { state: "approval-requested" };
  chat: ChatPartsActions;
}) {
  const t = useExtracted("assistant");
  const name = getToolName(part);

  const decide = (approved: boolean) => {
    void chat.addToolApprovalResponse({ id: part.approval.id, approved });
  };

  return (
    <fieldset
      className="flex min-w-0 flex-col gap-3 rounded-xl border bg-card p-3 text-sm"
      aria-label={t("{tool} needs your approval", { tool: name })}
    >
      <p className="flex items-center gap-2 font-medium">
        <ShieldQuestionIcon className="size-4" aria-hidden />
        {t("{tool} needs your approval", { tool: name })}
      </p>
      <pre className="overflow-x-auto text-xs whitespace-pre-wrap text-muted-foreground">
        {stringify(part.input)}
      </pre>
      <div className="flex gap-2">
        <Button
          size="sm"
          onClick={() => {
            decide(true);
          }}
        >
          <CheckIcon />
          {t("Approve")}
        </Button>
        <Button
          size="sm"
          variant="outline"
          onClick={() => {
            decide(false);
          }}
        >
          <XIcon />
          {t("Deny")}
        </Button>
      </div>
    </fieldset>
  );
}

/** One tool call as a trace line that opens to its input and output. */
function ToolTrace({ part }: { part: ToolPart }) {
  const t = useExtracted("assistant");
  const name = getToolName(part);

  const status =
    part.state === "output-error"
      ? ("error" as const)
      : part.state === "output-available" || part.state === "output-denied"
        ? undefined
        : ("running" as const);

  const label =
    part.state === "output-denied"
      ? t("{tool} was denied", { tool: name })
      : part.state === "output-available"
        ? t("{tool} finished", { tool: name })
        : part.state === "output-error"
          ? t("{tool} failed", { tool: name })
          : t("Running {tool}", { tool: name });

  return (
    <TraceCollapsible>
      <TraceCollapsibleTrigger>
        <TraceLine {...(status === undefined ? {} : { status })}>
          <TraceIcon>
            {status === "error" ? (
              <CircleAlertIcon />
            ) : status === "running" ? (
              <LoaderCircleIcon className="animate-spin motion-reduce:animate-none" />
            ) : (
              <WrenchIcon />
            )}
          </TraceIcon>
          <TraceTitle>{label}</TraceTitle>
        </TraceLine>
      </TraceCollapsibleTrigger>
      <TraceCollapsibleContent>
        <div className="flex flex-col gap-2 text-xs">
          <pre className="overflow-x-auto whitespace-pre-wrap">
            {stringify(part.input)}
          </pre>
          {part.state === "output-available" ? (
            <pre className="overflow-x-auto whitespace-pre-wrap">
              {stringify(part.output)}
            </pre>
          ) : null}
          {part.state === "output-error" ? (
            <p className="text-destructive">{part.errorText}</p>
          ) : null}
        </div>
      </TraceCollapsibleContent>
    </TraceCollapsible>
  );
}

function ToolPartView({
  part,
  chat,
}: {
  part: ToolPart;
  chat: ChatPartsActions;
}) {
  if (getToolName(part) === QUESTIONS_TOOL) {
    return <QuestionsPart part={part} chat={chat} />;
  }

  if (part.state === "approval-requested") {
    return <ApprovalPart part={{ ...part, state: part.state }} chat={chat} />;
  }

  return <ToolTrace part={part} />;
}

/** An attached or generated file as a chip. */
export function FileChips({ files }: { files: readonly FileUIPart[] }) {
  if (files.length === 0) {
    return null;
  }

  return (
    <AttachmentGroup>
      {files.map((file) => (
        <Attachment key={file.url} size="sm">
          <AttachmentMedia>
            <FileIcon />
          </AttachmentMedia>
          <AttachmentContent>
            <AttachmentTitle>{file.filename ?? file.mediaType}</AttachmentTitle>
          </AttachmentContent>
        </Attachment>
      ))}
    </AttachmentGroup>
  );
}

interface Source {
  readonly id: string;
  readonly title: string;
  readonly url: string | undefined;
}

const sourcesOf = (message: UIMessage): Source[] =>
  message.parts.flatMap((part): Source[] => {
    if (part.type === "source-url") {
      return [
        { id: part.sourceId, title: part.title ?? part.url, url: part.url },
      ];
    }

    return part.type === "source-document"
      ? [{ id: part.sourceId, title: part.title, url: undefined }]
      : [];
  });

/** The sources and knowledge citations an answer carries, as a trace. */
function Sources({ sources }: { sources: readonly Source[] }) {
  const t = useExtracted("assistant");

  return (
    <TraceCollapsible>
      <TraceCollapsibleTrigger>
        <TraceLine>
          <TraceTitle>
            {t("{count, number} sources", { count: sources.length })}
          </TraceTitle>
        </TraceLine>
      </TraceCollapsibleTrigger>
      <TraceCollapsibleContent>
        <ul className="flex flex-col gap-1 text-xs" aria-label={t("Sources")}>
          {sources.map((source) => (
            <li key={source.id}>
              {source.url === undefined ? (
                source.title
              ) : (
                <a
                  href={source.url}
                  target="_blank"
                  rel="noreferrer"
                  className="underline underline-offset-2 transition-colors hover:text-foreground"
                >
                  {source.title}
                </a>
              )}
            </li>
          ))}
        </ul>
      </TraceCollapsibleContent>
    </TraceCollapsible>
  );
}

/**
 * The parts of an answer in the order the model wrote them: reasoning, tool
 * traces, approvals, questions and text, then the sources it cites.
 */
export function AssistantParts({
  message,
  chat,
  animating,
}: {
  message: UIMessage;
  chat: ChatPartsActions;
  animating: boolean;
}) {
  const sources = sourcesOf(message);
  const lastIndex = message.parts.length - 1;

  return (
    <>
      {message.parts.map((part, index) => {
        const key = `${message.id}-${index}`;

        if (part.type === "reasoning") {
          return (
            <ReasoningPart
              key={key}
              part={part}
              streaming={animating && index === lastIndex}
            />
          );
        }

        if (isToolUIPart(part)) {
          return <ToolPartView key={part.toolCallId} part={part} chat={chat} />;
        }

        if (part.type === "text" && part.text !== "") {
          return (
            <MessageTextLazy
              key={key}
              text={part.text}
              animating={animating && index === lastIndex}
            />
          );
        }

        return null;
      })}
      {sources.length === 0 ? null : <Sources sources={sources} />}
    </>
  );
}
