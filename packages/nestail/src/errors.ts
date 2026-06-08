export type ErrorCategory =
  | "bad-route"
  | "config-error"
  | "asset-missing";

export type RouteError = {
  category: ErrorCategory;
  status: number;
  message: string;
};

export function renderError(error: RouteError): Response {
  const body = `<!doctype html>
<meta charset="utf-8">
<title>${escapeHtml(error.message)}</title>
<h1>${escapeHtml(error.message)}</h1>`;

  return new Response(body, {
    status: error.status,
    headers: { "content-type": "text/html; charset=utf-8" },
  });
}

export function errorResponse(
  category: ErrorCategory,
  status: number,
  message: string,
): Response {
  return renderError({ category, status, message });
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}
