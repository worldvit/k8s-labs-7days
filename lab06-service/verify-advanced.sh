#!/usr/bin/env bash
# Lab06 심화(지시형) 채점 — cap-master 노드 셸(root)에서 실행
# 사용: bash ~/k8s-labs-7days/lab06-service/verify-advanced.sh   (adv 네임스페이스 삭제 전에 실행)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
[ -f "$KUBECONFIG" ] || export KUBECONFIG=/etc/kubernetes/admin.conf
k() { kubectl "$@" 2>/dev/null; }
g() { k get "$1" "$2" -n adv -o jsonpath="$3"; }
nip() { k get node "$1" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}'; }

echo "[Lab06 심화 — 지시형 문제]"
p1_both()     { [ "$(g deploy adv-blue '{.status.availableReplicas}')" = "2" ] && [ "$(g deploy adv-green '{.status.availableReplicas}')" = "2" ]; }
p1_selector() { [ "$(g svc adv-front '{.spec.selector}')" = '{"app":"adv","color":"green"}' ]; }
p1_eps()      {
  local want got
  want=$(k get pods -n adv -l app=adv,color=green -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}' | sort)
  got=$(k get endpointslice -n adv -l kubernetes.io/service-name=adv-front -o jsonpath='{range .items[*].endpoints[?(@.conditions.ready==true)]}{.addresses[0]}{"\n"}{end}' | sort)
  [ -n "$want" ] && [ "$want" = "$got" ]
}
p1_http()     { local ip; ip=$(g svc adv-front '{.spec.clusterIP}'); for i in 1 2 3 4; do curl -s -m 3 "http://$ip/" | grep -q '^green' || return 1; done; }
p2_named()    { [ "$(g svc adv-front '{.spec.ports[0].targetPort}')" = "web" ] && [ "$(g deploy adv-green '{.spec.template.spec.containers[0].ports[?(@.name=="web")].containerPort}')" = "8080" ]; }
p3_alias()    { [ "$(g svc db '{.spec.type},{.spec.externalName}')" = "ExternalName,shop-db.shop.svc.cluster.local" ]; }
p4_policy()   { [ "$(g svc adv-front '{.spec.type}|{.spec.ports[0].nodePort}|{.spec.externalTrafficPolicy}')" = "NodePort|30081|Local" ]; }
p4_local()    { curl -s -m 3 "http://$(nip cap-node1):30081/" | grep -q '^green' && ! curl -s -m 3 "http://$(nip cap-node2):30081/" | grep -q green; }

check "문제 1  adv-blue · adv-green 각 2/2"                       p1_both
check "문제 1  adv-front selector app=adv · color=green"          p1_selector
check "문제 1  엔드포인트 = green Pod만"                           p1_eps
check "문제 1  ClusterIP 응답이 모두 green"                        p1_http
check "문제 2  targetPort 이름 web → 컨테이너 포트 8080"           p2_named
check "문제 3  ExternalName db → shop-db.shop.svc.cluster.local"   p3_alias
check "문제 4  NodePort 30081 · externalTrafficPolicy Local"       p4_policy
check "문제 4  cap-node1만 응답 · cap-node2 무응답"                p4_local
summary
