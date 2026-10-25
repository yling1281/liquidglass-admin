#!/usr/bin/env bash
# 端到端接口验证：对 App 工程里定义的每个接口，用真实服务跑一遍。
# 用法： bash scripts/verify_api.sh
#
# 验证的是「App 里写的路径 / 方法 / 参数名 / 编码方式」与真实服务一致，
# 而不是服务本身可用。

set -u
BASE="https://z7k2m9xq.lingyan.cyou/prod-api"
SHOP="https://www.siyecaogf.cn"
SHOPADMIN="https://lgk3f9x2p.lingyan.cyou"
PASS=0
FAIL=0

# ⚠️ 必须写成函数，不能写成 `CURL="curl ... --noproxy *"` 再 `$CURL` 调用 ——
# 未加引号的 `$CURL` 会走字段分割 + 路径名展开，`*` 被展开成当前目录的文件名，
# 于是 curl 拿到一堆乱七八糟的「URL」，测出来的结果全是假的
# （实测踩过：Location 变成 https://readme.md/，/login 报 upstream connect failed）。
CURL() { curl -s -m 20 --noproxy '*' "$@"; }

check() {
  local label="$1" expect="$2" actual="$3"
  if echo "$actual" | grep -q "$expect"; then
    echo "  ✅ $label"
    PASS=$((PASS+1))
  else
    echo "  ❌ $label"
    echo "      期望含: $expect"
    echo "      实际: $(echo "$actual" | head -c 220)"
    FAIL=$((FAIL+1))
  fi
}

echo "=== 1. 卡密后台 · 登录 ==="
LOGIN=$(CURL -X POST "$BASE/login" -H "Content-Type: application/json" \
  -d '{"username":"lingyan","password":"lingyan@2026"}')
check "POST /login 返回 code 200" '"code": *200' "$LOGIN"
TOKEN=$(echo "$LOGIN" | sed -n 's/.*"token": *"\([^"]*\)".*/\1/p')
if [ -z "$TOKEN" ]; then echo "  ❌ 未能取到 token，后续跳过"; exit 1; fi
echo "  token: ${TOKEN:0:30}..."

AUTH=(-H "Authorization: Bearer $TOKEN")

echo ""
echo "=== 2. 卡密后台 · 用户信息与路由 ==="
INFO=$(CURL "${AUTH[@]}" "$BASE/getInfo")
check "GET /getInfo 权限点" 'card:key:list' "$INFO"
check "GET /getInfo 用户名" '"userName": *"lingyan"' "$INFO"
ROUTERS=$(CURL "${AUTH[@]}" "$BASE/getRouters")
check "GET /getRouters 含卡密中心" '卡密中心' "$ROUTERS"

echo ""
echo "=== 3. 卡密管理 · 列表 ==="
LIST=$(CURL "${AUTH[@]}" "$BASE/card/key/list?pageNum=1&pageSize=5")
check "GET /card/key/list 返回 rows" '"rows"' "$LIST"
check "GET /card/key/list 返回 total" '"total"' "$LIST"
check "行含 cardNo" '"cardNo"' "$LIST"
check "行含 statusName" '"statusName"' "$LIST"
check "行含 productCode" '"productCode"' "$LIST"
check "行含 channelCode" '"channelCode"' "$LIST"
check "行含 orderNo" '"orderNo"' "$LIST"
check "行含 bindDevice" '"bindDevice"' "$LIST"
check "行含 expireAt" '"expireAt"' "$LIST"

echo ""
echo "=== 4. 卡密管理 · 状态筛选 ==="
F0=$(CURL "${AUTH[@]}" "$BASE/card/key/list?pageNum=1&pageSize=5&status=0")
check "GET /card/key/list?status=0" '"rows"' "$F0"
F1=$(CURL "${AUTH[@]}" "$BASE/card/key/list?pageNum=1&pageSize=5&status=1")
check "GET /card/key/list?status=1" '"rows"' "$F1"
F2=$(CURL "${AUTH[@]}" "$BASE/card/key/list?pageNum=1&pageSize=5&status=2")
check "GET /card/key/list?status=2" '"rows"' "$F2"

echo ""
echo "=== 5. 卡密管理 · 搜索（keyword 同时给 cardNo 和 batchNo）==="
FIRSTCARD=$(echo "$LIST" | sed -n 's/.*"cardNo": *"\([^"]*\)".*/\1/p' | head -1)
SEARCH=$(CURL "${AUTH[@]}" "$BASE/card/key/list?pageNum=1&pageSize=5&cardNo=$FIRSTCARD&batchNo=$FIRSTCARD")
check "GET /card/key/list?cardNo=&batchNo=" '"rows"' "$SEARCH"

