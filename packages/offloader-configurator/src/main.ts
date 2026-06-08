#!/usr/bin/env -S deno run --allow-run --allow-read
import { type CliMode, parseCliArgs, usage } from "./lib/args.ts";
import { invalidCliArgs } from "./lib/cli-error.ts";
import { type CliIo, fail, Out, writeVisibleObject } from "./lib/out.ts";
import { resolveTransportCommand } from "./lib/transport.ts";
import * as codex from "./targets/codex/index.ts";
import * as gh from "./targets/gh/index.ts";

type SuccessEnvelope = {
  ok: true;
  target: string;
  command: string;
  state: unknown;
};

type HelpEnvelope = {
  ok: true;
  help: string;
};

type ErrorEnvelope = {
  ok: false;
  target?: string;
  command?: string;
  error: {
    type: string;
    detail: unknown;
  };
};

type JsonEnvelope = SuccessEnvelope | HelpEnvelope | ErrorEnvelope;

const ghStateLabels = {
  authenticated: "gh authenticated",
  account: "gh account",
  host: "gh host",
  gitUserName: "git user.name",
  gitUserEmail: "git user.email",
  credentialHelper: "git credential.helper",
};

const codexStateLabels = {
  authenticated: "codex authenticated",
  codexHome: "codex home",
  authJsonPresent: "codex auth.json present",
  loginStatus: "codex login status",
};

