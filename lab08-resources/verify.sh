#!/usr/bin/env bash
# Lab08 채점 — cap-master 노드 셸(root)에서 실행
# 사용: bash ~/k8s-labs-7days/lab08-resources/verify.sh
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
[ -f "$KUBECONFIG" ] || export KUBECONFIG=/etc/kubernetes/admin.conf
k() { kubectl "$@" 2>/dev/null; }
g() { k get "$1" "$2" -n shop -o jsonpath="$3"; }

echo "[Lab08  리소스 관리 — requests · limits · LimitRange · Quota · HPA]"
ms_ok()      { [ "$(k get deploy metrics-server -n kube-system -o jsonpath='{.status.availableReplicas}')" = "1" ] && k top nodes >/dev/null; }
ms_flag()    { k get deploy metrics-server -n kube-system -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -q -- '--kubelet-insecure-tls'; }
api_res()    { [ "$(g deploy shop-api '{.spec.template.spec.containers[0].resources.requests.cpu},{.spec.template.spec.containers[0].resources.requests.memory},{.spec.template.spec.containers[0].resources.limits.cpu},{.spec.template.spec.containers[0].resources.limits.memory}')" = "100m,128Mi,500m,256Mi" ]; }
web_res()    { [ -n "$(g deploy shop-web '{.spec.template.spec.containers[?(@.name=="nginx")].resources.requests.cpu}')" ] && [ -n "$(g deploy shop-web '{.spec.template.spec.initContainers[?(@.name=="log-agent")].resources.limits.memory}')" ]; }
api_qos()    { local q; q=$(k get pods -n shop -l tier=api -o jsonpath='{range .items[*]}{.status.qosClass}{"\n"}{end}' | sort -u); [ "$q" = "Burstable" ]; }
lr_ok()      { [ "$(k get limitrange -n shop -o name | grep -c .)" = "1" ] && [ "$(g limitrange shop-limits '{.spec.limits[0].defaultRequest.cpu},{.spec.limits[0].default.memory},{.spec.limits[0].max.cpu},{.spec.limits[0].max.memory}')" = "50m,256Mi,1,1Gi" ]; }
quota_ok()   { [ "$(g resourcequota shop-quota '{.spec.hard.requests\.cpu},{.spec.hard.requests\.memory},{.spec.hard.pods},{.spec.hard.services\.nodeports}')" = "2,3Gi,20,2" ]; }
hpa_spec()   { [ "$(g hpa shop-api '{.spec.minReplicas},{.spec.maxReplicas},{.spec.metrics[0].resource.target.averageUtilization},{.spec.behavior.scaleDown.stabilizationWindowSeconds}')" = "2,5,50,60" ]; }
hpa_metric() { [ -n "$(g hpa shop-api '{.status.currentMetrics[0].resource.current.averageUtilization}')" ]; }
hpa_scaled() { [ -n "$(g hpa shop-api '{.status.lastScaleTime}')" ]; }
settled()    { [ "$(g hpa shop-api '{.status.currentReplicas}')" = "2" ]; }
no_replicas(){ ! grep -qE '^  replicas:' "$HOME/shop/shop-api-deploy.yaml" && ! k apply view-last-applied deploy/shop-api -n shop | grep -qE '^  replicas:'; }
lab_clean()  { [ -z "$(k get deploy,pods -n shop -o name | grep 'lab08-')" ]; }
e2e()        { local ip; ip=$(k get node cap-node1 -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}'); curl -s -m 5 "http://$ip:30080/api/products" | python3 -c 'import sys,json;d=json.load(sys.stdin);sys.exit(0 if d["source"]=="mysql" and len(d["items"])==5 else 1)'; }

check "metrics-server 가용 · kubectl top 동작"                 ms_ok
check "metrics-server --kubelet-insecure-tls (실습용)"          ms_flag
check "shop-api requests 100m·128Mi · limits 500m·256Mi"        api_res
check "shop-web nginx · log-agent 자원 설정"                     web_res
check "shop-api Pod QoS Burstable"                              api_qos
check "LimitRange shop-limits 1개 (기본값 · 상한)"               lr_ok
check "ResourceQuota shop-quota (cpu 2 · mem 3Gi · pods 20)"    quota_ok
check "HPA shop-api 2~5 · CPU 50% · 축소 안정화 60초"             hpa_spec
check "HPA 현재 지표 수집 중"                                     hpa_metric
check "HPA 확장 이력 (lastScaleTime)"                            hpa_scaled
check "부하 종료 후 replicas 2로 복귀"                            settled
check "manifest · last-applied에 replicas 없음"                  no_replicas
check "연습 리소스(lab08-*) 정리"                                 lab_clean
check "NodePort 30080 → API → DB (mysql · 5개)"                  e2e
summary
