export type OutputControl = {
  write(message: string): void;
};

export type FailureOutput<JsonArtifact> = OutputControl & {
  stage(artifact: JsonArtifact): void;
  flush(): void;
};

export type CliIo = {
  stdin: Pick<typeof Deno.stdin, "read">;
  stdout: Pick<typeof Deno.stdout, "writeSync">;
  stderr: Pick<typeof Deno.stderr, "writeSync">;
};

const encoder = new TextEncoder();

export class Out<JsonArtifact> {
  readonly json: boolean;
  #write: Pick<typeof Deno.stdout, "writeSync">;
  #artifact: JsonArtifact | undefined;

  constructor(json: boolean, io: CliIo) {
    this.json = json;
    this.#write = io.stdout;
  }

  stage(artifact: JsonArtifact): void {
    if (this.json) {
      this.#artifact = artifact;
    }
  }

  write(message: string): void {
    if (!this.json) {
      this.#write.writeSync(encoder.encode(message));
    }
  }

  flush(): void {
    if (this.json && this.#artifact !== undefined) {
      this.#write.writeSync(encoder.encode(`${jsonLines(this.#artifact)}\n`));
    }
  }
}

export function printError(
  out: OutputControl,
  prefix: string,
  message: string,
  detail?: unknown,
): void {
  out.write(`${prefix}: ${message}\n`);
  const rendered = renderDetail(detail);
  if (rendered) {
    out.write(`${rendered}\n`);
  }
}

export function fail<JsonArtifact>(
  out: FailureOutput<JsonArtifact>,
  code: number,
  artifact: JsonArtifact,
  message: string,
  detail?: unknown,
): never {
  out.stage(artifact);
  printError(out, "offloader-configurator", message, detail);
  out.flush();
  Deno.exit(code);
}

export function jsonLines(value: unknown): string {
  return JSON.stringify(value, null, 2);
}

export function writeVisibleObject(
  out: OutputControl,
  value: Record<string, unknown>,
  labels: Record<string, string> = {},
): void {
  for (const [key, raw] of Object.entries(value)) {
    if (raw === undefined || raw === null || raw === "") {
      continue;
    }
    out.write(`${labels[key] ?? labelFromKey(key)}: ${renderScalar(raw)}\n`);
  }
}

function renderDetail(detail: unknown): string | undefined {
  if (detail === undefined || detail === null || detail === "") {
    return undefined;
  }
  if (typeof detail === "string") {
    return detail;
  }
  return jsonLines(detail);
}

function renderScalar(value: unknown): string {
  if (typeof value === "boolean") {
    return value ? "yes" : "no";
  }
  if (
    typeof value === "string" ||
    typeof value === "number" ||
    typeof value === "bigint"
  ) {
    return String(value);
  }
  return jsonLines(value);
}

function labelFromKey(key: string): string {
  return key
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .replace(/[-_]+/g, " ")
    .toLowerCase();
}
