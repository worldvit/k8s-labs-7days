#!/usr/bin/env bash
# Lab08 Part 2(확장) 채점 — cap-master 노드 셸(root)에서 실행
# 사용: bash ~/k8s-labs-7days/lab08-resources/verify-ext.sh   (정리 단계 전에 실행)
# 누적 채점(verify-all.sh)에는 포함하지 않음
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
[ -f "$KUBECONFIG" ] || export KUBECONFIG=/etc/kubernetes/admin.conf
k() { kubectl "$@" 2>/dev/null; }
p() { k get pod "$1" -n ext -o jsonpath="$2"; }
oom() { k exec "$1" -n ext -- cat /proc/1/oom_score_adj | tr -d '[:space:]'; }

echo "[Lab08 Part 2  QoS와 OOM 순위 · Quota와 LimitRange의 관계 · Pending과 거부의 차이]"
ns_ext()     { k get namespace ext; }
qos()        { [ "$(p ext-be '{.status.qosClass}'),$(p ext-bu '{.status.qosClass}'),$(p ext-gu '{.status.qosClass}')" = "BestEffort,Burstable,Guaranteed" ]; }
oom_rank()   { local be bu gu; be=$(oom ext-be); bu=$(oom ext-bu); gu=$(oom ext-gu); [ "$be" = "1000" ] && [ "$gu" = "-997" ] && [ "$bu" -gt "$gu" ] && [ "$bu" -lt "$be" ]; }
quota()      { [ "$(k get resourcequota ext-quota -n ext -o jsonpath='{.spec.hard.requests\.cpu},{.spec.hard.requests\.memory},{.spec.hard.pods}')" = "4,2Gi,10" ]; }
lr()         { [ "$(k get limitrange ext-limits -n ext -o jsonpath='{.spec.limits[0].defaultRequest.cpu},{.spec.limits[0].default.cpu}')" = "100m,200m" ]; }
injected()   { [ "$(p ext-ok '{.spec.containers[0].resources.requests.cpu}')" = "100m" ] && [ -n "$(p ext-ok '{.metadata.annotations.kubernetes\.io/limit-ranger}')" ]; }
pending()    { [ "$(p ext-huge '{.status.phase}|{.status.conditions[?(@.type=="PodScheduled")].reason}')" = "Pending|Unschedulable" ] && [ "$(p ext-huge '{.spec.containers[0].resources.requests.cpu}')" = "3" ]; }
shop_ok()    { [ "$(k get hpa shop-api -n shop -o jsonpath='{.spec.minReplicas},{.spec.maxReplicas}')" = "2,5" ] && [ "$(k get deploy shop-api -n shop -o jsonpath='{.status.availableReplicas}')" -ge 2 ] 2>/dev/null; }

check "네임스페이스 ext 존재 (정리 전에 채점)"                     ns_ext
check "ext-be · ext-bu · ext-gu QoS (BestEffort · Burstable · Guaranteed)" qos
check "oom_score_adj 순위 (BestEffort 1000 > Burstable > Guaranteed -997)" oom_rank
check "ResourceQuota ext-quota (cpu 4 · mem 2Gi · pods 10)"        quota
check "LimitRange ext-limits (기본 request 100m · limit 200m)"     lr
check "ext-ok  LimitRange 기본값 주입 · limit-ranger 기록"          injected
check "ext-huge  cpu 3 요청 → Pending (Unschedulable)"             pending
check "본편 shop-api HPA 2~5 · 가용 유지"                          shop_ok
summary
