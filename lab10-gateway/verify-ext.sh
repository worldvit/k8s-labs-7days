#!/usr/bin/env bash
# Lab10 Part 2(확장) 채점 — cap-master 노드 셸(root)에서 실행
# 사용: bash ~/k8s-labs-7days/lab10-gateway/verify-ext.sh   (정리 단계 전에 실행)
# 누적 채점(verify-all.sh)에는 포함하지 않음
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
[ -f "$KUBECONFIG" ] || export KUBECONFIG=/etc/kubernetes/admin.conf
k() { kubectl "$@" 2>/dev/null; }
nip() { k get node "$1" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}'; }
N1=$(nip cap-node1)

echo "[Lab10 Part 2  내 Helm 차트 · 네임스페이스 넘는 라우팅 · 헤더 매칭 · 재작성 · 리다이렉트]"
chart_lint() { [ -f "$HOME/ext/hello/Chart.yaml" ] && helm lint "$HOME/ext/hello" >/dev/null 2>&1; }
releases()   { helm list -n ext -o json 2>/dev/null | python3 -c 'import sys,json;r={x["name"]:x for x in json.load(sys.stdin)};sys.exit(0 if all(n in r and r[n]["status"]=="deployed" and r[n]["chart"]=="hello-0.1.0" for n in ("ext-hello","ext-hello-v2")) else 1)'; }
hist()       { helm history ext-hello -n ext -o json 2>/dev/null | python3 -c 'import sys,json;h=json.load(sys.stdin);sys.exit(0 if len(h)>=3 and any("Rollback" in x.get("description","") for x in h) else 1)'; }
vals()       {
  helm get values ext-hello -n ext -o json 2>/dev/null | python3 -c 'import sys,json;sys.exit(0 if not json.load(sys.stdin) else 1)' &&
  helm get values ext-hello-v2 -n ext -o json 2>/dev/null | python3 -c 'import sys,json;sys.exit(0 if json.load(sys.stdin).get("message")=="hello v2" else 1)'
}
refgrant()   { k get referencegrant -n ext -o jsonpath='{range .items[*]}{.spec.from[0].kind}/{.spec.from[0].namespace}>{.spec.to[0].kind}{"\n"}{end}' | grep -qx 'HTTPRoute/shop>Service'; }
route_ok()   { [ "$(k get httproute ext-hello-route -n shop -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}|{.status.parents[0].conditions[?(@.type=="ResolvedRefs")].status}')" = "True|True" ]; }
e2e_v1()     { curl -s -m 5 "http://$N1:31080/hello" | grep -q '^hello v1 '; }
e2e_v2()     { curl -s -m 5 -H 'X-Version: v2' "http://$N1:31080/hello" | grep -q '^hello v2 '; }
redirect()   { [ "$(curl -s -m 5 -o /dev/null -w '%{http_code}' "http://$N1:31080/old-hello")" = "301" ]; }
shop_ok()    {
  [ "$(k get httproute shop-route -n shop -o jsonpath='{range .spec.rules[*]}{.matches[0].path.value}={.backendRefs[0].name}:{.backendRefs[0].port} {end}')" = "/api=shop-api:5000 /=shop-web:80 " ] &&
  curl -s -m 5 "http://$N1:31080/api/products" | python3 -c 'import sys,json;d=json.load(sys.stdin);sys.exit(0 if d["source"]=="mysql" and len(d["items"])==5 else 1)'
}

check "~/ext/hello 차트 · helm lint 통과"                          chart_lint
check "릴리스 ext-hello · ext-hello-v2 (hello-0.1.0 · deployed)"   releases
check "ext-hello 업그레이드 · 롤백 이력"                            hist
check "values — ext-hello 기본값 · ext-hello-v2 message=hello v2"  vals
check "ReferenceGrant (shop의 HTTPRoute → ext의 Service)"          refgrant
check "HTTPRoute ext-hello-route Accepted · ResolvedRefs"          route_ok
check ":31080/hello → hello v1"                                     e2e_v1
check ":31080/hello + X-Version: v2 → hello v2"                     e2e_v2
check ":31080/old-hello → 301 리다이렉트"                           redirect
check "본편 shop-route 규칙 · 쇼핑몰 API 유지"                      shop_ok
summary
