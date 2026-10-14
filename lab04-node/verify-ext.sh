#!/usr/bin/env bash
# Lab04 Part 2(확장) 채점 — cap-master 노드 셸(root)에서 실행
# 사용: bash ~/k8s-labs-7days/lab04-node/verify-ext.sh   (정리 단계 전에 실행)
# 누적 채점(verify-all.sh)에는 포함하지 않음
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
[ -f "$KUBECONFIG" ] || export KUBECONFIG=/etc/kubernetes/admin.conf
k() { kubectl "$@" 2>/dev/null; }
dj() { k get deploy "$1" -n ext -o jsonpath="$2"; }

echo "[Lab04 Part 2  분산 배치와 중단 예산 — antiAffinity · topologySpread · PDB]"
ns_ext()      { k get namespace ext; }
anti_pref()   {
  [ -n "$(dj ext-anti '{.spec.template.spec.affinity.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution[0].weight}')" ] &&
  [ -z "$(dj ext-anti '{.spec.template.spec.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution}')" ] &&
  [ "$(dj ext-anti '{.spec.template.spec.affinity.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution[0].podAffinityTerm.topologyKey}')" = "kubernetes.io/hostname" ]
}
spread_rule() {
  [ "$(dj ext-spread '{.spec.template.spec.topologySpreadConstraints[0].maxSkew},{.spec.template.spec.topologySpreadConstraints[0].topologyKey},{.spec.template.spec.topologySpreadConstraints[0].whenUnsatisfiable}')" = "1,kubernetes.io/hostname,DoNotSchedule" ]
}
spread_honor(){ [ "$(dj ext-spread '{.spec.template.spec.topologySpreadConstraints[0].nodeTaintsPolicy}')" = "Honor" ]; }
pdb_min()     { [ "$(k get pdb ext-web-pdb -n ext -o jsonpath='{.spec.minAvailable}')" = "1" ] && [ "$(k get pdb ext-web-pdb -n ext -o jsonpath='{.spec.selector.matchLabels.app}')" = "ext-web" ]; }
web_avail()   { [ "$(dj ext-web '{.status.availableReplicas}')" = "2" ]; }
web_moved()   {
  local nodes; nodes=$(k get pods -n ext -l app=ext-web -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort -u)
  [ "$nodes" = "cap-node2" ]
}
n1_sched()    { [ "$(k get node cap-node1 -o jsonpath='{.spec.unschedulable}')" != "true" ]; }
n2_sched()    { [ "$(k get node cap-node2 -o jsonpath='{.spec.unschedulable}')" != "true" ]; }
n2_taint()    { [ "$(k get node cap-node2 -o jsonpath='{range .spec.taints[*]}{.key}={.value}:{.effect}{"\n"}{end}')" = "dedicated=db:NoSchedule" ]; }
shop_clean()  { [ -z "$(k get deploy,pdb,pods -n shop -o name | grep -E '/ext-')" ]; }

check "네임스페이스 ext 존재 (정리 전에 채점)"                 ns_ext
check "ext-anti  preferred podAntiAffinity (hostname 기준)"   anti_pref
check "ext-spread  maxSkew 1 · hostname · DoNotSchedule"      spread_rule
check "ext-spread  nodeTaintsPolicy Honor"                     spread_honor
check "ext-web-pdb  minAvailable 1 · selector app=ext-web"     pdb_min
check "ext-web  가용 2/2"                                      web_avail
check "ext-web  drain 후 모두 cap-node2로 이동"                web_moved
check "cap-node1 uncordon (스케줄 가능)"                       n1_sched
check "cap-node2 스케줄 가능"                                  n2_sched
check "cap-node2 taint는 dedicated=db:NoSchedule 하나만"       n2_taint
check "shop 네임스페이스에 확장 리소스 없음"                   shop_clean
summary
