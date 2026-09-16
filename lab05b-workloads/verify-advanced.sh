#!/usr/bin/env bash
# Lab05-B 심화(4일차 4교시) 채점 — cap-master 노드 셸(root)에서 실행
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
[ -f "$KUBECONFIG" ] || export KUBECONFIG=/etc/kubernetes/admin.conf
k() { kubectl "$@" 2>/dev/null; }
g() { k get "$1" "$2" -n shop -o jsonpath="$3"; }

echo "[Lab05-B 심화 — 지시형 문제]"
p1_label()   { [ "$(g deploy shop-web '{.spec.template.metadata.labels.release}')" = "stable" ] && [ -n "$(g deploy shop-web '{.spec.template.metadata.annotations.shop\.skillboost/owner}')" ]; }
p1_resumed() { [ "$(g deploy shop-web '{.spec.paused}')" != "true" ] && [ "$(g deploy shop-web '{.status.updatedReplicas},{.status.availableReplicas}')" = "2,2" ]; }
p2_indexed() { [ "$(g job adv-indexed '{.spec.completionMode},{.spec.completions},{.spec.parallelism},{.status.succeeded}')" = "Indexed,3,3,3" ]; }
p3_deadline(){ [ "$(g job adv-deadline '{.status.conditions[?(@.type=="Failed")].reason}')" = "DeadlineExceeded" ]; }
p4_resumed() { [ "$(g cronjob shop-report '{.spec.suspend}')" = "false" ]; }

check "문제 1  shop-web 템플릿 라벨 release=stable · 어노테이션 추가"  p1_label
check "문제 1  pause 해제 · 2/2 최신 반영"                             p1_resumed
check "문제 2  adv-indexed Indexed · 3/3 완료"                         p2_indexed
check "문제 3  adv-deadline 실패 사유 DeadlineExceeded"                 p3_deadline
check "문제 4  shop-report 재개 상태"                                  p4_resumed
summary
