// Verify-TeardownCdp.mjs — Zero-dependency Node v26 + Chromium CDP verifier for docs/teardown/index.html

import { spawn, execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { pathToFileURL } from "node:url";

function parseArgs(argv) {
  const out = {
    html: "",
    userDataDir: "",
    viewportWidth: 1280,
    viewportHeight: 820,
    negativeSelfTest: false
  };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--html" && i + 1 < argv.length) out.html = argv[++i];
    else if (a === "--user-data-dir" && i + 1 < argv.length) out.userDataDir = argv[++i];
    else if (a === "--width" && i + 1 < argv.length) out.viewportWidth = Number(argv[++i]);
    else if (a === "--height" && i + 1 < argv.length) out.viewportHeight = Number(argv[++i]);
    else if (a === "--negative-self-test") out.negativeSelfTest = true;
  }
  return out;
}

function findBrowserExecutable() {
  const candidates = [
    "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
    "C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe",
    path.join(process.env.LOCALAPPDATA || "", "Google\\Chrome\\Application\\chrome.exe"),
    "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe",
    "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe"
  ];
  for (const c of candidates) {
    if (c && fs.existsSync(c)) return c;
  }
  throw new Error("No Chromium/Edge executable found on host");
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function killChromeTree(pid) {
  if (!pid) return;
  try {
    execFileSync("taskkill.exe", ["/F", "/T", "/PID", String(pid)], { stdio: "ignore" });
  } catch {
    // Ignore if already exited
  }
}

async function cleanupDirWithRetry(dirPath) {
  for (let i = 0; i < 8; i++) {
    try {
      if (fs.existsSync(dirPath)) {
        fs.rmSync(dirPath, { recursive: true, force: true });
      }
      return;
    } catch {
      await sleep(250);
    }
  }
}

class CdpClient {
  constructor(wsUrl) {
    this.ws = new WebSocket(wsUrl);
    this.nextId = 1;
    this.pending = new Map();
    this.events = [];
    this.openPromise = new Promise((resolve, reject) => {
      this.ws.addEventListener("open", () => resolve());
      this.ws.addEventListener("error", (err) => reject(new Error(`WebSocket error: ${err?.message || "unknown"}`)));
    });
    this.ws.addEventListener("message", (ev) => {
      const msg = JSON.parse(String(ev.data));
      if (msg.id !== undefined) {
        const entry = this.pending.get(msg.id);
        if (entry) {
          this.pending.delete(msg.id);
          if (msg.error) entry.reject(new Error(`CDP ${entry.method}: ${msg.error.message}`));
          else entry.resolve(msg.result);
        }
      } else if (msg.method) {
        this.events.push(msg);
      }
    });
  }

  async connect() {
    await this.openPromise;
  }

  send(method, params = {}) {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject, method });
      this.ws.send(JSON.stringify({ id, method, params }));
    });
  }

  async evalJs(expression) {
    const res = await this.send("Runtime.evaluate", {
      expression,
      returnByValue: true,
      awaitPromise: true
    });
    if (res.exceptionDetails) {
      throw new Error(`Page eval exception: ${res.exceptionDetails.text || JSON.stringify(res.exceptionDetails)}`);
    }
    return res.result ? res.result.value : undefined;
  }

  close() {
    try {
      this.ws.close();
    } catch {
      // Ignore
    }
  }
}

