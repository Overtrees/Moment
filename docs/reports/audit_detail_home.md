# 数值级对齐排查 · 线 3：首页（列表态 + 宽屏网格态）

只读审计（2026-11-26）。Web 真值出处：`rust/apps/web/styles/{tokens,base,editor}.css`、`rust/apps/web/src/{main,list}.rs`；原生出处：`rust/apps/ios/app/MomentApp.swift`（下称 Swift，行号为审计时点）。分类口径：缺陷待修 / 系统等价更优 / 已定案偏离（注明出处）。

令牌基准（tokens.css）：radius-32=32、radius-26=26、radius-28=28、radius-20=20、radius-999=999；字号 1rem=16px。

## 一、页眉（头像 / 标题区 / 紧凑胶囊）

| 元素 | Web 真值 | 原生现行 | 差值 | 分类 |
|---|---|---|---|---|
| 头像尺寸 | 72×72 圆（main.rs:2346 KeyedAvatar size:72；list.rs AvatarContent） | 72×72（Swift:9931 header 内 AvatarView(size: 72)） | 0 | 一致 |
| 头像回退（无自定义头像） | 玻璃 control 圆 + 恐龙线稿 size−8=64、底对齐（list.rs:1638-1652） | glassControl 圆 + DinoView(size×0.72≈51.8)、居中（Swift:9317-9319） | 恐龙 51.8 vs 64（−12.2），对齐居中 vs 底对齐 | 缺陷待修（小） |
| 头像滚动变换 | scale 1→0.55、ty 0→−4、opacity 1→0.7、p≥1 才 hidden（main.rs:2007-2013） | 同公式（Swift:9943-9949） | 0 | 一致 |
| 页眉结构与首卡静止位 | 流内：header-actions 高 44（base.css:62）+ 标题区 4+72+10=86（base.css:82-88）+ .container padding-top 46（base.css:116）→ 首卡顶 ≈ safe+176 | 悬浮页眉高 82（Swift:9963-9965）+ List 首行 spacer 88（Swift:9886-9888）→ 首卡顶 ≈ safe+88 | 首卡静止位高约 88pt | 已定案偏离（0.9.23 真悬浮结构定案）；注：纵向偏移量本身未见单独定案记录 |
| 紧凑小标题胶囊度量 | font 17/600、padding 6/16、radius 20、glass-overlay（base.css:89-111） | font 17 semibold、padding 6/16、radius 20（Swift:10647 起 CompactTitle） | 字重/内距/圆角 0；材质档：glassCard=content 档（ultraThin+0.74 染）vs Web overlay 档（0.84 白+blur28） | 缺陷待修（小，材质档） |
| 紧凑胶囊纵向位置 | fixed、top = safe+7、水平居中（base.css:92-94） | 页眉 ZStack 内垂直居中于 82 高框 → 胶囊顶 ≈ safe+7+(82−32)/2 ≈ safe+32 | 中心低约 25pt | 缺陷待修 |
| 紧凑呈现方式 | visibility/opacity 阈值切换、无 transition（base.css:106-108；main.rs:2011） | 阈值 + 180ms 淡入（Swift:9958-9962） | — | 已定案（系统惯例等价，0.9.23 落码注记） |

## 二、搜索胶囊

