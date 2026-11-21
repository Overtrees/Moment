// 用原版自带 vendor/katex.min.js 在 Node 下渲染夹具，提取 KaTeX
// 自身的版面数（strut 高度/深度、frac-line 线宽、delimsizing 档位、
// array 列距 span 宽度）——原版渲染规格的 em 级量测，不依赖浏览器。
const katex = require('/home/hatch/workspace/Mynote/vendor/katex.min.js');
const OPTS = { output: 'htmlAndMathml', throwOnError: false, trust: false, strict: 'ignore', maxExpand: 100, maxSize: 20 };

function render(tex, display) {
  return katex.renderToString(tex, { ...OPTS, displayMode: !!display });
}
function strut(html) {
  const m = html.match(/class="strut" style="height:([\d.]+)em;vertical-align:(-?[\d.]+)em/);
  return m ? { h: +m[1], depth: -(+m[2]) } : null;
}
function show(label, tex, display) {
  const html = render(tex, display);
  const s = strut(html);
  console.log(`\n== ${label} :: ${tex} (display=${!!display})`);
  console.log('strut:', JSON.stringify(s), s ? 'total=' + (s.h + s.depth).toFixed(3) + 'em' : '');
  return html;
}

// 字号基线：普通括号与四档定界符
show('plain-paren', '(x)');
for (const cmd of ['big', 'Big', 'bigg', 'Bigg']) {
  const html = show(cmd, `\\${cmd}(`);
  const dm = html.match(/delimsizing (size\d|mult)/);
  console.log('delimclass:', dm && dm[1]);
  const inner = [...html.matchAll(/style="height:([\d.]+)em/g)].map((x) => +x[1]);
  console.log('innerHeights:', JSON.stringify(inner.slice(0, 6)));
}
// l/r/m 变体档位一致性抽查
for (const cmd of ['bigl', 'Bigl', 'biggl', 'Biggl', 'bigm', 'Biggm']) {
  const html = render(`\\${cmd}(`);
  const dm = html.match(/delimsizing (size\d|mult)/);
  console.log(cmd, '->', dm && dm[1], 'strut', JSON.stringify(strut(html)));
}
// 分式：frac-line 线宽（内联 style 或 CSS 类）
{
  const html = show('frac-inline', '\\frac{a+b}{2}');
  const fl = html.match(/frac-line"[^>]*style="([^"]*)"/) || html.match(/style="([^"]*)"[^>]*class="[^"]*frac-line/);
  console.log('frac-line style:', fl && fl[1]);
  const bw = html.match(/border-bottom-width:([\d.]+)em/);
  console.log('frac border-bottom-width:', bw && bw[1]);
  show('frac-display', '\\frac{a+b}{2}', true);
  show('dfrac', '\\dfrac{1}{2}');
  show('tfrac', '\\tfrac{1}{2}');
}
// 求和/积分限值
show('sum-display', '\\sum_{k=1}^{n} k^2', true);
show('sum-inline', '\\sum_{k=1}^{n} k^2');
show('int-display', '\\int_0^\\infty e^{-x^2}\\,dx', true);
show('int-inline', '\\int_0^\\infty e^{-x^2}\\,dx');
// 根号
show('sqrt', '\\sqrt{x^2+1}');
show('sqrt-tall', '\\sqrt{\\frac{1}{2}}');
// 矩阵与 array
{
  const html = show('pmatrix', '\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}', true);
  const cs = [...html.matchAll(/arraycolsep" style="width:([\d.]+)em/g)].map((x) => +x[1]);
  console.log('arraycolsep widths:', JSON.stringify(cs.slice(0, 4)));
  const rows = [...html.matchAll(/style="height:([\d.]+)em;vertical-align/g)].map((x) => +x[1]);
  console.log('vlist heights sample:', JSON.stringify(rows.slice(0, 8)));
}
{
  const html = show('array-hline', '\\begin{array}{|c|c|} \\hline a & b \\\\ \\hline c & d \\\\ \\hline \\end{array}', true);
  const lines = [...html.matchAll(/class="([^"]*(?:hline|arrayrule)[^"]*)"/g)].map((x) => x[1]);
  console.log('hline classes:', JSON.stringify(lines.slice(0, 6)));
  const bw = [...html.matchAll(/border[^;"]*/g)].map((x) => x[0]).slice(0, 6);
  console.log('borders:', JSON.stringify(bw));
}
// 行内基线：E=mc^2 与混排分式的 strut
show('inline-mixed', 'E=mc^2');
show('sqrt-inline', '\\sqrt{\\pi}');