async function main(): Promise<void> {
  const io: CliIo = {
    stdin: Deno.stdin,
    stdout: Deno.stdout,
    stderr: Deno.stderr,
  };
  const parsed = parseCliArgs(Deno.args);
  const out = new Out<JsonEnvelope>(
    parsed.ok ? parsed.value.json : parsed.error.json,
    io,
  );
  if (!parsed.ok) {
    if (parsed.error.type === "help") {
      out.write(`${usage}\n`);
      out.stage({ ok: true, help: usage });
      out.flush();
      return;
    }

    fail(
      out,
      2,
      {
        ok: false,
        error: invalidCliArgs(parsed.error.message ?? "invalid arguments"),
      },
      parsed.error.message ?? "invalid arguments",
      "Run `offloader-configurator --help` for usage.",
    );
  }

  const opts = parsed.value;
  const mode: CliMode = opts.json ? "json" : "interactive";
  const transport = resolveTransportCommand(opts.transport);
  if (!transport.ok) {
    fail(
      out,
      2,
      {
        ok: false,
        target: opts.target,
        command: opts.command,
        error: transport.error,
      },
      transport.error.type,
      transport.error.detail,
    );
  }

  switch (opts.target) {
    case "gh": {
      const ctx: gh.CommandContext = { transport: transport.value };
      const command = opts.command;

      if (command === "check") {
        const parsedCheck = gh.parseCheckInput(opts.targetArgs);
        if (!parsedCheck.ok) {
          fail(
            out,
            2,
            {
              ok: false,
              target: "gh",
              command,
              error: parsedCheck.error,
            },
            parsedCheck.error.type,
            parsedCheck.error.detail,
          );
        }

        const guardResult = await gh.guard(ctx);
        if (!guardResult.ok) {
          fail(
            out,
            1,
            {
              ok: false,
              target: "gh",
              command,
              error: guardResult.error,
            },
            guardResult.error.type,
            guardResult.error.detail,
          );
        }

        if (!guardResult.value.ok) {
          const error = {
            type: "guard-failed" as const,
            detail: guardResult.value.error,
          };
          fail(
            out,
            1,
            {
              ok: false,
              target: "gh",
              command,
              error,
            },
            error.type,
            error.detail,
          );
        }

        const state = await gh.query(ctx);
        if (!state.ok) {
          fail(
            out,
            1,
            {
              ok: false,
              target: "gh",
              command,
              error: state.error,
            },
            state.error.type,
            state.error.detail,
          );
        }

        out.stage({
          ok: true,
          target: "gh",
          command,
          state: state.value,
        });

        writeVisibleObject(out, state.value, ghStateLabels);
        out.flush();
        return;
      }

      const mutationInput = gh.parseInput(command, opts.targetArgs);
      if (!mutationInput.ok) {
        fail(
          out,
          2,
          {
            ok: false,
            target: "gh",
            command,
            error: mutationInput.error,
          },
          mutationInput.error.type,
          mutationInput.error.detail,
        );
      }

      const completePayload = gh.parseCompleteMutationPayload(
        mutationInput.value,
      );
      if (!completePayload.ok && mode === "json") {
        fail(
          out,
          2,
          {
            ok: false,
            target: "gh",
            command,
            error: completePayload.error,
          },
          completePayload.error.type,
          completePayload.error.detail,
        );
      }

      const guardResult = await gh.guard(ctx);
      if (!guardResult.ok) {
        fail(
          out,
          1,
          {
            ok: false,
            target: "gh",
            command,
            error: guardResult.error,
          },
          guardResult.error.type,
          guardResult.error.detail,
        );
      }

      if (!guardResult.value.ok) {
        const error = {
          type: "guard-failed" as const,
          detail: guardResult.value.error,
        };
        fail(
          out,
          1,
          {
            ok: false,
            target: "gh",
            command,
            error,
          },
          error.type,
          error.detail,
        );
      }

      const candidatePayload = completePayload.ok
        ? completePayload
        : await gh.completeInput(mutationInput.value, io);
      if (!candidatePayload.ok) {
        const error = {
          type: "mutation-planning-failed" as const,
          detail: candidatePayload.error,
        };
        fail(
          out,
          1,
          {
            ok: false,
            target: "gh",
            command,
            error,
          },
          error.type,
          error.detail,
        );
      }

      const finalPayload = gh.mutationSchema.safeParse(candidatePayload.value);
      if (!finalPayload.success) {
        const error = {
          type: "mutation-planning-failed" as const,
          detail: {
            type: "invalid-mutation",
            detail: finalPayload.error.issues,
          },
        };
        fail(
          out,
          1,
          {
            ok: false,
            target: "gh",
            command,
            error,
          },
          error.type,
          error.detail,
        );
      }

      const result = await gh.mutate(ctx, finalPayload.data);
      if (!result.ok) {
        fail(
          out,
          1,
          {
            ok: false,
            target: "gh",
            command,
            error: result.error,
          },
          result.error.type,
          result.error.detail,
        );
      }

      out.stage({
        ok: true,
        target: "gh",
        command,
        state: result.value,
      });

      out.write("Configured gh.\n");
      writeVisibleObject(out, result.value, ghStateLabels);
      out.flush();
      return;
    }
    case "codex": {
      const ctx: codex.CommandContext = { transport: transport.value };
      const command = opts.command;

      if (command === "check") {
        const parsedCheck = codex.parseCheckInput(opts.targetArgs);
        if (!parsedCheck.ok) {
          fail(
            out,
            2,
            {
              ok: false,
              target: "codex",
              command,
              error: parsedCheck.error,
            },
            parsedCheck.error.type,
            parsedCheck.error.detail,
          );
        }

        const guardResult = await codex.guard(ctx);
        if (!guardResult.ok) {
          fail(
            out,
            1,
            {
              ok: false,
              target: "codex",
              command,
              error: guardResult.error,
            },
            guardResult.error.type,
            guardResult.error.detail,
          );
        }

        if (!guardResult.value.ok) {
          const error = {
            type: "guard-failed" as const,
            detail: guardResult.value.error,
          };
          fail(
            out,
            1,
            {
              ok: false,
              target: "codex",
              command,
              error,
            },
            error.type,
            error.detail,
          );
        }

        const state = await codex.query(ctx);
        if (!state.ok) {
          fail(
            out,
            1,
            {
              ok: false,
              target: "codex",
              command,
              error: state.error,
            },
            state.error.type,
            state.error.detail,
          );
        }

        out.stage({
          ok: true,
          target: "codex",
          command,
          state: state.value,
        });

        writeVisibleObject(out, state.value, codexStateLabels);
        out.flush();
        return;
      }

      const mutationInput = codex.parseInput(command, opts.targetArgs);
      if (!mutationInput.ok) {
        fail(
          out,
          2,
          {
            ok: false,
            target: "codex",
            command,
            error: mutationInput.error,
          },
          mutationInput.error.type,
          mutationInput.error.detail,
        );
      }

      const completePayload = codex.parseCompleteMutationPayload(
        mutationInput.value,
      );
      if (!completePayload.ok && mode === "json") {
        fail(
          out,
          2,
          {
            ok: false,
            target: "codex",
            command,
            error: completePayload.error,
          },
          completePayload.error.type,
          completePayload.error.detail,
        );
      }

      const guardResult = await codex.guard(ctx);
      if (!guardResult.ok) {
        fail(
          out,
          1,
          {
            ok: false,
            target: "codex",
            command,
            error: guardResult.error,
          },
          guardResult.error.type,
          guardResult.error.detail,
        );
      }

      if (!guardResult.value.ok) {
        const error = {
          type: "guard-failed" as const,
          detail: guardResult.value.error,
        };
        fail(
          out,
          1,
          {
            ok: false,
            target: "codex",
            command,
            error,
          },
          error.type,
          error.detail,
        );
      }

      const candidatePayload = completePayload.ok
        ? completePayload
        : await codex.completeInput(mutationInput.value, io);
      if (!candidatePayload.ok) {
        const error = {
          type: "mutation-planning-failed" as const,
          detail: candidatePayload.error,
        };
        fail(
          out,
          1,
          {
            ok: false,
            target: "codex",
            command,
            error,
          },
          error.type,
          error.detail,
        );
      }

      const finalPayload = codex.mutationSchema.safeParse(
        candidatePayload.value,
      );
      if (!finalPayload.success) {
        const error = {
          type: "mutation-planning-failed" as const,
          detail: {
            type: "invalid-mutation",
            detail: finalPayload.error.issues,
          },
        };
        fail(
          out,
          1,
          {
            ok: false,
            target: "codex",
            command,
            error,
          },
          error.type,
          error.detail,
        );
      }

      const result = await codex.mutate(ctx, finalPayload.data);
      if (!result.ok) {
        fail(
          out,
          1,
          {
            ok: false,
            target: "codex",
            command,
            error: result.error,
          },
          result.error.type,
          result.error.detail,
        );
      }

      out.stage({
        ok: true,
        target: "codex",
        command,
        state: result.value,
      });

      out.write("Configured codex.\n");
      writeVisibleObject(out, result.value, codexStateLabels);
      out.flush();
      return;
    }
    default:
      fail(
        out,
        2,
        {
          ok: false,
          target: opts.target,
          command: opts.command,
          error: { type: "unknown-target", detail: opts.target },
        },
        `unknown target: ${opts.target}`,
      );
  }
}

if (import.meta.main) {
  await main();
}