| 元素 | Web 真值 | 原生现行 | 差值 | 分类 |
|---|---|---|---|---|
| 触发态盒 | 高 66、padding 0/18、gap 6、radius 999、glass-control（base.css:307-317） | 高 66、padding 横 18、spacing 6、radius 999、glassControl（Swift:10014-10022） | 0 | 一致 |
| 触发图标 | SVG 20px（main.rs SearchCapsule search_markup(20)） | SF magnifyingglass 17（Swift:10011） | −3 | 缺陷待修（小） |
| 触发文字 | 14px、color = --glass-label-color（#48494f / 深 #d1d1d6）、letter-spacing −0.1（main.rs:225-228） | 14、T.textSecondary（#68686d / 深 #98989d）、无 tracking（Swift:10012-10013） | 色值不同（浅色深一档/深色浅一档） | 缺陷待修（小） |
| 展开态盒 | 高 66、padding 0/14、gap 8、radius 999、glass-**overlay**（base.css:296-305） | 高 66、padding 横 14、spacing 8、radius 999、glassCard=content 档（Swift:9990-9992） | 材质档 overlay vs content | 缺陷待修（小） |
| 展开图标 | SVG 18px（main.rs:190） | SF 15（Swift:9973） | −3 | 缺陷待修（小） |
| 输入框 | width 140、height 40、font 15（main.rs:205-213） | frame 140×40、font 15（Swift:9980-9981） | 0 | 一致 |
| 关闭/清除 | 无清除钮；失焦或 Esc 收起、query 保留（main.rs:196-203） | 额外 × 钮（清 query + 收起）；无失焦收起（Swift:9982-9990） | 行为面不同 | 系统等价更优（清除钮为原生增强；失焦不收起属可接受分叉） |
| 紧凑态 | opacity 1→0 + hidden（main.rs:184-186） | opacity 1−p（Swift:9951-9952） | 0 | 一致 |

## 三、行卡（窄屏列表态）

| 元素 | Web 真值 | 原生现行 | 差值 | 分类 |
|---|---|---|---|---|
| 文本卡圆角/材质 | radius 32、glass-content、0.5 边（base.css:155-167） | glassCard() 默认 radius 32、content 档、0.5 边、clipShape（Swift:8943、8880-8900） | 0 | 一致 |
| 文本卡内边距 | padding 14/16（base.css:156） | padding 横 16 纵 14（Swift:10505-10506） | 0 | 一致 |
| 卡内行距 | .item-left gap 4（base.css:169） | VStack spacing 4（Swift:10500） | 0 | 一致 |
| 卡间距 | .swipe-wrapper margin-bottom 6（base.css:126） | listRowInsets 上下各 3 → 卡间 6（Swift:10523-10524） | 0 | 一致 |
| 容器左右距 | .container padding 横 16（base.css:116） | listRowInsets leading/trailing 16 | 0 | 一致 |
| 标题字号/行数 | 16、单行省略（base.css:170-180） | 16、lineLimit 1（Swift:10540-10543） | 0 | 一致 |
| 标题字重 | 650（base.css:171；图片卡 .t 同为 650，base.css:200） | semibold=600（Swift:10541；图片卡 Swift:10485 同） | −50（全卡系统性：含新建卡、方卡标题、天气温度） | 缺陷待修（小，SF 可用 .semibold 近似但与 650 恒差一档） |
| 置顶圆点 | 6×6、--color-warning（base.css:187） | 6×6、T.warning（Swift:10536-10538） | 0 | 一致 |
| 标签 chip 字号/高 | font 10、line-height 18、padding 0/5、radius 999 → 高 18（list.rs:1164-1172 内联） | font 10、padding 横 6 纵 2 → 高 ≈16（Swift:10545-10551） | 高 −2、横距 +1 | 缺陷待修（小） |
| 标签 chip 色 | 文字 --glass-label-accent（#005bbb / 深 #72b7ff）+ glass-control 底 + 1px 边（base.css:341-345 .glass-tag） | 文字 T.textSecondary（灰）+ glassControlTint 底、无边（Swift:10546-10551） | 蓝字 vs 灰字 | 缺陷待修 |
| 标签布局 | 标题 max-width 60%，标签列 flex:1 右对齐、溢出隐藏（base.css:175-181） | 标签紧随标题左排、无 60% 上限（Swift:10532-10552） | 位置/截断口径不同 | 缺陷待修（小） |
| 标签个数 | scan 上限 3（list.rs:645）；窄屏全显（+.item-tag-more 窄屏 display:none，base.css:182） | prefix(3)（Swift:10544） | 0 | 一致（取数范围差见 §七） |
| meta 字号 | 12（base.css:188） | 12（metaFontSize，Swift:10577） | 0 | 一致（原生经 ScaledMetric 跟随 Dynamic Type——已定案口径） |
| meta 文形 | 文本卡「{ago}␣␣{摘要}」同段截断；图文卡「{ago} · {摘要}」（list.rs:1497、1394） | 同形（Swift:10561-10563） | 0（Web 为 NBSP×2、原生普通空格，视觉无差） | 一致 |
| 摘要截断长 | 文本卡 80 字 / 图文卡 60 字（list.rs:1224） | prefix(80/60)（Swift:9127） | 0 | 一致 |
| 时间格式 | time_ago 四分支（list.rs:922-955） | ago 四分支同构（Swift:9132-9158） | 0 | 一致 |
| 展开/收起钮形态 | .expand-btn：玻璃 control 药丸、font 11、padding 4/10、radius 14、1px 边、色 --glass-label-color，位于 meta 行右端（base.css:199-205） | 纯文字钮：font 12、accent 蓝、无底无边，紧随 meta 文本之后（Swift:10564-10575） | 字号 +1、形态与位置全差 | 缺陷待修 |
| 图文卡封面 | aspect 16/9、上圆角 32、下 0（base.css:197） | aspectRatio 16/9 + 整卡 clipShape radius 32（Swift:10473-10476、glassCard clip） | 0 | 一致 |
| 图文卡体 | padding 10/16/12（base.css:198）；标题 15（base.css:200） | padding 横 16 上 10 下 12（Swift:10490-10492）；标题 15（Swift:10485） | 0 | 一致 |
| 左滑动作 | 自绘双钮 68×44、radius 22、区宽 168（base.css:127-153） | 系统 swipeActions（Swift:10525-10543） | — | 已定案（左滑系统实现） |

