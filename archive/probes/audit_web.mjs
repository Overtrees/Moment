import { chromium } from 'playwright-core';
const exe = process.env.HOME + '/.cache/ms-playwright/chromium_headless_shell-1255/chrome-headless-shell-linux64/chrome-headless-shell';
const browser = await chromium.launch({ executablePath: exe });
const page = await browser.newPage({ viewport: { width: 420, height: 900 } });
page.on('pageerror', e => console.log('PAGEERROR', String(e).slice(0, 120)));
await page.goto('http://127.0.0.1:8096/Moment.html', { waitUntil: 'networkidle' });
await page.waitForTimeout(3500);
const now = Date.now();
await page.evaluate(async (now) => {
  const doc1 = [
    {id:'d1p1', type:'paragraph', children:[{text:'今天去了 UCCA 的「非物质再现」展。光线透过亚克力板投射在墙上的影子会随着人的移动变化，站久了会忘记时间。'}]},
    {id:'d1p2', type:'paragraph', children:[{text:'想起上周看的书里那句话：==所谓的边界，只是我们还没习惯的过渡带=='}]},
    {id:'d1h', type:'heading', attrs:{level:2}, children:[{text:'实用信息'}]},
    {id:'d1p3', type:'paragraph', children:[{text:'地址：798 艺术区 UCCA。票价 100 元。'}]},
    {id:'d1m', type:'musicCard', url:'https://open.spotify.com/track/4uLU6hMCjMI75M1A2tKUQC', status:'ready', meta:{title:'Never Gonna Give You Up', subtitle:'Rick Astley', source:'Spotify', type:'music'}}
  ];
  const doc2 = [
    {id:'d2t1', type:'todo', attrs:{checked:true}, children:[{text:'厨房插座至少留 6 个，台面要带开关'}]},
    {id:'d2t2', type:'todo', attrs:{checked:true}, children:[{text:'卫生间防水刷到 1.8m，闭水试验做满 48h'}]},
    {id:'d2t3', type:'todo', attrs:{checked:false}, children:[{text:'地板和瓷砖之间用极窄收边条'}]}
  ];
  const db = await new Promise((res, rej) => { const r = indexedDB.open('MemosDB'); r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); });
  const tx = db.transaction('memos', 'readwrite');
  const store = tx.objectStore('memos');
  store.put({id:'demo_exhibit', title:'周末看展记录', doc: doc1, createdAt: now - 86400000, updatedAt: now - 3600000, pinned:false});
  store.put({id:'demo_home', title:'装修踩坑清单', doc: doc2, createdAt: now - 2*86400000, updatedAt: now - 7200000, pinned:true});
  await new Promise((res) => { tx.oncomplete = res; });
}, now);
await page.reload({ waitUntil: 'networkidle' });
await page.waitForTimeout(3500);
await page.screenshot({ path: '/tmp/audit-web-list.png' });
await page.mouse.click(200, 300);
await page.waitForTimeout(2500);
await page.screenshot({ path: '/tmp/audit-web-editor.png' });
await browser.close();
