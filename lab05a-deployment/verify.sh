#!/usr/bin/env bash
# Lab05-A 채점 — cap-master 노드 셸(root)에서 실행
# 사용: bash ~/k8s-labs-7days/lab05a-deployment/verify.sh
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
[ -f "$KUBECONFIG" ] || export KUBECONFIG=/etc/kubernetes/admin.conf
k() { kubectl "$@" 2>/dev/null; }
dj() { k get deploy "$1" -n shop -o jsonpath="$2"; }

echo "[Lab05-A  shop을 Deployment로 — 롤링 업데이트 · 롤백]"
api_avail()   { [ "$(dj shop-api '{.status.availableReplicas}')" = "2" ] && [ "$(dj shop-api '{.spec.replicas}')" = "2" ]; }
api_image()   { [ "$(dj shop-api '{.spec.template.spec.containers[?(@.name=="api")].image}')" = "ghcr.io/worldvit/skillboost-api:v2" ]; }
api_selector(){ [ "$(dj shop-api '{.spec.selector.matchLabels}')" = '{"app":"shop","tier":"api"}' ]; }
api_version() { [ "$(dj shop-api '{.spec.template.metadata.labels.version}')" = "v2" ]; }
api_strategy(){ [ "$(dj shop-api '{.spec.strategy.rollingUpdate.maxSurge},{.spec.strategy.rollingUpdate.maxUnavailable}')" = "1,0" ]; }
api_node()    { [ "$(dj shop-api '{.spec.template.spec.nodeSelector.tier}')" = "front" ]; }
api_config()  { dj shop-api '{.spec.template.spec.containers[0].envFrom[*].configMapRef.name}' | grep -qw shop-config && [ "$(dj shop-api '{.spec.template.spec.containers[0].env[?(@.name=="DB_PASSWORD")].valueFrom.secretKeyRef.name}')" = "shop-db-secret" ]; }
api_rev()     { local r; r=$(k get deploy shop-api -n shop -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}'); [ -n "$r" ] && [ "$r" -ge 2 ]; }
api_http()    {
  local ips ok=0; ips=$(k get pods -n shop -l app=shop,tier=api -o jsonpath='{range .items[?(@.status.phase=="Running")]}{.status.podIP}{" "}{end}')
  [ -n "$ips" ] || return 1
  for ip in $ips; do curl -s -m 5 "http://$ip:5000/api/version" | grep -q '"version":"v2"' || return 1; ok=$((ok+1)); done
  [ $ok -ge 2 ]
}
web_avail()   { [ "$(dj shop-web '{.status.availableReplicas}')" = "2" ]; }
web_spec()    {
  [ "$(dj shop-web '{.spec.template.spec.initContainers[?(@.name=="log-agent")].restartPolicy}')" = "Always" ] &&
  [ "$(dj shop-web '{.spec.template.spec.nodeSelector.tier}')" = "front" ] &&
  [ -n "$(dj shop-web '{.spec.template.spec.volumes[?(@.configMap.name=="shop-web-html")].name}')" ]
}
no_bare()     { [ -z "$(k get pods -n shop --no-headers -o custom-columns=NAME:.metadata.name,OWNER:.metadata.ownerReferences[0].kind | awk '$2=="<none>"{print $1}')" ]; }
lab_clean()   { [ -z "$(k get rs,pods -n shop -l app=lab05 -o name)" ]; }
file_synced() { grep -q 'skillboost-api:v2' "$HOME/shop/shop-api-deploy.yaml" 2>/dev/null && grep -q 'version: v2' "$HOME/shop/shop-api-deploy.yaml"; }

check "shop-api Deployment 가용 2/2"                        api_avail
check "shop-api 이미지 v2"                                  api_image
check "shop-api selector app · tier (version 제외)"         api_selector
check "shop-api 템플릿 라벨 version=v2"                     api_version
check "shop-api 전략 maxSurge 1 · maxUnavailable 0"         api_strategy
check "shop-api nodeSelector tier=front"                   api_node
check "shop-api ConfigMap · Secret 주입 유지"               api_config
check "shop-api 롤아웃 revision 2 이상"                     api_rev
check "shop-api Pod 모두 /api/version v2 응답"               api_http
check "shop-web Deployment 가용 2/2"                        web_avail
check "shop-web 사이드카 · nodeSelector · 화면 볼륨"         web_spec
check "소유자 없는 Pod 없음 (모두 컨트롤러 관리)"            no_bare
check "연습 ReplicaSet · Pod(app=lab05) 정리"               lab_clean
check "~/shop/shop-api-deploy.yaml 파일이 v2와 일치"         file_synced
summary