echo ""
echo "=== 6. 卡密管理 · 生成（真实创建 1 张）==="
GEN=$(CURL "${AUTH[@]}" -X POST "$BASE/card/key/generate" -H "Content-Type: application/json" \
  -d '{"batchName":"verify-script","productId":"LG-APP","count":1,"durationDays":30}')
check "POST /card/key/generate 成功" '"code": *200' "$GEN"
check "返回 batchNo" '"batchNo"' "$GEN"
check "返回 successCount" '"successCount"' "$GEN"

echo ""
echo "=== 7. 卡密管理 · 状态变更 / 解冻 / 解封 / 删除（用不存在的 id）==="
ST=$(CURL "${AUTH[@]}" -X PUT "$BASE/card/key/status" -H "Content-Type: application/json" \
  -d '{"ids":[-1],"status":3,"reason":"probe"}')
check "PUT /card/key/status 返回 success" '"success"' "$ST"
check "skipped 是对象数组" '"cardNo"' "$ST"
UNF=$(CURL "${AUTH[@]}" -X PUT "$BASE/card/key/unfreeze" -H "Content-Type: application/json" -d '{"ids":[-1]}')
check "PUT /card/key/unfreeze" '"success"' "$UNF"
UNB=$(CURL "${AUTH[@]}" -X PUT "$BASE/card/key/unban" -H "Content-Type: application/json" -d '{"ids":[-1]}')
check "PUT /card/key/unban" '"success"' "$UNB"
DEL=$(CURL "${AUTH[@]}" -X DELETE "$BASE/card/key/999999")
check "DELETE /card/key/{id}" '"success"' "$DEL"

echo ""
echo "=== 8. 卡密管理 · 操作记录 ==="
REC=$(CURL "${AUTH[@]}" "$BASE/card/record/list?pageNum=1&pageSize=5")
check "GET /card/record/list 返回 rows" '"rows"' "$REC"
check "行含 action" '"action"' "$REC"
check "行含 source" '"source"' "$REC"
check "行含 operator" '"operator"' "$REC"

echo ""
echo "=== 9. 对接情况 · 发卡渠道 ==="
CH=$(CURL "${AUTH[@]}" "$BASE/card/channel/list")
check "GET /card/channel/list 返回 rows" '"rows"' "$CH"
check "含 channelName" '"channelName"' "$CH"
check "含 enabled" '"enabled"' "$CH"
check "含 remark" '"remark"' "$CH"

echo ""
echo "=== 10. 店铺管理 · 商城分类（GET, query）==="
CAT=$(CURL "$SHOP/user/api/index/data" -H "Accept: application/json" -H "X-Requested-With: XMLHttpRequest")
check "GET /user/api/index/data" '"code": *200' "$CAT"
check "分类含 name" '"name"' "$CAT"
check "分类含 commodity_count" '"commodity_count"' "$CAT"
check "分类含 owner" '"owner"' "$CAT"

echo ""
echo "=== 11. 店铺管理 · 商品列表（GET, query）==="
COMM=$(CURL "$SHOP/user/api/index/commodity" -H "Accept: application/json" -H "X-Requested-With: XMLHttpRequest")
check "GET /user/api/index/commodity" '"code": *200' "$COMM"
check "商品含 price" '"price"' "$COMM"
check "商品含 user_price" '"user_price"' "$COMM"
check "商品含 delivery_way" '"delivery_way"' "$COMM"
check "商品含 stock" '"stock"' "$COMM"
check "商品含 order_sold" '"order_sold"' "$COMM"
check "商品含 recommend" '"recommend"' "$COMM"
check "商品含 category_id" '"category_id"' "$COMM"
check "商品含 seckill_active" '"seckill_active"' "$COMM"

echo ""
echo "=== 12. 店铺管理 · 库存与估值（POST, form 编码 —— 关键！）==="
STOCK=$(CURL -X POST "$SHOP/user/api/index/stock" \
  -H "Content-Type: application/x-www-form-urlencoded" -d "item_id=5")
check "POST /user/api/index/stock" '"code": *200' "$STOCK"
check "返回 stock" '"stock"' "$STOCK"
check "返回 stock_state" '"stock_state"' "$STOCK"
VAL=$(CURL -X POST "$SHOP/user/api/index/valuation" \
  -H "Content-Type: application/x-www-form-urlencoded" -d "item_id=5&quantity=1")
echo "     valuation 原始返回: $(echo "$VAL" | head -c 120)"

