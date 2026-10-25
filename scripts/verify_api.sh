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

CURL="curl -s -m 20 --noproxy *"

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
LOGIN=$($CURL -X POST "$BASE/login" -H "Content-Type: application/json" \
  -d '{"username":"lingyan","password":"lingyan@2026"}')
check "POST /login 返回 code 200" '"code": *200' "$LOGIN"
TOKEN=$(echo "$LOGIN" | sed -n 's/.*"token": *"\([^"]*\)".*/\1/p')
if [ -z "$TOKEN" ]; then echo "  ❌ 未能取到 token，后续跳过"; exit 1; fi
echo "  token: ${TOKEN:0:30}..."

AUTH=(-H "Authorization: Bearer $TOKEN")

echo ""
echo "=== 2. 卡密后台 · 用户信息与路由 ==="
INFO=$($CURL "${AUTH[@]}" "$BASE/getInfo")
check "GET /getInfo 权限点" 'card:key:list' "$INFO"
check "GET /getInfo 用户名" '"userName": *"lingyan"' "$INFO"
ROUTERS=$($CURL "${AUTH[@]}" "$BASE/getRouters")
check "GET /getRouters 含卡密中心" '卡密中心' "$ROUTERS"

echo ""
echo "=== 3. 卡密管理 · 列表 ==="
LIST=$($CURL "${AUTH[@]}" "$BASE/card/key/list?pageNum=1&pageSize=5")
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
F0=$($CURL "${AUTH[@]}" "$BASE/card/key/list?pageNum=1&pageSize=5&status=0")
check "GET /card/key/list?status=0" '"rows"' "$F0"
F1=$($CURL "${AUTH[@]}" "$BASE/card/key/list?pageNum=1&pageSize=5&status=1")
check "GET /card/key/list?status=1" '"rows"' "$F1"
F2=$($CURL "${AUTH[@]}" "$BASE/card/key/list?pageNum=1&pageSize=5&status=2")
check "GET /card/key/list?status=2" '"rows"' "$F2"

echo ""
echo "=== 5. 卡密管理 · 搜索（keyword 同时给 cardNo 和 batchNo）==="
FIRSTCARD=$(echo "$LIST" | sed -n 's/.*"cardNo": *"\([^"]*\)".*/\1/p' | head -1)
SEARCH=$($CURL "${AUTH[@]}" "$BASE/card/key/list?pageNum=1&pageSize=5&cardNo=$FIRSTCARD&batchNo=$FIRSTCARD")
check "GET /card/key/list?cardNo=&batchNo=" '"rows"' "$SEARCH"

echo ""
echo "=== 6. 卡密管理 · 生成（真实创建 1 张）==="
GEN=$($CURL "${AUTH[@]}" -X POST "$BASE/card/key/generate" -H "Content-Type: application/json" \
  -d '{"batchName":"verify-script","productId":"LG-APP","count":1,"durationDays":30}')
check "POST /card/key/generate 成功" '"code": *200' "$GEN"
check "返回 batchNo" '"batchNo"' "$GEN"
check "返回 successCount" '"successCount"' "$GEN"

echo ""
echo "=== 7. 卡密管理 · 状态变更 / 解冻 / 解封 / 删除（用不存在的 id）==="
ST=$($CURL "${AUTH[@]}" -X PUT "$BASE/card/key/status" -H "Content-Type: application/json" \
  -d '{"ids":[-1],"status":3,"reason":"probe"}')
check "PUT /card/key/status 返回 success" '"success"' "$ST"
check "skipped 是对象数组" '"cardNo"' "$ST"
UNF=$($CURL "${AUTH[@]}" -X PUT "$BASE/card/key/unfreeze" -H "Content-Type: application/json" -d '{"ids":[-1]}')
check "PUT /card/key/unfreeze" '"success"' "$UNF"
UNB=$($CURL "${AUTH[@]}" -X PUT "$BASE/card/key/unban" -H "Content-Type: application/json" -d '{"ids":[-1]}')
check "PUT /card/key/unban" '"success"' "$UNB"
DEL=$($CURL "${AUTH[@]}" -X DELETE "$BASE/card/key/999999")
check "DELETE /card/key/{id}" '"success"' "$DEL"

echo ""
echo "=== 8. 卡密管理 · 操作记录 ==="
REC=$($CURL "${AUTH[@]}" "$BASE/card/record/list?pageNum=1&pageSize=5")
check "GET /card/record/list 返回 rows" '"rows"' "$REC"
check "行含 action" '"action"' "$REC"
check "行含 source" '"source"' "$REC"
check "行含 operator" '"operator"' "$REC"

echo ""
echo "=== 9. 对接情况 · 发卡渠道 ==="
CH=$($CURL "${AUTH[@]}" "$BASE/card/channel/list")
check "GET /card/channel/list 返回 rows" '"rows"' "$CH"
check "含 channelName" '"channelName"' "$CH"
check "含 enabled" '"enabled"' "$CH"
check "含 remark" '"remark"' "$CH"

echo ""
echo "=== 10. 店铺管理 · 商城分类（GET, query）==="
CAT=$($CURL "$SHOP/user/api/index/data" -H "Accept: application/json" -H "X-Requested-With: XMLHttpRequest")
check "GET /user/api/index/data" '"code": *200' "$CAT"
check "分类含 name" '"name"' "$CAT"
check "分类含 commodity_count" '"commodity_count"' "$CAT"
check "分类含 owner" '"owner"' "$CAT"

echo ""
echo "=== 11. 店铺管理 · 商品列表（GET, query）==="
COMM=$($CURL "$SHOP/user/api/index/commodity" -H "Accept: application/json" -H "X-Requested-With: XMLHttpRequest")
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
STOCK=$($CURL -X POST "$SHOP/user/api/index/stock" \
  -H "Content-Type: application/x-www-form-urlencoded" -d "item_id=5")
check "POST /user/api/index/stock" '"code": *200' "$STOCK"
check "返回 stock" '"stock"' "$STOCK"
check "返回 stock_state" '"stock_state"' "$STOCK"
VAL=$($CURL -X POST "$SHOP/user/api/index/valuation" \
  -H "Content-Type: application/x-www-form-urlencoded" -d "item_id=5&quantity=1")
echo "     valuation 原始返回: $(echo "$VAL" | head -c 120)"

echo ""
echo "=== 13. 店铺管理 · 订单查询与发货内容（POST, form）==="
QRY=$($CURL -X POST "$SHOP/user/api/index/query" \
  -H "Content-Type: application/x-www-form-urlencoded" -d "keywords=__probe__&page=1&limit=10")
check "POST /user/api/index/query" '"code": *200' "$QRY"
check "含 data.list" '"list"' "$QRY"
SEC=$($CURL -X POST "$SHOP/user/api/index/secret" \
  -H "Content-Type: application/x-www-form-urlencoded" -d "tradeNo=0&password=0")
echo "     secret 原始返回: $(echo "$SEC" | head -c 120)"

echo ""
echo "=== 14. 店铺后台 · 登录端点（账号已知失效，只验证路径）==="
SL=$($CURL -X POST "$SHOPADMIN/admin/api/authentication/login" \
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
OV=$($CURL "$SHOPADMIN/admin/api/dashboard/overview" -H "Accept: application/json" -H "X-Requested-With: XMLHttpRequest")
if echo "$OV" | grep -q '"msg"'; then
  echo "  ✅ GET /admin/api/dashboard/overview 路径有效"
  echo "      $OV"
  PASS=$((PASS+1))
else
  echo "  ❌ 端点不存在: $(echo "$OV" | head -c 150)"
  FAIL=$((FAIL+1))
fi

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
