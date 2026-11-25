// SQLite spike 的 Dedicated Worker（阶段一脚手架）。
// OPFS 同步访问句柄只存在于 Dedicated Worker，SQLite 必须住在这里；
// 主线程只经 postMessage 桥调用，与阶段二的桥形态一致。
import init, { spike_write, spike_read } from './pkg/mynote_sqlite_spike.js';

const ready = (async () => {
  await init(new URL('./pkg/mynote_sqlite_spike_bg.wasm', import.meta.url));
})();

// 递归列 OPFS 内容（落点证据：路径 + 字节数）。
async function listOpfs() {
  const out = [];
  async function walk(dir, prefix) {
    for await (const [name, handle] of dir.entries()) {
      const path = prefix + name;
      if (handle.kind === 'file') {
        const f = await handle.getFile();
        out.push({ path, size: f.size });
      } else {
        await walk(handle, path + '/');
      }
    }
  }
  const root = await navigator.storage.getDirectory();
  await walk(root, '/');
  return out;
}

self.onmessage = async (e) => {
  const { id, cmd, tag, body } = e.data;
  try {
    await ready;
    let out;
    if (cmd === 'write') out = await spike_write(tag, body);
    else if (cmd === 'read') out = await spike_read();
    else throw new Error('unknown cmd ' + cmd);
    let opfs = null;
    try { opfs = await listOpfs(); } catch (err) { opfs = 'list failed: ' + err; }
    self.postMessage({ id, ok: true, out: JSON.parse(out), opfs });
  } catch (err) {
    self.postMessage({ id, ok: false, out: String((err && err.stack) || err) });
  }
};
