#!/usr/bin/env bash
# Lab12 Part 2(확장) 채점 (클러스터) — cap-master 노드 셸(root)에서 실행
# 사용: bash ~/k8s-labs-7days/lab12-aws/verify-ext.sh   (Part 2 정리 단계 전에 실행)
# 누적 채점(verify-all.sh)에는 포함하지 않음
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
[ -f "$KUBECONFIG" ] || export KUBECONFIG=/etc/kubernetes/admin.conf
k() { kubectl "$@" 2>/dev/null; }
g() { k get "$1" "$2" -n "${4:-ext}" -o jsonpath="$3"; }
node_az() { k get node cap-node1 -o jsonpath='{.metadata.labels.topology\.ebs\.csi\.aws\.com/zone}'; }

echo "[Lab12 Part 2  EBS 확장 · 볼륨 AZ · ALB 무중단 (클러스터)]"
ns_ext()     { k get namespace ext; }
grow_spec()  { [ "$(g pvc ext-data '{.status.phase}|{.spec.storageClassName}|{.spec.resources.requests.storage}|{.status.capacity.storage}')" = "Bound|gp3|2Gi|2Gi" ]; }
grow_fs()    {
  [ "$(g pod ext-vol '{.status.conditions[?(@.type=="Ready")].status}')" = "True" ] || return 1
  local kb; kb=$(k exec -n ext ext-vol -- df -k /data | awk 'NR==2{print $2}')
  [ -n "$kb" ] && [ "$kb" -ge 1800000 ]
}
grow_keep()  { k exec -n ext ext-vol -- cat /data/hello.txt | grep -q 'before-resize'; }
far_sc()     {
  local z; z=$(k get sc ext-far -o jsonpath='{.allowedTopologies[0].matchLabelExpressions[0].values[0]}')
  [ "$(k get sc ext-far -o jsonpath='{.provisioner}|{.volumeBindingMode}')" = "ebs.csi.aws.com|Immediate" ] &&
  [ -n "$z" ] && [ "$z" != "$(node_az)" ]
}
far_pv()     {
  local pv z; z=$(k get sc ext-far -o jsonpath='{.allowedTopologies[0].matchLabelExpressions[0].values[0]}')
  [ "$(g pvc ext-far '{.status.phase}')" = "Bound" ] || return 1
  pv=$(g pvc ext-far '{.spec.volumeName}')
  k get pv "$pv" -o jsonpath='{.spec.nodeAffinity.required.nodeSelectorTerms[*].matchExpressions[*].values[*]}' | grep -qw "$z"
}
far_pending(){
  [ "$(g pod ext-far '{.status.phase}')" = "Pending" ] &&
  g pod ext-far '{.status.conditions[?(@.type=="PodScheduled")].message}' | grep -q 'volume node affinity conflict'
}
files()      { [ -f "$HOME/ext/ext-data.yaml" ] && [ -f "$HOME/ext/ext-far.yaml" ] && grep -q 'storage: 2Gi' "$HOME/ext/ext-data.yaml"; }
web_roll()   {
  [ -n "$(g deploy shop-web '{.spec.template.metadata.annotations.kubectl\.kubernetes\.io/restartedAt}' shop)" ] &&
  [ "$(g deploy shop-web '{.status.updatedReplicas},{.status.availableReplicas}' shop)" = "2,2" ]
}
shop_ok()    { [ "$(g pvc shop-db-ebs '{.status.phase}' shop)" = "Bound" ] && [ "$(g pod shop-db-0 '{.status.conditions[?(@.type=="Ready")].status}' shop)" = "True" ]; }

check "네임스페이스 ext 존재 (정리 전에 채점)"                    ns_ext
check "ext-data  gp3 · 요청 2Gi · 실제 용량 2Gi (온라인 확장)"     grow_spec
check "ext-vol  Ready · /data 파일시스템 약 2G로 확장"             grow_fs
check "ext-vol  확장 전 데이터(before-resize) 유지"                grow_keep
check "StorageClass ext-far  Immediate · 노드와 다른 AZ 지정"       far_sc
check "ext-far  즉시 Bound · PV nodeAffinity = 지정 AZ"            far_pv
check "ext-far Pod  Pending · volume node affinity conflict"        far_pending
check "~/ext 파일 (ext-data.yaml 2Gi · ext-far.yaml)"               files
check "shop-web  rollout restart 흔적 · 2/2 가용"                   web_roll
check "본편 shop-db (EBS) 영향 없음"                                shop_ok
summary
