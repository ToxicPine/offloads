import { z } from "zod";

export type CliBoundaryError = {
  type: "invalid-cli-args";
  detail: unknown;
};

export function invalidCliArgs(detail: unknown): CliBoundaryError {
  return { type: "invalid-cli-args", detail };
}

export function invalidCliArgsFrom(error: unknown): CliBoundaryError {
  if (error instanceof z.ZodError) {
    return invalidCliArgs(error.issues);
  }
  if (error instanceof Error) {
    return invalidCliArgs(error.message);
  }
  return invalidCliArgs(String(error));
}