## 四、分组头与组间间距（窄屏）

| 元素 | Web 真值 | 原生现行 | 差值 | 分类 |
|---|---|---|---|---|
| 分组头字号/字重/色 | 14 / 600 / --text-secondary、letter-spacing 0.3、uppercase（editor.css:139-146） | 14 / semibold / T.textSecondary、无 tracking（Swift:10447-10450） | tracking −0.3（中文标签无感、数字/年份标签略差） | 缺陷待修（微） |
| 分组头内距 | padding 24/4/6（editor.css:140）；:first-child 时 top 4（editor.css:147-149） | listRowInsets top 24、leading 20（=容器 16+4）、bottom 6（Swift:10454-10455） | 0（组头本体口径一致；inter-group 合成见下行） | 一致 |
| 组间合成距 | 前组 .list-group margin-bottom 24 + 组头 top 4 → 文本上 28、下 6 | 前卡 bottom inset 3 + 组头 top 24 → 文本上 27、下 6+卡 top 3=9 | 上 −1、下 +3 | 缺陷待修（微） |
| 图/文子列间隔 | img 组 margin-bottom 24 + .gap-16 高 16 = 40（base.css:119-125、206；main.rs:2496-2498） | Color.clear 高 16 行 + 两侧卡 inset 3+3 = 22（Swift:9805-9810） | −18 | 缺陷待修 |
| 列表底部留白 | .container padding-bottom = 20 + safe（base.css:116） | 无显式底距（末行 bottom inset 3） | −17 | 缺陷待修（小） |

## 五、新建卡与天气（窄屏）