async function launchChrome(browserExe, userDataDir, w, h) {
  const args = [
    "--headless=new",
    "--use-gl=angle",
    "--use-angle=swiftshader",
    "--enable-webgl",
    "--ignore-gpu-blocklist",
    "--remote-debugging-port=0",
    "--no-first-run",
    "--no-default-browser-check",
    "--disable-background-networking",
    `--window-size=${w},${h}`,
    `--user-data-dir=${userDataDir}`,
    "about:blank"
  ];

  const proc = spawn(browserExe, args, { stdio: ["ignore", "ignore", "pipe"] });
  let stderrBuf = "";
  const wsPort = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`Timed out waiting for Chrome DevTools port. stderr=${stderrBuf}`)), 15000);
    proc.stderr.on("data", (chunk) => {
      stderrBuf += chunk.toString("utf8");
      const m = stderrBuf.match(/DevTools listening on ws:\/\/127\.0\.0\.1:(\d+)\//);
      if (m) {
        clearTimeout(timer);
        resolve(Number(m[1]));
      }
    });
    proc.on("exit", (code) => {
      clearTimeout(timer);
      reject(new Error(`Chrome exited prematurely (${code}). stderr=${stderrBuf}`));
    });
  });

  const targetsResp = await fetch(`http://127.0.0.1:${wsPort}/json/list`);
  const targets = await targetsResp.json();
  const pageTarget = targets.find((t) => t.type === "page") || targets[0];
  if (!pageTarget || !pageTarget.webSocketDebuggerUrl) {
    throw new Error("No page target returned by DevTools");
  }

  return { proc, wsUrl: pageTarget.webSocketDebuggerUrl };
}

