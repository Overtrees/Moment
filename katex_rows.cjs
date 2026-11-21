// 行距推导：1/2/3 行同内容 strut 总高差分 = 行距 pitch。
const katex = require('/home/hatch/workspace/Mynote/vendor/katex.min.js');
const OPTS = { output: 'html', throwOnError: false, trust: false, strict: 'ignore', maxExpand: 100, maxSize: 20 };
function total(tex, display = true) {
  const html = katex.renderToString(tex, { ...OPTS, displayMode: display });
  const m = html.match(/class="strut" style="height:([\d.]+)em;vertical-align:(-?[\d.]+)em/);
  return m ? (+m[1] - +m[2]).toFixed(3) : null;
}
for (const [name, mk] of [
  ['array', (rows) => `\\begin{array}{c} ${rows.join(' \\\\ ')} \\end{array}`],
  ['pmatrix', (rows) => `\\begin{pmatrix} ${rows.join(' \\\\ ')} \\end{pmatrix}`],
  ['aligned', (rows) => `\\begin{aligned} ${rows.map((r) => r + ' &= x').join(' \\\\ ')} \\end{aligned}`],
  ['cases', (rows) => `\\begin{cases} ${rows.join(' \\\\ ')} \\end{cases}`],
  ['matrix', (rows) => `\\begin{matrix} ${rows.join(' \\\\ ')} \\end{matrix}`],
]) {
  const t1 = total(mk(['a']));
  const t2 = total(mk(['a', 'b']));
  const t3 = total(mk(['a', 'b', 'c']));
  console.log(name, 'T1=', t1, 'T2=', t2, 'T3=', t3, 'pitch=', (t2 - t1).toFixed(3), '/', (t3 - t2).toFixed(3));
}
// 带分式的行（内容更高时 pitch 是否随内容走）
console.log('array frac rows T2=', total('\\begin{array}{c} \\frac{1}{2} \\\\ \\frac{1}{2} \\end{array}'));
// \\[dim] 显式行距
console.log('array \\\\[0.5em] T2=', total('\\begin{array}{c} a \\\\[0.5em] b \\end{array}'));
console.log('array \\\\[6pt] T2=', total('\\begin{array}{c} a \\\\[6pt] b \\end{array}'));
