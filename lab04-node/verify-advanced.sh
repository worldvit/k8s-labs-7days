#!/usr/bin/env bash
# Lab04 심화(4교시) 채점 — cap-master 노드 셸(root)에서 실행
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
[ -f "$KUBECONFIG" ] || export KUBECONFIG=/etc/kubernetes/admin.conf
k() { kubectl "$@" 2>/dev/null; }
jp() { k get pod "$1" -n shop -o jsonpath="$2"; }

echo "[Lab04 심화 — 지시형 문제]"
p1_running() { [ "$(jp adv-ssd '{.status.phase}')" = "Running" ] && [ "$(jp adv-ssd '{.spec.nodeName}')" = "cap-node2" ]; }
p1_affinity(){ jp adv-ssd '{.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[*].matchExpressions[?(@.key=="disk")].values[*]}' | grep -qw ssd; }
p1_toler()   { jp adv-ssd '{range .spec.tolerations[*]}{.key}{"\n"}{end}' | grep -qx dedicated; }
p2_prefer()  { [ -n "$(jp adv-prefer '{.spec.affinity.nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution[*].weight}')" ] && [ -z "$(jp adv-prefer '{.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution}')" ]; }
p2_node()    { [ "$(jp adv-prefer '{.status.phase}')" = "Running" ] && [ "$(jp adv-prefer '{.spec.nodeName}')" = "cap-node1" ]; }
p3_clean()   { ! k get node cap-node2 -o jsonpath='{range .spec.taints[*]}{.effect}{"\n"}{end}' | grep -qx NoExecute; }
keep()       { [ "$(k get node cap-node2 -o jsonpath='{range .spec.taints[*]}{.key}={.value}:{.effect}{"\n"}{end}' | grep -cx 'dedicated=db:NoSchedule')" = "1" ]; }

check "문제 1  adv-ssd Running · cap-node2"                p1_running
check "문제 1  required affinity disk In ssd"              p1_affinity
check "문제 1  toleration dedicated"                       p1_toler
check "문제 2  adv-prefer preferred affinity만 사용"       p2_prefer
check "문제 2  adv-prefer가 cap-node1에 배치 (taint 영향)"  p2_node
check "문제 3  NoExecute taint 제거"                        p3_clean
check "유지    cap-node2 dedicated=db:NoSchedule"           keep
summary
