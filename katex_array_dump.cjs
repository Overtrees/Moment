// 深挖 KaTeX array/pmatrix 的 HTML 结构：行距、列距、hline 画法。
const katex = require('/home/hatch/workspace/Mynote/vendor/katex.min.js');
const OPTS = { output: 'html', throwOnError: false, trust: false, strict: 'ignore', maxExpand: 100, maxSize: 20 };

function strip(html) {
  // 只留标签骨架 + style，去掉 MathML 与文本噪音
  return html
    .replace(/<math[\s\S]*?<\/math>/g, '')
    .replace(/></g, '>\n<');
}
const pm = katex.renderToString('\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}', { ...OPTS, displayMode: true });
console.log('===== PMATRIX =====');
console.log(strip(pm).split('\n').filter((l) => /vlist|arraycolsep|strut|height|margin/.test(l)).slice(0, 40).join('\n'));

const ar = katex.renderToString('\\begin{array}{|c|c|} \\hline a & b \\\\ \\hline c & d \\\\ \\hline \\end{array}', { ...OPTS, displayMode: true });
console.log('\n===== ARRAY-HLINE =====');
console.log(strip(ar).split('\n').filter((l) => /hline|vlist|arraycolsep|strut|border|height/.test(l)).slice(0, 50).join('\n'));

const cs = katex.renderToString('\\begin{cases} a & x>0 \\\\ b & x<0 \\end{cases}', { ...OPTS, displayMode: true });
console.log('\n===== CASES strut =====');
console.log((cs.match(/class="strut" style="[^"]*"/) || ['none'])[0]);

// 单行 array 的行高基线（1 行）与两行差分推行距
const one = katex.renderToString('\\begin{array}{c} a \\end{array}', { ...OPTS, displayMode: true });
const two = katex.renderToString('\\begin{array}{c} a \\\\ b \\end{array}', { ...OPTS, displayMode: true });
const s1 = one.match(/class="strut" style="height:([\d.]+)em;vertical-align:(-?[\d.]+)em/);
const s2 = two.match(/class="strut" style="height:([\d.]+)em;vertical-align:(-?[\d.]+)em/);
console.log('\narray 1 row strut:', s1 && s1.slice(1), ' 2 rows strut:', s2 && s2.slice(1));
// pmatrix 1 行 vs 2 行
const p1 = katex.renderToString('\\begin{pmatrix} a \\end{pmatrix}', { ...OPTS, displayMode: true });
const sp1 = p1.match(/class="strut" style="height:([\d.]+)em;vertical-align:(-?[\d.]+)em/);
console.log('pmatrix 1 row strut:', sp1 && sp1.slice(1));
// 三列 array 的 colsep span 个数（定列距构成）
const three = katex.renderToString('\\begin{array}{ccc} a & b & c \\end{array}', { ...OPTS, displayMode: true });
console.log('3-col arraycolsep count:', (three.match(/arraycolsep/g) || []).length,
  'widths:', [...three.matchAll(/arraycolsep" style="width:([\d.]+)em/g)].map((x) => x[1]).join(','));
const pm3 = katex.renderToString('\\begin{pmatrix} a & b & c \\end{pmatrix}', { ...OPTS, displayMode: true });
console.log('pmatrix 3-col arraycolsep count:', (pm3.match(/arraycolsep/g) || []).length);

// 行基线偏移（vlist 子 span 的 top 值）
console.log('\n===== VLIST TOPS (2-row array) =====');
console.log([...two.matchAll(/style="top:(-?[\d.]+)em"/g)].map((x) => x[1]).join(', '));
console.log('===== VLIST TOPS (pmatrix) =====');
console.log([...pm.matchAll(/style="top:(-?[\d.]+)em"/g)].map((x) => x[1]).join(', '));
const sm = katex.renderToString('\\begin{smallmatrix} a & b \\\\ c & d \\end{smallmatrix}', { ...OPTS, displayMode: true });
console.log('smallmatrix colseps:', [...sm.matchAll(/arraycolsep" style="width:([\d.]+)em/g)].map((x) => x[1]).join(','),
  'strut:', (sm.match(/class="strut" style="([^"]*)"/) || [])[1]);
const al = katex.renderToString('\\begin{aligned} a &= b \\\\ c &= d \\end{aligned}', { ...OPTS, displayMode: true });
console.log('aligned strut:', (al.match(/class="strut" style="([^"]*)"/) || [])[1],
  'tops:', [...al.matchAll(/style="top:(-?[\d.]+)em"/g)].map((x) => x[1]).join(', '));
const ga = katex.renderToString('\\begin{gather} a=b \\\\ c=d \\end{gather}', { ...OPTS, displayMode: true });
console.log('gather strut:', (ga.match(/class="strut" style="([^"]*)"/) || [])[1]);
