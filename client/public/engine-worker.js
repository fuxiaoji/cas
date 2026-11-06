// The Worker owns the offline authority. Only replies returned by the core's
// request boundary leave it; there is no JS simulation or renderer fallback.
const encoder = new TextEncoder();
const decoder = new TextDecoder('utf-8', { fatal: true });
let initialization;
let queue = Promise.resolve();

function exportsForSession() {
  initialization ??= (async () => {
    const url = new URL('./cas_core.wasm', self.location.href);
    const response = await fetch(url, { cache: 'no-cache' });
    if (!response.ok) throw new Error(`无法加载战斗内核（${response.status}）。`);
    // The desktop's virtual asset host may not advertise application/wasm.
    const { instance } = await WebAssembly.instantiate(await response.arrayBuffer(), {});
    const api = instance.exports;
    if (!(api.memory instanceof WebAssembly.Memory) ||
        ['cas_alloc', 'cas_request', 'cas_response_len'].some(name => typeof api[name] !== 'function')) {
      throw new Error('战斗内核和客户端版本不匹配。');
    }
    return api;
  })();
  return initialization;
}

async function dispatch(id, request) {
  try {
    const api = await exportsForSession();
    const payload = encoder.encode(JSON.stringify(request));
    const ptr = api.cas_alloc(payload.byteLength) >>> 0;
    if (ptr === 0) throw new Error('战斗内核无法接收命令。');
    new Uint8Array(api.memory.buffer, ptr, payload.byteLength).set(payload);
    const out = api.cas_request(ptr, payload.byteLength) >>> 0;
    const count = api.cas_response_len() >>> 0;
    // cas_request may grow memory; take a fresh buffer and decode before the
    // next request can invalidate the core-owned response.
    if (!out || !count) throw new Error('战斗内核没有返回结果。');
    const response = JSON.parse(decoder.decode(new Uint8Array(api.memory.buffer, out, count)));
    if (typeof response?.ok !== 'boolean') throw new Error('战斗内核返回了无法识别的结果。');
    self.postMessage({ id, response });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    self.postMessage({ id, response: { ok: false, error: message } });
  }
}

self.onmessage = ({ data }) => {
  if (!data || !Number.isSafeInteger(data.id) || typeof data.request !== 'object' || !data.request) return;
  // Keep request order even during the initial WASM fetch.
  queue = queue.then(() => dispatch(data.id, data.request));
};
