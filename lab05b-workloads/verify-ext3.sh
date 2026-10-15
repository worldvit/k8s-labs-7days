#!/usr/bin/env bash
# Lab05-B Part 3(확장) 채점 — cap-master 노드 셸(root)에서 실행
# 사용: bash ~/k8s-labs-7days/lab05b-workloads/verify-ext3.sh   (정리 단계 전에 실행)
# 누적 채점(verify-all.sh)에는 포함하지 않음
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
[ -f "$KUBECONFIG" ] || export KUBECONFIG=/etc/kubernetes/admin.conf
k() { kubectl "$@" 2>/dev/null; }
g() { k get "$1" "$2" -n "${4:-ext3}" -o jsonpath="$3"; }

echo "[Lab05-B Part 3  ReplicaSet 심화 · Deployment 세부 제어]"
ns_ext3()     { k get namespace ext3; }
rs2_sel()     { [ "$(g rs ext3-rs2 '{.spec.selector.matchLabels.app}|{.spec.selector.matchExpressions[0].key}|{.spec.selector.matchExpressions[0].operator}|{.spec.selector.matchExpressions[0].values}')" = 'ext3|ver|In|["1.36","1.37"]' ]; }
rs2_ready()   { [ "$(g rs ext3-rs2 '{.spec.replicas},{.status.readyReplicas}')" = "2,2" ] && ! k get rs ext3-rs -n ext3; }
rs2_adopt()   {
  local imgs; imgs="$(k get pods -n ext3 -l 'ver in (1.36,1.37)' -o jsonpath='{range .items[*]}{.metadata.ownerReferences[0].name}/{.spec.containers[0].image}{"\n"}{end}' | sort -u)"
  [ "$(g rs ext3-rs2 '{.spec.template.spec.containers[0].image}')" = "busybox:1.37" ] && [ "$imgs" = "ext3-rs2/busybox:1.36" ]
}
rs_file()     { grep -q 'image: busybox:1.36' "$HOME/ext3/ext3-rs.yaml" && grep -q 'ver: "1.36"' "$HOME/ext3/ext3-rs.yaml"; }
loose_pods()  {
  [ -z "$(g pod ext3-p1 '{.metadata.ownerReferences}')" ] && [ "$(g pod ext3-p1 '{.metadata.name}')" = "ext3-p1" ] &&
  [ -z "$(g pod ext3-p3 '{.metadata.ownerReferences}')" ] && [ "$(g pod ext3-p3 '{.metadata.name}')" = "ext3-p3" ] &&
  ! k get pod ext3-p2 -n ext3
}
dep_strategy(){ [ "$(g deploy ext3-web '{.spec.strategy.rollingUpdate.maxSurge},{.spec.strategy.rollingUpdate.maxUnavailable},{.spec.minReadySeconds}')" = "50%,25%,10" ]; }
dep_ready()   { [ "$(g deploy ext3-web '{.status.updatedReplicas},{.status.availableReplicas}')" = "3,3" ] && [ "$(g deploy ext3-web '{.spec.paused}')" != "true" ]; }
dep_spec()    {
  [ "$(g deploy ext3-web '{.spec.template.spec.containers[0].image}')" = "nginx:1.29-alpine" ] &&
  [ "$(g deploy ext3-web '{.spec.template.spec.containers[0].resources.limits.cpu},{.spec.template.spec.containers[0].resources.limits.memory}')" = "100m,128Mi" ]
}
dep_batch()   {
  [ "$(k get rs -n ext3 -l app=ext3-web --no-headers | wc -l)" -eq 3 ] &&
  [ "$(g deploy ext3-web '{.metadata.annotations.deployment\.kubernetes\.io/revision}')" -ge 3 ]
}
dep_file()    { [ -f "$HOME/ext3/ext3-web.yaml" ] && kubectl diff -f "$HOME/ext3/ext3-web.yaml" >/dev/null 2>&1; }
shop_ok()     {
  [ "$(g deploy shop-api '{.status.availableReplicas}' shop)" = "2" ] && [ "$(g deploy shop-web '{.status.availableReplicas}' shop)" = "2" ] &&
  [ "$(g sts shop-db '{.status.readyReplicas}' shop)" = "1" ]
}

check "네임스페이스 ext3 존재 (정리 전에 채점)"                        ns_ext3
check "ext3-rs2  selector app=ext3 + ver In (1.36, 1.37)"              rs2_sel
check "ext3-rs2  2/2 Ready · ext3-rs 삭제됨"                           rs2_ready
check "ext3-rs2  입양한 Pod는 busybox:1.36 (템플릿은 1.37)"            rs2_adopt
check "~/ext3/ext3-rs.yaml 템플릿 1.36으로 수정"                        rs_file
check "ext3-p1 · ext3-p3 소유자 없음 · ext3-p2 삭제됨"                  loose_pods
check "ext3-web  maxSurge 50% · maxUnavailable 25% · minReadySeconds 10" dep_strategy
check "ext3-web  3/3 최신 · pause 해제"                                dep_ready
check "ext3-web  nginx:1.29-alpine · limits cpu 100m / memory 128Mi"  dep_spec
check "ext3-web  pause로 묶어 ReplicaSet 3개 · revision 3 이상"         dep_batch
check "~/ext3/ext3-web.yaml 파일이 클러스터와 일치"                    dep_file
check "본편 shop-api · shop-web · shop-db 영향 없음"                   shop_ok
summary
