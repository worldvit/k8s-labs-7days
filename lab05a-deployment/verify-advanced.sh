#!/usr/bin/env bash
# Lab05-A 심화(지시형) 채점 — cap-master 노드 셸(root)에서 실행
# 사용: bash ~/k8s-labs-7days/lab05a-deployment/verify-advanced.sh   (adv 네임스페이스 삭제 전에 실행)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
[ -f "$KUBECONFIG" ] || export KUBECONFIG=/etc/kubernetes/admin.conf
k() { kubectl "$@" 2>/dev/null; }
dj() { k get deploy "$1" -n adv -o jsonpath="$2"; }
F="$HOME/adv/adv-web.yaml"

echo "[Lab05-A 심화 — 지시형 문제]"
p1_strategy() { [ "$(dj adv-web '{.spec.strategy.type},{.spec.strategy.rollingUpdate.maxSurge},{.spec.strategy.rollingUpdate.maxUnavailable}')" = "RollingUpdate,0,1" ]; }
p1_fields()   { [ "$(dj adv-web '{.spec.replicas},{.spec.revisionHistoryLimit},{.spec.progressDeadlineSeconds}')" = "3,5,60" ]; }
p1_cause()    { [ -n "$(dj adv-web '{.metadata.annotations.kubernetes\.io/change-cause}')" ]; }
p2_recreate() {
  [ "$(dj adv-recreate '{.spec.strategy.type}')" = "Recreate" ] &&
  [ "$(dj adv-recreate '{.spec.template.spec.containers[0].image}')" = "nginx:1.30-alpine" ] &&
  [ "$(dj adv-recreate '{.status.availableReplicas},{.spec.replicas}')" = "2,2" ]
}
p3_bad_rs()   {
  k get rs -n adv --no-headers -o custom-columns='N:.metadata.name,I:.spec.template.spec.containers[0].image,R:.spec.replicas' |
    awk '$1 ~ /^adv-web-/ && $2=="nginx:9.99-alpine" && $3=="0"' | grep -q .
}
p3_restored() {
  [ "$(dj adv-web '{.spec.template.spec.containers[0].image}')" = "nginx:1.30-alpine" ] &&
  [ "$(dj adv-web '{.status.conditions[?(@.type=="Progressing")].reason}')" = "NewReplicaSetAvailable" ]
}
p3_file()     { [ -f "$F" ] && grep -q 'nginx:1.30-alpine' "$F" && ! grep -q '9.99' "$F"; }
p4_restart()  {
  [ -n "$(dj adv-web '{.spec.template.metadata.annotations.kubectl\.kubernetes\.io/restartedAt}')" ] &&
  [ "$(dj adv-web '{.status.updatedReplicas},{.status.availableReplicas}')" = "3,3" ]
}

check "문제 1  adv-web 전략 maxSurge 0 · maxUnavailable 1"            p1_strategy
check "문제 1  replicas 3 · revisionHistoryLimit 5 · 진행 기한 60초"  p1_fields
check "문제 1  변경 사유(change-cause) 기록"                          p1_cause
check "문제 2  adv-recreate Recreate · 1.30 · 2/2"                     p2_recreate
check "문제 3  실패 revision(9.99) 이력 보존 · 개수 0"                 p3_bad_rs
check "문제 3  adv-web 1.30으로 복구 · 정상 진행 상태"                 p3_restored
check "문제 3  ~/adv/adv-web.yaml 1.30으로 동기화"                     p3_file
check "문제 4  rollout restart 흔적 · 3/3 최신 반영"                   p4_restart
summary