| 元素 | Web 真值 | 原生现行 | 差值 | 分类 |
|---|---|---|---|---|
| 新建卡盒 | 同 .list-item（padding 14/16、radius 32） | 同行卡口径（Swift:10434-10436） | 0 | 一致 |
| 新建标题 | 「新建笔记」16 / 600 / --text-secondary（base.css:183-186 .new-card-title） | 16 / semibold / textSecondary（Swift:10416-10418） | 0 | 一致 |
| 新建副行 | 「现在␣␣点击记录你的瞬间」12（list.rs:1556-1558） | 同文 12（Swift:10419-10421） | 0 | 一致 |
| 天气块位置距 | .list-item gap 12 + .newcard-weather padding-left 12 → 与左列隔 24（base.css:161、192） | HStack spacing 10、无额外左距（Swift:10413） | −14 | 缺陷待修（小） |
| 天气温度 | 16 / 650 / letter-spacing −0.5、line-height 1.1（base.css:193） | 16 / semibold、无 tracking（Swift:10428-10430） | 字重 −50、无字距 | 缺陷待修（小） |
| 天气城/况行 | 12、line-height 1.2、与温度 gap 4（base.css:192-194） | 12、VStack spacing 2（Swift:10426） | gap −2 | 缺陷待修（微） |
| 天气文形 | 「{城市} {状况}」（list.rs:1520-1528，城市经 to_cn） | 「{city} {text}」空格拼（Swift:10431-10434）；城市名走系统地理编码 | 0 | 一致（城市名来源为已定案原生更优口径，0.8.6） |

## 六、撤销 toast 与 notice 行

| 元素 | Web 真值 | 原生现行 | 差值 | 分类 |
|---|---|---|---|---|
| 撤销条形态 | 全宽条：left/right 16、bottom = safe+16、radius 28、padding 14/16、gap 10、glass-overlay（base.css:620-630） | 居中胶囊：radius 999、padding 横 18 纵 10、spacing 14、glassCard content 档、bottom 距 14（Swift:10038-10053） | 形态/度量全面不同 | 缺陷待修 |
| 撤销条图标 | del SVG 19px（main.rs:2661） | 无图标（Swift:10039-10047） | 缺失 | 缺陷待修 |
| 撤销条文字 | 「备忘已删除」14 / 500 / line-height 1.35（base.css:642） | 14 / 常规字重（Swift:10040-10042） | 字重 −100 | 缺陷待修（小） |
| 撤销钮 | 14 / 600 / accent、padding 6/10（base.css:636） | 14 / semibold / accent（Swift:10043-10046） | 近似（缺内距盒） | 缺陷待修（微，并入形态行） |
| 撤销条进场 | toastSlideUpBar 220ms 弹簧（上滑 24 + scale .94→1 + 淡入）（base.css:631-632） | move(.bottom)+opacity、spring 0.28（Swift:9822-9824、10055-10057） | 近似 | 系统等价更优（近似等价） |
| notice 行 | Web 首页无对应物 | 12px 次级色行（Swift:9899-9908） | — | 已定案（原生自救/诊断通道呈现面，诊断批 B/C 定案） |

## 七、摘要/标签取数（内容口径）

| 元素 | Web 真值 | 原生现行 | 差值 | 分类 |
|---|---|---|---|---|
| 摘要取数范围 | 遍历**全部** paragraph 块、各取首个子节点文本、空格拼接后剥语法截断（list.rs:620-660 summarize_uncached） | 仅**首个** paragraph 块的首个文本子节点（Swift:9034-9049 firstParaText；summary Swift:9090） | 首段为空/纯标签时：Web 仍有后段文本，原生回退标签名或「无更多文本」 | 缺陷待修 |
| 标签取数范围 | 全段落 scan_tags、上限 3（list.rs:631-645） | 仅首段扫描、上限 3（Swift:9053-9081） | 后段标签不显 | 缺陷待修（与上行同根） |
| 标签文形 | tag 串含「#」原样渲染（list.rs:32） | 存储不含「#」、渲染拼「#」（Swift:10546） | 0（显示同形） | 一致 |

## 八、空状态

