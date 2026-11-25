// Mynote 存储 Worker 分发层（SQLite 接入阶段二）。
// OPFS 同步访问句柄只存在于 Dedicated Worker，SQLite 必须
// 住在这里；主线程（apps/web/src/persist.rs）与演练台
// （index.html）都只经 postMessage RPC 调用：
//   请求 {id, cmd, payload} → 响应 {id, ok, result|error}
// result 为 JSON 字符串（rpc 导出回字符串，保数字/哈希
// 等大整数以字符串形态过桥不丢精度），本层解析回对象。
import init, { rpc } from './pkg/mynote_storage_worker.js';

const ready = (async () => {
  await init(new URL('./pkg/mynote_storage_worker_bg.wasm', import.meta.url));
})();

self.onmessage = async (e) => {
  const { id, cmd, payload } = e.data || {};
  try {
    await ready;
    const out = await rpc(cmd, payload || {});
    self.postMessage({ id, ok: true, result: JSON.parse(out) });
  } catch (err) {
    self.postMessage({ id, ok: false, error: String((err && err.message) || err) });
  }
};
