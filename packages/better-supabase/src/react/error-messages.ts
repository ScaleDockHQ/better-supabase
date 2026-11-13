import type { ReactNode } from "react";

import { createContext, createElement, useContext } from "react";

import type { DbError } from "../core/errors.ts";

/**
 * Turns an error into the sentence to show, such as `blockErrorMessage` plus
 * your fallback.
 */
export type ErrorMessageResolver = (error: DbError) => string;

const plain: ErrorMessageResolver = (error) => error.message;

const ErrorMessagesContext = createContext<ErrorMessageResolver>(plain);

/**
 * Sets how `useErrorMessage` words an error for the components below it. Build
 * `messages` where your translations are, so every component shows the same
 * wording without calling a translation hook itself.
 */
export function ErrorMessagesProvider(props: {
  readonly messages: ErrorMessageResolver;
  readonly children?: ReactNode;
}): ReactNode {
  return createElement(
    ErrorMessagesContext.Provider,
    { value: props.messages },
    props.children,
  );
}

/**
 * The sentence to show for a `DbError`: the resolver of the nearest
 * `ErrorMessagesProvider`, or the error's own English message without one.
 */
export function useErrorMessage(): ErrorMessageResolver {
  return useContext(ErrorMessagesContext);
}