| 元素 | Web 真值 | 原生现行 | 差值 | 分类 |
|---|---|---|---|---|
| 空状态内距 | padding 56/24、gap 8（editor.css:132） | padding 纵 48（Swift:10630） | 纵 −8 | 缺陷待修（小） |
| 空状态图标 | SVG 44、opacity .55（editor.css:135；list.rs:1581） | SF Symbol 44、opacity .55（Swift:10615-10617） | 字形为系统符号替代 | 系统等价更优 |
| 空状态标题 | 16 / 600（editor.css:136） | 16 / semibold（Swift:10618-10620） | 0 | 一致 |
| 空状态说明 | 13、line-height 1.55、max-width 280（editor.css:137） | 13、无行高/无最大宽（Swift:10621-10623） | 行高与限宽缺失 | 缺陷待修（小） |
| 空状态动作钮 | padding 9/22、radius 999、accent 底白字、14/600、margin-top 10（editor.css:138） | padding 横 16 纵 8、14 semibold、top 距 6（Swift:10624-10629） | 横 −6、纵 −1、上距 −4（与 gap 合成 18 vs 14） | 缺陷待修（小） |
| 加载失败说明文 | 「本地数据读取出错。重新加载试试；若反复失败，可在设置页查看诊断日志」（zh-CN empty.load_error_sub） | 「本地数据读取出错，重新加载试试」（Swift:10590） | 文案截短、丢诊断指引 | 缺陷待修（小） |
| 搜索零结果说明文 | 「换个关键词试试，或清除搜索查看全部备忘」（zh-CN empty.search_sub） | 「换个关键词试试，或清除搜索查看全部」（Swift:10597） | 尾缺「备忘」 | 缺陷待修（微） |
| 空库说明文 | 「暂无笔记，点击上方新建」（zh-CN list.empty_tip） | 同文（Swift:10603） | 0 | 一致 |
| 网格态空状态 | 同一 EmptyState 组件（宽屏下 grid-column 1/-1，base.css:403） | gridEmpty：标题 15、说明 12、padding 纵 40、**无动作钮**（Swift:10149-10166） | 标题 −1、说明 −1、内距 −16、动作钮缺失；且与原生窄屏 emptyRow 自身不一致 | 缺陷待修 |

## 九、宽屏网格态