echo ""
echo "=== 13. 店铺管理 · 订单查询与发货内容（POST, form）==="
QRY=$(CURL -X POST "$SHOP/user/api/index/query" \
  -H "Content-Type: application/x-www-form-urlencoded" -d "keywords=__probe__&page=1&limit=10")
check "POST /user/api/index/query" '"code": *200' "$QRY"
check "含 data.list" '"list"' "$QRY"
SEC=$(CURL -X POST "$SHOP/user/api/index/secret" \
  -H "Content-Type: application/x-www-form-urlencoded" -d "tradeNo=0&password=0")
echo "     secret 原始返回: $(echo "$SEC" | head -c 120)"

echo ""
echo "=== 14. 店铺后台 · 登录端点（账号已知失效，只验证路径）==="
SL=$(CURL -X POST "$SHOPADMIN/admin/api/authentication/login" \
  -H "Content-Type: application/json" -H "X-Requested-With: XMLHttpRequest" \
  -d '{"username":"__probe__","password":"__probe__"}')
if echo "$SL" | grep -q '"msg"'; then
  echo "  ✅ POST /admin/api/authentication/login 路径有效"
  echo "      $SL"
  PASS=$((PASS+1))
else
  echo "  ❌ 端点不存在: $(echo "$SL" | head -c 150)"
  FAIL=$((FAIL+1))
fi
OV=$(CURL "$SHOPADMIN/admin/api/dashboard/overview" -H "Accept: application/json" -H "X-Requested-With: XMLHttpRequest")
if echo "$OV" | grep -q '"msg"'; then
  echo "  ✅ GET /admin/api/dashboard/overview 路径有效"
  echo "      $OV"
  PASS=$((PASS+1))
else
  echo "  ❌ 端点不存在: $(echo "$OV" | head -c 150)"
  FAIL=$((FAIL+1))
fi

echo ""
echo "=== 15. QQ 第三方登录 ==="
QQST=$(CURL "${AUTH[@]}" "$BASE/qq/status")
check "GET /qq/status 返回 configured" '"configured"' "$QQST"
check "GET /qq/status 返回 isAdmin" '"isAdmin"' "$QQST"
check "GET /qq/status 返回 openidMasked" '"openidMasked"' "$QQST"

QQBT=$(CURL "${AUTH[@]}" -X POST "$BASE/qq/bind/ticket")
check "POST /qq/bind/ticket 发票据" '"ticket"' "$QQBT"
QTICKET=$(echo "$QQBT" | sed -n 's/.*"ticket": *"\([^"]*\)".*/\1/p')

if [ -n "$QTICKET" ]; then
  # 授权页应 302 到腾讯
  QLOC=$(CURL -o /dev/null -D - "$BASE/qq/authorize?t=$QTICKET" | grep -i '^location' | head -1)
  check "GET /qq/authorize 跳腾讯" 'graph.qq.com' "$QLOC"
  check "回调地址正确" 'z7k2m9xq.lingyan.cyou%2Fprod-api%2Fqq%2Fcallback' "$QLOC"

  # 票据必须一次性：第二次打开应给出「已用过」提示而不是再 302
  QAGAIM=$(CURL "$BASE/qq/authorize?t=$QTICKET")
  check "票据一次性（二次打开被拒）" '已经用过或已过期' "$QAGAIM"
fi

# QQ 登录入口（web / app 两种 mode）都应 302
QLOCW=$(CURL -o /dev/null -D - "$BASE/qq/authorize?mode=web" | grep -i '^location' | head -1)
check "GET /qq/authorize?mode=web" 'graph.qq.com' "$QLOCW"
QLOCA=$(CURL -o /dev/null -D - "$BASE/qq/authorize?mode=app" | grep -i '^location' | head -1)
check "GET /qq/authorize?mode=app" 'graph.qq.com' "$QLOCA"

# SPA 深链回退：直接刷新 /login 必须是页面而不是 401 JSON
SPA=$(CURL -o /dev/null -w '%{http_code}' "https://z7k2m9xq.lingyan.cyou/login")
check "GET /login 返回页面（SPA 回退）" '^200$' "$SPA"

# 网页版 QQ 按钮脚本可访问
QJS=$(CURL -o /dev/null -w '%{http_code}' "https://z7k2m9xq.lingyan.cyou/qq-login.js")
check "GET /qq-login.js 可访问" '^200$' "$QJS"

echo ""
echo "=========================================="
echo "通过 $PASS 项，失败 $FAIL 项"
if [ "$FAIL" -eq 0 ]; then
  echo "✅ 全部通过"
  exit 0
else
  echo "❌ 有失败项"
  exit 1
fi
