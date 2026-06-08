import { INTERNAL_PREFIXES } from "./constants.ts";

export function shellResponse(
  id: string,
  targetOrigin: URL,
): Response {
  const body = `<!doctype html>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${id}</title>
<script type="module">
import { ScramjetController } from "/__scramjet/scramjet.bundle.js";
import { BareMuxConnection } from "/__baremux/index.mjs";

const routeId = ${JSON.stringify(id)};
const targetOrigin = ${JSON.stringify(targetOrigin.origin)};
const internalPrefixes = ${JSON.stringify(INTERNAL_PREFIXES)};

const scramjet = new ScramjetController({
  prefix: "/__scramjet/proxy/",
  files: {
    wasm: "/__scramjet/scramjet.wasm.wasm",
    all: "/__scramjet/scramjet.all.js",
    sync: "/__scramjet/scramjet.sync.js"
  },
  flags: {
    serviceworkers: true
  }
});

await resetScramjetDatabaseIfCorrupt();
await scramjet.openIDB();

const bareMux = new BareMuxConnection("/__baremux/worker.js");
await bareMux.setTransport("/__route-proxy/transport.js", [
  location.origin + "/__transport/" + routeId + "/"
]);
await bareMux.getTransport();

await navigator.serviceWorker.register("/__scramjet-sw.js", { scope: "/" });
await navigator.serviceWorker.ready;
await scramjet.init();

const frame = scramjet.createFrame();
frame.frame.style.cssText = "position:fixed;inset:0;width:100%;height:100%;border:0";
document.body.appendChild(frame.frame);

let applyingOuterUrl = null;
let lastOuter = location.pathname + location.search + location.hash;
let routeStack = [lastOuter];
let routeIndex = 0;

history.replaceState(stateFor(routeIndex), "", lastOuter);

frame.addEventListener("urlchange", syncOuterUrl);
frame.addEventListener("navigate", syncOuterUrl);

function syncOuterUrl(event) {
  if (isAppliedOuterNav(event.url)) return;
  const next = outerFromTarget(event.url);
  if (!next || next === lastOuter) return;

  lastOuter = next;

  if (routeStack[routeIndex - 1] === next) {
    routeIndex -= 1;
    history.replaceState(stateFor(routeIndex), "", next);
    return;
  }

  if (routeStack[routeIndex + 1] === next) {
    routeIndex += 1;
    history.replaceState(stateFor(routeIndex), "", next);
    return;
  }

  routeStack = routeStack.slice(0, routeIndex + 1);
  routeStack.push(next);
  routeIndex += 1;
  history.pushState(stateFor(routeIndex), "", next);
}

addEventListener("popstate", (event) => {
  const target = targetFromOuter(location);
  lastOuter = location.pathname + location.search + location.hash;
  if (Number.isInteger(event.state?.routeIndex)) {
    routeIndex = event.state.routeIndex;
  }
  applyingOuterUrl = new URL(target).toString();
  frame.frame.contentWindow?.location.replace(scramjet.encodeUrl(target));
});

frame.go(targetFromOuter(location));

async function resetScramjetDatabaseIfCorrupt() {
  const databaseNames = await indexedDB.databases?.();
  if (databaseNames && !databaseNames.some((database) => database.name === "$scramjet")) {
    return;
  }

  const database = await openScramjetDatabase();
  if (!database) return;

  const requiredStores = [
    "config",
    "cookies",
    "redirectTrackers",
    "referrerPolicies",
    "publicSuffixList"
  ];
  const hasRequiredStores = requiredStores.every((store) =>
    database.objectStoreNames.contains(store)
  );
  database.close();

  if (hasRequiredStores) return;

  return new Promise((resolve, reject) => {
    const request = indexedDB.deleteDatabase("$scramjet");
    request.onsuccess = () => resolve();
    request.onerror = () => reject(request.error);
    request.onblocked = () => resolve();
  });
}

function openScramjetDatabase() {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open("$scramjet");
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
    request.onblocked = () => resolve(null);
  });
}

function targetFromOuter(outer) {
  const parts = outer.pathname.split("/");
  const id = parts[1] || routeId;
  if (id !== routeId || internalPrefixes.includes(id)) {
    return targetOrigin + "/";
  }

  const path = "/" + parts.slice(2).join("/");
  return targetOrigin + path + outer.search + outer.hash;
}

function outerFromTarget(value) {
  const target = new URL(value);
  if (target.origin !== targetOrigin) return null;
  return "/" + routeId + target.pathname + target.search + target.hash;
}

function isAppliedOuterNav(value) {
  if (!applyingOuterUrl) return false;
  if (new URL(value).toString() !== applyingOuterUrl) return false;
  applyingOuterUrl = null;
  return true;
}

function stateFor(index) {
  return { ...(history.state ?? {}), routeIndex: index };
}
</script>
<body></body>`;

  return new Response(body, {
    headers: { "content-type": "text/html; charset=utf-8" },
  });
}

export function scramjetServiceWorkerScript(): string {
  return `
importScripts("/__scramjet/scramjet.all.js");

const { ScramjetServiceWorker } = $scramjetLoadWorker();

self.addEventListener("message", (event) => {
  if (event.data?.scramjet$type === "loadConfig") {
    // Let loadConfig() initialize Scramjet's module-global config from IndexedDB.
    event.stopImmediatePropagation();
  }
});

const scramjet = new ScramjetServiceWorker();

self.addEventListener("install", (event) => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener("activate", (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener("fetch", (event) => {
  event.respondWith((async () => {
    await scramjet.loadConfig();
    if (scramjet.route(event)) {
      return scramjet.fetch(event);
    }
    return fetch(event.request);
  })());
});
`;
}
