import { err, ok, type Result } from "./result.ts";

export type TransportResult = {
  code: number;
  stdout: string;
  stderr: string;
};

export type TransportError =
  | { type: "transport-command-missing"; detail: string }
  | { type: "transport-process-failed"; detail: string };

const decoder = new TextDecoder();
const encoder = new TextEncoder();

export function resolveTransportCommand(
  override?: string,
): Result<string, TransportError> {
  const transport = override ?? Deno.env.get("OFFLOADER_CONFIG_TRANSPORT");
  if (!transport?.trim()) {
    return err({
      type: "transport-command-missing",
      detail: "set --transport or OFFLOADER_CONFIG_TRANSPORT",
    });
  }
  return ok(transport);
}

export async function runTransport(
  transport: string,
  script: string,
): Promise<Result<TransportResult, TransportError>> {
  if (!transport.trim()) {
    return err({
      type: "transport-command-missing",
      detail: "set --transport or OFFLOADER_CONFIG_TRANSPORT",
    });
  }

  try {
    const command = new Deno.Command("bash", {
      args: ["-c", transport],
      stdin: "piped",
      stdout: "piped",
      stderr: "piped",
    });
    const child = command.spawn();
    const writer = child.stdin.getWriter();
    await writer.write(encoder.encode(script));
    await writer.close();

    const output = await child.output();
    return ok({
      code: output.code,
      stdout: decoder.decode(output.stdout),
      stderr: decoder.decode(output.stderr),
    });
  } catch (error) {
    return err({
      type: "transport-process-failed",
      detail: error instanceof Error ? error.message : String(error),
    });
  }
}