async function runVerification(opts) {
  const browserExe = findBrowserExecutable();
  const ownProfile = !opts.userDataDir;
  const userDataDir = opts.userDataDir || fs.mkdtempSync(path.join(os.tmpdir(), "ugm_cdp_prof_"));
  fs.mkdirSync(userDataDir, { recursive: true });

  let proc = null;
  let client = null;
  let tempHtml = "";

  try {
    let targetHtml = opts.html;
    if (opts.negativeSelfTest) {
      tempHtml = path.join(userDataDir, "neg_external_test.html");
      fs.writeFileSync(
        tempHtml,
        `<!DOCTYPE html><html><head><meta charset="utf-8"><script src="https://example.invalid/bad.js"></script></head><body><script>console.error("E2E_NEG_CONSOLE_ERR"); throw new Error("E2E_NEG_EXC");</script></body></html>`,
        "utf8"
      );
      targetHtml = tempHtml;
    }

    if (!targetHtml || !fs.existsSync(targetHtml)) {
      throw new Error(`Target HTML file not found: ${targetHtml}`);
    }

    const launched = await launchChrome(browserExe, userDataDir, opts.viewportWidth, opts.viewportHeight);
    proc = launched.proc;
    client = new CdpClient(launched.wsUrl);
    await client.connect();

    await client.send("Page.enable");
    await client.send("Runtime.enable");
    await client.send("Network.enable");
    await client.send("Emulation.setDeviceMetricsOverride", {
      width: opts.viewportWidth,
      height: opts.viewportHeight,
      deviceScaleFactor: 1,
      mobile: false
    });

    const fileUrl = pathToFileURL(path.resolve(targetHtml)).href;
    await client.send("Page.navigate", { url: fileUrl });
    await sleep(1100);

    const externalRequests = [];
    const consoleErrors = [];
    const exceptions = [];

    for (const ev of client.events) {
      if (ev.method === "Network.requestWillBeSent") {
        const u = ev.params?.request?.url || "";
        if (!/^(file:|data:|blob:|about:)/i.test(u)) {
          externalRequests.push(u);
        }
      } else if (ev.method === "Runtime.consoleAPICalled") {
        if (ev.params?.type === "error") {
          const text = (ev.params.args || []).map((a) => a.value ?? a.description ?? "").join(" ");
          consoleErrors.push(text);
        }
      } else if (ev.method === "Runtime.exceptionThrown") {
        exceptions.push(ev.params?.exceptionDetails?.text || "Runtime exception");
      }
    }

    if (opts.negativeSelfTest) {
      return {
        ok: externalRequests.length > 0 && (consoleErrors.length > 0 || exceptions.length > 0),
        negativeSelfTest: true,
        externalRequests,
        consoleErrors,
        exceptions
      };
    }

    const staticCheck = await client.evalJs(`(() => {
      const canvas = document.querySelector('canvas');
      const rect = canvas ? canvas.getBoundingClientRect() : null;
      let nonZeroPixels = 0;
      let dataUrlLen = 0;
      let sampleBefore = '';
      if (canvas) {
        dataUrlLen = canvas.toDataURL().length;
        try {
          const ctx = canvas.getContext('2d');
          if (ctx) {
            const img = ctx.getImageData(0, 0, Math.min(200, canvas.width), Math.min(200, canvas.height)).data;
            const seen = new Set();
            for (let i = 0; i < img.length; i += 16) {
              seen.add(img[i] + ',' + img[i+1] + ',' + img[i+2]);
              if (seen.size > 4) break;
            }
            nonZeroPixels = seen.size;
          } else {
            nonZeroPixels = dataUrlLen > 2000 ? 10 : 0;
          }
        } catch {
          nonZeroPixels = dataUrlLen > 2000 ? 10 : 0;
        }
        sampleBefore = canvas.toDataURL().slice(-120);
      }
      const bodyText = document.body ? document.body.innerText : '';
      const layerButtons = Array.from(document.querySelectorAll('[data-layer], .layer-btn'));
      return {
        protocol: window.location.protocol,
        hasCanvas: Boolean(canvas),
        canvasW: rect ? rect.width : 0,
        canvasH: rect ? rect.height : 0,
        nonZeroColorCount: nonZeroPixels,
        dataUrlLen,
        sampleBefore,
        layerCount: layerButtons.length,
        themeAttr: document.documentElement.getAttribute('data-theme') || '',
        bodyHasLayers: /GUI|Трей/i.test(bodyText) && /PowerShell|AAA/i.test(bodyText) && /CPU|ЦП/i.test(bodyText) && /GPU|График/i.test(bodyText) && /RAM|Память/i.test(bodyText) && /Zapret|WinDivert/i.test(bodyText)
      };
    })()`);

    // Exercise interactive controls semantically
    const interactive = await client.evalJs(`(async () => {
      const wait = (ms) => new Promise(r => setTimeout(r, ms));
      const canvas = document.querySelector('canvas');
      const before = canvas ? canvas.toDataURL() : '';

      // 1. Theme toggle
      const themeBtn = document.getElementById('btnThemeToggle') || Array.from(document.querySelectorAll('button')).find(b => /тема|theme/i.test(b.textContent || ''));
      const themeBefore = document.documentElement.getAttribute('data-theme');
      if (themeBtn) themeBtn.click();
      await wait(120);
      const themeAfter = document.documentElement.getAttribute('data-theme');

      // 2. Cutaway toggle
      const cutBtn = document.getElementById('btnCutaway') || Array.from(document.querySelectorAll('button')).find(b => /разрез|cutaway/i.test(b.textContent || ''));
      const cutBefore = cutBtn ? cutBtn.getAttribute('aria-pressed') : '';
      if (cutBtn) cutBtn.click();
      await wait(120);
      const cutAfter = cutBtn ? cutBtn.getAttribute('aria-pressed') : '';

      // 3. Explode toggle / slider
      const expBtn = document.getElementById('btnExplodeToggle') || Array.from(document.querySelectorAll('button')).find(b => /разобр|собрат|explode/i.test(b.textContent || ''));
      const expSlider = document.getElementById('explodeSlider') || document.querySelector('input[type="range"]');
      const expBefore = expSlider ? String(expSlider.value) : '';
      if (expBtn) expBtn.click();
      await wait(350);
      const expAfter = expSlider ? String(expSlider.value) : '';

      // 4. Mode / Telemetry toggle (Normal <-> AAA)
      const normBtn = document.getElementById('btnModeNormal') || Array.from(document.querySelectorAll('button')).find(b => /штатн|normal/i.test(b.textContent || ''));
      const telRam = document.getElementById('telRam');
      const ramBefore = telRam ? telRam.textContent : '';
      if (normBtn) normBtn.click();
      await wait(350);
      const ramAfter = telRam ? telRam.textContent : '';

      // 5. Zoom + camera preset
      const zoomIn = document.getElementById('btnZoomIn');
      const hudZoom = document.getElementById('hudZoom');
      const zoomBefore = hudZoom ? hudZoom.textContent : '';
      if (zoomIn) zoomIn.click();
      await wait(250);
      const zoomAfter = hudZoom ? hudZoom.textContent : '';

      // 6. Select layer 7
      const l7 = document.querySelector('[data-layer="7"]');
      if (l7) l7.click();
      await wait(120);
      const insTitle = (document.getElementById('insTitle')?.textContent || '');

      const after = canvas ? canvas.toDataURL() : '';
      return {
        themeChanged: Boolean(themeBtn) && themeBefore !== themeAfter,
        themeBefore,
        themeAfter,
        cutawayChanged: Boolean(cutBtn) && cutBefore !== cutAfter,
        explodeChanged: Boolean(expSlider) && expBefore !== expAfter,
        telemetryChanged: Boolean(telRam) && ramBefore !== ramAfter,
        zoomChanged: Boolean(hudZoom) && zoomBefore !== zoomAfter,
        layer7Selected: /сет|zapret/i.test(insTitle),
        insTitle,
        canvasPixelsChanged: before !== after
      };
    })()`);

    // Viewport resize stress (960x680 -> 860x600 -> 390x844)
    const resizeResults = [];
    for (const vp of [[960, 680], [860, 600], [390, 844]]) {
      await client.send("Emulation.setDeviceMetricsOverride", {
        width: vp[0],
        height: vp[1],
        deviceScaleFactor: 1,
        mobile: vp[0] < 500
      });
      await sleep(150);
      const rInfo = await client.evalJs(`(() => {
        const c = document.querySelector('canvas');
        const r = c ? c.getBoundingClientRect() : { width: 0, height: 0 };
        return { w: r.width, h: r.height };
      })()`);
      resizeResults.push({ viewport: `${vp[0]}x${vp[1]}`, canvasW: rInfo.w, canvasH: rInfo.h });
    }

    // Re-collect events after interactions
    const postExternal = [];
    const postConsoleErr = [];
    const postExceptions = [];
    for (const ev of client.events) {
      if (ev.method === "Network.requestWillBeSent") {
        const u = ev.params?.request?.url || "";
        if (!/^(file:|data:|blob:|about:)/i.test(u)) postExternal.push(u);
      } else if (ev.method === "Runtime.consoleAPICalled" && ev.params?.type === "error") {
        postConsoleErr.push((ev.params.args || []).map((a) => a.value ?? a.description ?? "").join(" "));
      } else if (ev.method === "Runtime.exceptionThrown") {
        postExceptions.push(ev.params?.exceptionDetails?.text || "Runtime exception");
      }
    }

    const ok =
      postExternal.length === 0 &&
      postConsoleErr.length === 0 &&
      postExceptions.length === 0 &&
      staticCheck.protocol === "file:" &&
      staticCheck.hasCanvas &&
      staticCheck.canvasW > 100 &&
      staticCheck.canvasH > 100 &&
      staticCheck.nonZeroColorCount > 3 &&
      staticCheck.layerCount === 7 &&
      staticCheck.bodyHasLayers &&
      interactive.themeChanged &&
      interactive.cutawayChanged &&
      interactive.explodeChanged &&
      interactive.telemetryChanged &&
      interactive.layer7Selected &&
      interactive.canvasPixelsChanged &&
      resizeResults.every((r) => r.canvasW > 0 && r.canvasH > 0);

    return {
      ok,
      externalRequests: postExternal,
      consoleErrors: postConsoleErr,
      exceptions: postExceptions,
      staticCheck,
      interactive,
      resizeResults
    };
  } finally {
    if (client) client.close();
    if (proc) {
      try {
        proc.kill();
      } catch {}
      killChromeTree(proc.pid);
    }
    if (ownProfile) {
      await cleanupDirWithRetry(userDataDir);
    } else if (tempHtml && fs.existsSync(tempHtml)) {
      try {
        fs.rmSync(tempHtml, { force: true });
      } catch {}
    }
  }
}

const opts = parseArgs(process.argv);
runVerification(opts)
  .then((res) => {
    process.stdout.write(JSON.stringify(res, null, 2));
    process.exit(res.ok ? 0 : 1);
  })
  .catch((err) => {
    process.stderr.write(String(err?.stack || err) + "\n");
    process.exit(1);
  });
