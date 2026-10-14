#!/usr/bin/env bash
# Lab04 Part 4(Taint · Toleration 종합) 채점 — cap-master 노드 셸(root)에서 실행
# 사용: bash ~/k8s-labs-7days/lab04-node/verify-taint.sh   (Part 4 정리 단계 전에 실행)
# 누적 채점(verify-all.sh)에는 포함하지 않음
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
[ -f "$KUBECONFIG" ] || export KUBECONFIG=/etc/kubernetes/admin.conf
k() { kubectl "$@" 2>/dev/null; }
NS=taint-lab
D="$HOME/taint-lab"
tol() { k get deploy "$1" -n $NS -o jsonpath='{range .spec.template.spec.tolerations[*]}{.key}|{.operator}|{.value}|{.effect}|{.tolerationSeconds};{end}'; }
taints() { k get node "$1" -o jsonpath='{range .spec.taints[*]}{.key}={.value}:{.effect} {end}'; }

echo "[Lab04 Part 4  Taint · Toleration 종합 — effect 3종 · operator 4형태 · nodeName 우회]"
ns_ok()      { k get namespace $NS; }
n1_clean()   { [ -z "$(taints cap-node1)" ]; }
n2_only()    { [ "$(taints cap-node2)" = "dedicated=db:NoSchedule " ]; }
files()      { for f in dep-taints.yaml dep-taints-nodeselector.yaml dep-taints-toleration.yaml mk.sh tol-variants.yaml prefer-pods.yaml victim-pod.yaml noexecute.yaml; do [ -f "$D/$f" ] || return 1; done; }
labels_uniq(){ [ "$(grep -h 'app: pod-nginx' "$D"/dep-taints*.yaml | sort -u | wc -l)" -ge 3 ]; }
variants()   {
  [ "$(tol tol-equal)"         = "team|Equal|dev|NoSchedule|;" ] &&
  [ "$(tol tol-wrong-value)"   = "team|Equal|prod|NoSchedule|;" ] &&
  [ "$(tol tol-wrong-effect)"  = "team|Equal|dev|NoExecute|;" ] &&
  [ "$(tol tol-exists-effect)" = "team|Exists||NoSchedule|;" ] &&
  [ "$(tol tol-exists-key)"    = "team|Exists|||;" ] &&
  [ "$(tol tol-other-key)"     = "app|Exists|||;" ] &&
  [ "$(tol tol-exists-all)"    = "|Exists|||;" ]
}
prefer()     { [ "$(k get pod prefer-1 -n $NS -o jsonpath='{.spec.nodeName}')" = "cap-node2" ] && [ "$(k get pod prefer-2 -n $NS -o jsonpath='{.spec.nodeName}')" = "cap-node1" ]; }
victim_gone(){ ! k get pod victim-pod -n $NS; }
ne_key()     { tol ne-key | grep -q 'storage|Exists||NoExecute|60;'; }
ne_running() {
  for d in ne-plain ne-key ne-ultimate; do
    [ "$(k get deploy $d -n $NS -o jsonpath='{.status.availableReplicas}')" = "1" ] || return 1
  done
  [ "$(k get pods -n $NS -l app=ne-ultimate -o jsonpath='{.items[0].spec.nodeName}')" = "cap-node2" ]
}
shop_ok()    { k get configmap shop-config -n shop && ! k get deploy,pods -n shop -o name | grep -qE 'nginx|tol-|ne-|prefer|victim'; }

check "네임스페이스 taint-lab 존재 (정리 전에 채점)"                   ns_ok
check "cap-node1 실험 taint 모두 제거"                                 n1_clean
check "cap-node2 taint는 dedicated=db:NoSchedule 하나만"               n2_only
check "~/taint-lab 실습 파일 8개"                                      files
check "dep-taints 3종의 Pod 라벨이 서로 다름 (selector 겹침 방지)"     labels_uniq
check "toleration 7형태 (Equal · Exists · 값/효과/키 불일치 · 빈 Exists)" variants
check "PreferNoSchedule  prefer-1 → cap-node2 · prefer-2 → cap-node1"  prefer
check "NoExecute  nodeName으로 만든 victim-pod 축출 · 재생성 안 됨"    victim_gone
check "ne-key  storage Exists NoExecute · tolerationSeconds 60"        ne_key
check "taint 제거 후 ne-plain · ne-key · ne-ultimate 모두 1/1"         ne_running
check "shop 네임스페이스에 실습 리소스 없음"                           shop_ok
summary
