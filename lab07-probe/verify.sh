#!/usr/bin/env bash
# Lab07 채점 — cap-master 노드 셸(root)에서 실행
# 사용: bash ~/k8s-labs-7days/lab07-probe/verify.sh
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
[ -f "$KUBECONFIG" ] || export KUBECONFIG=/etc/kubernetes/admin.conf
k() { kubectl "$@" 2>/dev/null; }
dj() { k get deploy shop-api -n shop -o jsonpath="$1"; }
C='{.spec.template.spec.containers[?(@.name=="api")]'

echo "[Lab07  shop-api Probe — Startup · Liveness · Readiness]"
port_name() { [ "$(dj "$C.ports[0].name}")" = "http" ]; }
startup()   { [ "$(dj "$C.startupProbe.httpGet.path}|$C.startupProbe.httpGet.port}")" = "/healthz|http" ]; }
budget()    {
  local p f d; p=$(dj "$C.startupProbe.periodSeconds}"); f=$(dj "$C.startupProbe.failureThreshold}")
  d=$(dj "$C.env[?(@.name==\"STARTUP_DELAY\")].value}")
  [ -n "$p" ] && [ -n "$f" ] && [ -n "$d" ] && [ $((p*f)) -gt "$d" ] && [ "$d" -ge 5 ]
}
liveness()  { [ "$(dj "$C.livenessProbe.httpGet.path}|$C.livenessProbe.periodSeconds}|$C.livenessProbe.failureThreshold}")" = "/healthz|5|3" ]; }
readiness() { [ "$(dj "$C.readinessProbe.httpGet.path}|$C.readinessProbe.httpGet.port}")" = "/readyz|http" ]; }
separated() { [ "$(dj "$C.livenessProbe.httpGet.path}")" != "/readyz" ]; }
avail()     { [ "$(dj '{.status.availableReplicas}|{.status.updatedReplicas}')" = "2|2" ] && [ "$(k get pods -n shop -l tier=api -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' | grep -c True)" -ge 2 ]; }
db_svc()    { [ "$(k get svc shop-db -n shop -o jsonpath='{.spec.selector}')" = '{"app":"shop","tier":"db"}' ]; }
eps()       { [ "$(k get endpointslice -n shop -l kubernetes.io/service-name=shop-api -o jsonpath='{range .items[*].endpoints[?(@.conditions.ready==true)]}{.addresses[0]}{"\n"}{end}' | grep -c .)" = "2" ]; }
e2e()       { local ip; ip=$(k get node cap-node1 -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}'); curl -s -m 5 "http://$ip:30080/api/products" | python3 -c 'import sys,json;d=json.load(sys.stdin);sys.exit(0 if d["source"]=="mysql" and len(d["items"])==5 else 1)'; }
file_sync() { f="$HOME/shop/shop-api-deploy.yaml"; grep -q "startupProbe:" "$f" 2>/dev/null && grep -q "readinessProbe:" "$f" && grep -q "failureThreshold: 15" "$f" && grep -q 'value: "10"' "$f"; }

check "shop-api 포트 이름 http"                              port_name
check "startupProbe /healthz (이름 포트)"                    startup
check "startup 예산(period × failure) > STARTUP_DELAY"       budget
check "livenessProbe /healthz · 5초 · 3회"                   liveness
check "readinessProbe /readyz (이름 포트)"                   readiness
check "liveness가 DB 확인 경로(/readyz)를 쓰지 않음"          separated
check "shop-api 2/2 최신 · Ready"                            avail
check "shop-db Service selector 복구 (app · tier=db)"       db_svc
check "shop-api EndpointSlice ready 2개"                     eps
check "NodePort 30080 → shop-api → DB (mysql · 5개)"         e2e
check "~/shop/shop-api-deploy.yaml 최종 Probe 반영"           file_sync
summary
