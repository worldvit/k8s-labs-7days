#!/usr/bin/env bash
# Lab02 채점 (클러스터) — cap-master 노드 셸에서 root로 실행
# 사용: sudo -i 후  bash ~/k8s-capstone-labs/lab02-install/verify.sh
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
[ -f "$KUBECONFIG" ] || export KUBECONFIG=/etc/kubernetes/admin.conf

echo "[Lab02  cap 클러스터 — 노드 검사]"
k() { kubectl "$@" 2>/dev/null; }

api_ok()        { k get --raw=/readyz | grep -qx ok; }
node_exists()   { k get node "$1"; }
all_ready()     {
  local s; s=$(k get nodes -o jsonpath='{range .items[*]}{.metadata.name}={.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}')
  for n in cap-master cap-node1 cap-node2; do echo "$s" | grep -qx "$n=True" || return 1; done
}
kubelet_136()   {
  local v; v=$(k get nodes -o jsonpath='{range .items[*]}{.status.nodeInfo.kubeletVersion}{"\n"}{end}')
  [ "$(echo "$v" | grep -c '^v1\.36\.')" -eq 3 ]
}
containerd_2()  {
  local r; r=$(k get nodes -o jsonpath='{range .items[*]}{.status.nodeInfo.containerRuntimeVersion}{"\n"}{end}')
  [ "$(echo "$r" | grep -c '^containerd://2\.')" -eq 3 ]
}
cp_taint()      { k get node cap-master -o jsonpath='{.spec.taints[*].key}' | grep -q 'node-role.kubernetes.io/control-plane'; }
calico_pool()   {
  [ "$(k get installation default -o jsonpath='{.spec.calicoNetwork.ipPools[0].cidr}')" = "10.11.0.0/16" ] &&
  [ "$(k get installation default -o jsonpath='{.spec.calicoNetwork.ipPools[0].encapsulation}')" = "VXLAN" ]
}
calico_running(){
  local total notrun nodes
  total=$(k get pods -n calico-system --no-headers | wc -l)
  notrun=$(k get pods -n calico-system --no-headers | awk '$3!="Running"' | wc -l)
  nodes=$(k get ds calico-node -n calico-system -o jsonpath='{.status.numberReady}')
  [ "$total" -gt 0 ] && [ "$notrun" -eq 0 ] && [ "$nodes" = "3" ]
}
coredns_ready() { [ "$(k get deploy coredns -n kube-system -o jsonpath='{.status.readyReplicas}')" = "2" ]; }

check "kubectl로 API Server 접근"                    api_ok
check "노드 cap-master 등록"                          node_exists cap-master
check "노드 cap-node1 등록"                           node_exists cap-node1
check "노드 cap-node2 등록"                           node_exists cap-node2
check "노드 3대 모두 Ready"                           all_ready
check "kubelet 버전 v1.36.x"                          kubelet_136
check "컨테이너 런타임 containerd 2.x"                containerd_2
check "cap-master control-plane taint 유지"           cp_taint
check "Calico IPPool 10.11.0.0/16 · VXLAN"            calico_pool
check "calico-system Pod 모두 Running (calico-node 3개)" calico_running
check "CoreDNS Ready 2개"                             coredns_ready
summary
