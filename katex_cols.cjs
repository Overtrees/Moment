// cases / aligned / gather 的列距构成（arraycolsep 个数与宽度、& 列结构）。
const katex = require('/home/hatch/workspace/Mynote/vendor/katex.min.js');
const OPTS = { output: 'html', throwOnError: false, trust: false, strict: 'ignore', maxExpand: 100, maxSize: 20 };
function colseps(label, tex) {
  const html = katex.renderToString(tex, { ...OPTS, displayMode: true });
  const cs = [...html.matchAll(/arraycolsep" style="width:([\d.]+)em/g)].map((x) => +x[1]);
  const strut = (html.match(/class="strut" style="([^"]*)"/) || [])[1];
  console.log(label, 'colseps:', JSON.stringify(cs), 'strut:', strut);
}
colseps('cases', '\\begin{cases} a & x>0 \\\\ b & x<0 \\end{cases}');
colseps('cases-3col', '\\begin{cases} a & x & y \\\\ b & u & v \\end{cases}');
colseps('aligned', '\\begin{aligned} a &= b \\\\ c &= d \\end{aligned}');
colseps('aligned-2pair', '\\begin{aligned} a &= b & c &= d \\\\ e &= f & g &= h \\end{aligned}');
colseps('gather', '\\begin{gather} a=b \\\\ c=d \\end{gather}');
colseps('array-lcr', '\\begin{array}{lcr} a & b & c \\\\ d & e & f \\end{array}');
colseps('smallmatrix', '\\begin{smallmatrix} a & b \\\\ c & d \\end{smallmatrix}');
colseps(' subarray', '\\begin{subarray}{c} a \\\\ b \\end{subarray}');
// aligned 的列间是否有额外 \qquad 类间距：量第二对与第一对之间的 span
const al2 = katex.renderToString('\\begin{aligned} a &= b & c &= d \\end{aligned}', { ...OPTS, displayMode: true });
console.log('aligned-2pair mspace widths:', [...al2.matchAll(/mspace" style="margin-right:([\d.]+)em/g)].map((x) => x[1]).join(','),
  'kern:', [...al2.matchAll(/style="margin-left:(-?[\d.]+)em/g)].map((x) => x[1]).slice(0, 6).join(','));
