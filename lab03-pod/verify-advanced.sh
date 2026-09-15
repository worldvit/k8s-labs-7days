#!/usr/bin/env bash
# Lab03 심화(8교시) 채점 — cap-master 노드 셸(root)에서 실행
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
[ -f "$KUBECONFIG" ] || export KUBECONFIG=/etc/kubernetes/admin.conf
k() { kubectl "$@" 2>/dev/null; }
jp() { k get "$1" "$2" -n shop -o jsonpath="$3"; }

echo "[Lab03 심화 — 지시형 문제]"
p1_env()   {
  [ "$(jp pod shop-api '{.spec.containers[?(@.name=="api")].env[?(@.name=="POD_NAME")].valueFrom.fieldRef.fieldPath}')" = "metadata.name" ] &&
  [ "$(jp pod shop-api '{.spec.containers[?(@.name=="api")].env[?(@.name=="NODE_NAME")].valueFrom.fieldRef.fieldPath}')" = "spec.nodeName" ]
}
p1_value() { [ "$(k exec shop-api -n shop -c api -- printenv NODE_NAME)" = "$(jp pod shop-api '{.spec.nodeName}')" ]; }
p2_title() {
  local want ip got; want=$(jp configmap shop-config '{.data.APP_TITLE}'); ip=$(jp pod shop-api '{.status.podIP}')
  [ "$want" != "SkillBoost Shop" ] && got=$(curl -s -m 5 "http://$ip:5000/api/products" | python3 -c 'import sys,json;print(json.load(sys.stdin)["title"])') && [ "$got" = "$want" ]
}
p3_pod()   { [ "$(jp pod debug-tools '{.status.phase}')" = "Running" ] && [ -n "$(jp pod debug-tools '{.spec.containers[0].command}')" ]; }
p3_label() { [ "$(jp pod debug-tools '{.metadata.labels.tier}')" = "debug" ]; }

check "문제 1  shop-api Downward API (POD_NAME · NODE_NAME)"  p1_env
check "문제 1  NODE_NAME 값이 실제 배치 노드와 일치"         p1_value
check "문제 2  변경한 APP_TITLE이 /api/products에 반영"       p2_title
check "문제 3  debug-tools Pod Running · command 지정"        p3_pod
check "문제 3  debug-tools 라벨 tier=debug"                   p3_label
summary
