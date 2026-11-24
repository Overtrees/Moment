#!/usr/bin/env bash
# Mynote Rust 全量回归：一键跑 单元测试 + 构建 + 全部页面冒烟 + 专用探针（标题/拖拽）。
# 用法：bash run_all_tests.sh [--live]   (--live 打线上地址，只跑冒烟)
set -u
cd "$(dirname "$0")"
export PATH="$HOME/.cargo/bin:$PATH"
FAIL=0
step() { echo; echo "######## $1"; }

if [ "${1:-}" != "--live" ]; then
  step "cargo test (core + storage)"
  (cd rust && TMPDIR=$HOME/.tmp cargo test 2>&1 | tail -3) || FAIL=1
  step "build web"
  bash rust/apps/web/build.sh >/dev/null 2>&1 || { echo "BUILD FAILED"; exit 1; }
  step "verify rustweb（静态一致性 + 五包键集/残留文案/占位符/僵尸键门禁）"
  bash scripts/verify_rustweb.sh || FAIL=1
  python3 ~/workspace/mynote-ab/tools/serve_headers.py rust/apps/web/dist 8096 >/tmp/mynote-serve.log 2>&1 &
  SERVE_PID=$!
  trap 'kill $SERVE_PID 2>/dev/null' EXIT
  sleep 1
  BASE="http://localhost:8096/"
else
  BASE="https://mynote-rustweb.pages.dev/"
fi

for t in smoke-rustweb smoke-rustweb-w2 smoke-rustweb-w3 smoke-rustweb-i18n \
         smoke-rustweb-settings smoke-rustweb-list smoke-rustweb-editor2 smoke-rustweb-misc \
         smoke-rustweb-visual smoke-rustweb-highlight smoke-rustweb-blocks smoke-rustweb-tails smoke-rustweb-wiki smoke-rustweb-gaps smoke-rustweb-export; do
  step "$t"
  if node "$t.mjs" "$BASE" > "/tmp/$t.out" 2>&1; then
    grep -E "^✗" "/tmp/$t.out" && FAIL=1
    grep -qE "ERRORS: none" "/tmp/$t.out" || { echo "($t 未输出 ERRORS: none)"; }
    tail -2 "/tmp/$t.out"
    echo "PASS $t"
  else
    tail -5 "/tmp/$t.out"
    echo "FAIL $t"
    FAIL=1
  fi
done

# 专用探针（批 0 纳入门禁）：与冒烟同构（argv[2] 接 baseURL），
# 成功打印 ALL PASS、失败非零退出。守最脆弱的标题几何与
# 拖拽排序两面——此前只靠手动跑，现与 15 套冒烟同列。
for t in probe_title_geom probe_drag_sort probe_drag_pickup probe_drag_handle probe_bridge_input probe_batch3 probe_card_menu probe_list_cards probe_canvas_focus probe_lift_surface probe_title_dock probe_slash_anchor probe_root_dim probe_lightbox_page probe_attachment_open probe_menu_attach probe_page_transitions probe_undo_granularity probe_avatar_button probe_twocol_flow_span probe_weather probe_backup_fresh probe_delete_undo; do
  step "$t"
  if node "$t.mjs" "$BASE" > "/tmp/$t.out" 2>&1 && grep -q "ALL PASS" "/tmp/$t.out"; then
    tail -2 "/tmp/$t.out"
    echo "PASS $t"
  else
    tail -5 "/tmp/$t.out"
    echo "FAIL $t"
    FAIL=1
  fi
done

echo
if [ $FAIL -eq 0 ]; then echo "ALL GREEN"; else echo "SOME SUITES FAILED"; exit 1; fi