| 元素 | Web 真值 | 原生现行 | 差值 | 分类 |
|---|---|---|---|---|
| 网格判定 | min-width 768 或（横屏且 max-height 560）（base.css:371） | 宽 ≥768 或（宽>高且高 ≤560）（Swift:9861-9863） | 0 | 一致 |
| 列数 | 3 列；≥1280 四列（base.css:374、565-568） | homeCols 3 / ≥1280 为 4（Swift:9870-9871） | 0 | 一致 |
| 网格 gap | 14（base.css:377） | LazyVGrid spacing 14（行列同）（Swift:10077、10116-10118） | 0 | 一致 |
| 容器宽/边距 | max-width 1240 居中、padding 横 24（base.css:378-382） | frame maxWidth 1240、padding 横 24（Swift:10107-10108） | 0 | 一致 |
| 方卡比例/圆角 | aspect 1/1、radius 26（base.css:404-414） | aspectRatio 1、glassCard radius 26（Swift:10247、10210） | 0 | 一致 |
| 方卡内边距 | padding 14、内部 gap 8（base.css:419-427） | padding 14、VStack spacing 8（Swift:10282-10310） | 0 | 一致 |
| 方卡标题 | 16 / 650、line-height 1.35、clamp 3（base.css:447-458） | 16 / semibold、lineSpacing 5.6（合成行高 21.6=1.35）、lineLimit 3（Swift:10295-10301） | 字重 −50、行高/行数 0 | 缺陷待修（小，仅字重） |
| 方卡置顶点 | 7×7、margin-top 7（base.css:460-464） | 7×7、padding top 7（Swift:10287-10290） | 0 | 一致 |
| 方卡标签 | font 11、line-height 20、padding 0/7 → 高 20、gap 6、只显前 2 + 「+N」（base.css:474-495） | font 11、padding 横 7 纵 2.5 → 高 ≈18.2、spacing 6、前 2 + 「+N」（Swift:10364-10384） | 高 −1.8；文字色灰 vs Web accent 蓝（同 §三 chip 色行） | 缺陷待修（小） |
| 方卡 meta | 12、line-height 1.4；摘要 span clamp 3、line-height 1.45（base.css:496-507） | 12、lineSpacing 5.4（行高 17.4=1.45）、lineLimit 3（Swift:10304-10307） | 0 | 一致 |
| 图文方卡封面 | flex 1 填充、radius 26 26 0 0（base.css:513-522） | GeometryReader 填充 + 整卡 clip radius 26（Swift:10320-10328） | 0 | 一致 |
| 图文方卡体 | 高 78、padding 10/12（base.css:523-529） | 高 78、padding 横 12 纵 10（Swift:10347-10349） | 0 | 一致 |
| 图文方卡标题 | 13 / 650、line-height 1.25、单行省略（base.css:531-539） | 13 / semibold、lineLimit 1（Swift:10331-10335） | 字重 −50 | 缺陷待修（小） |
| 图文方卡标签 | font 10、line-height 18、padding 0/6、max-width calc(50%−2px)（base.css:546-556） | font 10、padding 横 6 纵 1 → 高 ≈14（Swift:10366-10376 small 分支） | 高 −4 | 缺陷待修（小） |
| 图文方卡 meta | 12、line-height 1.35（base.css:557） | 12、无 lineSpacing（默认 ≈1.2）（Swift:10340-10343） | 行高 −0.15 档 | 缺陷待修（微） |
| 幽灵叠卡 | ::before scale .94 / y+7 / opacity .68；::after scale .97 / y+4 / opacity .86；radius 26（base.css:573-590） | 同值两层（Swift:10216-10239） | 0 | 一致（呈现方式为已定案 contextMenu 配套） |
| 网格组头 | 13 / 600、padding 8/2/0、margin-bottom −6、色 --glass-label-color、line-height 1.25、letter-spacing .02em（base.css:390-401） | 13 / semibold、色 textSecondary、padding top 8、无负下距（Swift:10089-10095） | 下合成距 14 vs 8（+6）；色值差（同搜索触发行） | 缺陷待修（小） |
| 网格新建方卡 | 同 .list-item 方卡化：标题左上、天气经 last-child 规则排**底部整行**：flex row、space-between（温度左、城市右同行）（base.css:508-512 + 192-194） | 标题/副行左上、天气 VStack 右下两行（温度上、城市下、右对齐）（Swift:10167-10205） | 天气排布：同行两端 vs 右下两行 | 缺陷待修 |
| 网格首行顶距 | .container padding-top 46（宽屏未改）（base.css:116、372-383） | spacer 88（Swift:10065-10075） | 同 §一页眉结构行（悬浮口径） | 已定案偏离（0.9.23） |
| ≥1280 页眉约束 | 头部同受 1240 居中约束：标题区左右内距与搜索 right 取 (100vw−1240)/2（base.css:565-580，W-4 有意偏离原版的定案） | 页眉恒 padding 横 20、与网格 1240 列不对齐（Swift:9963） | iPad 12.9 横屏（1366）时差 ≈43pt | 缺陷待修 |
| 网格底部距 | padding-bottom 20 + safe（base.css:116） | padding bottom 20（Swift:10109） | 0 | 一致 |

## 汇总

- 条目总数：86（一致 39 / 缺陷待修 39 / 系统等价更优 3 / 已定案偏离 5）。
- 系统性小差（多行共因）：标题类字重 Web 650 vs 原生 semibold 600（行卡/方卡/图文方卡/新建卡/天气温度共 5 处）；标签 chip 文字色 Web accent 蓝 vs 原生灰（窄屏行卡 + 两类方卡共 3 处）；SF 图标比 Web SVG 小 3px（搜索两态）。
