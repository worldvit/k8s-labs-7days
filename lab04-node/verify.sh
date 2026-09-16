#!/usr/bin/env bash
# Lab04 채점 — cap-master 노드 셸(root)에서 실행
# 사용: bash ~/k8s-labs-7days/lab04-node/verify.sh
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
[ -f "$KUBECONFIG" ] || export KUBECONFIG=/etc/kubernetes/admin.conf
k() { kubectl "$@" 2>/dev/null; }

echo "[Lab04  노드 역할 나누기 — label · taint · drain]"
n1_label()   { [ "$(k get node cap-node1 -o jsonpath='{.metadata.labels.tier}')" = "front" ]; }
n2_label()   { [ "$(k get node cap-node2 -o jsonpath='{.metadata.labels.disk}')" = "ssd" ]; }
n2_taint()   { k get node cap-node2 -o jsonpath='{range .spec.taints[*]}{.key}={.value}:{.effect}{"\n"}{end}' | grep -qx 'dedicated=db:NoSchedule'; }
n2_noexec()  { ! k get node cap-node2 -o jsonpath='{range .spec.taints[*]}{.effect}{"\n"}{end}' | grep -qx 'NoExecute'; }
n1_sched()   { [ "$(k get node cap-node1 -o jsonpath='{.spec.unschedulable}')" != "true" ]; }
n2_sched()   { [ "$(k get node cap-node2 -o jsonpath='{.spec.unschedulable}')" != "true" ]; }
nodes_ready(){ [ "$(k get nodes -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' | grep -c True)" = "3" ]; }
drained()    { ! k get pod shop-web -n shop; }
clean()      { [ "$(k get pods -n shop --no-headers -o custom-columns=N:.metadata.name | grep -c '^lab04-')" = "0" ]; }
shop_cfg()   { k get configmap shop-config -n shop && k get configmap shop-web-html -n shop && k get secret shop-db-secret -n shop; }

check "cap-node1 라벨 tier=front"                     n1_label
check "cap-node2 라벨 disk=ssd"                       n2_label
check "cap-node2 taint dedicated=db:NoSchedule"       n2_taint
check "cap-node2 NoExecute 실험 taint 제거"            n2_noexec
check "cap-node1 uncordon (스케줄 가능)"               n1_sched
check "cap-node2 스케줄 가능"                          n2_sched
check "노드 3대 Ready"                                 nodes_ready
check "drain 수행 — 직접 만든 shop-web 삭제됨"          drained
check "연습 Pod(lab04-*) 정리"                         clean
check "shop ConfigMap · Secret 유지"                   shop_cfg
summary
