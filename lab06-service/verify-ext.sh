#!/usr/bin/env bash
# Lab06 Part 2(확장) 채점 — cap-master 노드 셸(root)에서 실행
# 사용: bash ~/k8s-labs-7days/lab06-service/verify-ext.sh   (정리 단계 전에 실행)
# 누적 채점(verify-all.sh)에는 포함하지 않음
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
[ -f "$KUBECONFIG" ] || export KUBECONFIG=/etc/kubernetes/admin.conf
k() { kubectl "$@" 2>/dev/null; }
g() { k get "$1" "$2" -n "${4:-ext}" -o jsonpath="$3"; }
ready_eps() { k get endpointslice -n ext -l kubernetes.io/service-name="$1" -o jsonpath='{range .items[*].endpoints[?(@.conditions.ready==true)]}{.addresses[0]}{"\n"}{end}' | grep -c .; }

echo "[Lab06 Part 2  Service 심화 — 포트 이름 · 세션 고정 · ExternalName · 수동 EndpointSlice]"
ns_ext()      { k get namespace ext; }
echo_ok()     { [ "$(g deploy ext-echo '{.status.availableReplicas}')" = "3" ] && [ "$(g svc ext-echo '{.spec.ports[0].targetPort}')" = "http" ]; }
affinity()    {
  [ "$(g svc ext-echo '{.spec.sessionAffinity}')" = "ClientIP" ] || return 1
  local ip n; ip=$(g svc ext-echo '{.spec.clusterIP}')
  n=$(for i in 1 2 3 4 5; do curl -s -m 3 "http://$ip/"; done | sort -u | grep -c .)
  [ "$n" = "1" ]
}
wrong_fixed() {
  [ "$(g svc ext-wrong '{.spec.ports[0].targetPort}')" = "http" ] && [ "$(ready_eps ext-wrong)" = "3" ] &&
  curl -s -m 3 "http://$(g svc ext-wrong '{.spec.clusterIP}')/" | grep -q 'ext-echo-'
}
ext_name()    { [ "$(g svc shop-api '{.spec.type},{.spec.externalName}')" = "ExternalName,shop-api.shop.svc.cluster.local" ]; }
legacy_nosel(){ [ -z "$(g svc ext-legacy '{.spec.selector}')" ] && [ "$(k get endpointslice -n ext -l kubernetes.io/service-name=ext-legacy -o jsonpath='{.items[0].ports[0].port}')" = "30080" ]; }
legacy_http() { curl -s -m 5 "http://$(g svc ext-legacy '{.spec.clusterIP}')/api/version" | grep -q '"version"'; }
shop_ok()     { [ "$(g svc shop-web '{.spec.type}|{.spec.ports[0].nodePort}|{.spec.externalTrafficPolicy}' shop)" = "NodePort|30080|Cluster" ] && [ "$(g svc shop-api '{.spec.type}' shop)" = "ClusterIP" ]; }

check "네임스페이스 ext 존재 (정리 전에 채점)"                    ns_ext
check "ext-echo  3/3 · targetPort 이름 http"                       echo_ok
check "ext-echo  sessionAffinity ClientIP · 5회 모두 같은 Pod"      affinity
check "ext-wrong  targetPort 수정 · 엔드포인트 3 · 응답"            wrong_fixed
check "ext 네임스페이스 shop-api → ExternalName(shop 네임스페이스)" ext_name
check "ext-legacy  selector 없음 · 수동 EndpointSlice 30080"       legacy_nosel
check "ext-legacy  ClusterIP로 쇼핑몰 API 응답"                    legacy_http
check "본편 shop-web(NodePort 30080 · Cluster) · shop-api 유지"    shop_ok
summary
