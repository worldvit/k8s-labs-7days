#!/usr/bin/env bash
# Lab11 Part 2(확장) 채점 — cap-master 노드 셸(root)에서 실행
# 사용: bash ~/k8s-labs-7days/lab11-volume/verify-ext.sh   (정리 단계 전에 실행)
# 누적 채점(verify-all.sh)에는 포함하지 않음
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
[ -f "$KUBECONFIG" ] || export KUBECONFIG=/etc/kubernetes/admin.conf
k() { kubectl "$@" 2>/dev/null; }
g() { k get "$1" "$2" -n "${4:-ext}" -o jsonpath="$3"; }

echo "[Lab11 Part 2  PV/PVC 바인딩 규칙 · subPathExpr · PVC 보호 · Released PV 재사용]"
ns_ext()    { k get namespace ext; }
pv_small()  { [ "$(k get pv ext-pv-small -o jsonpath='{.status.phase}|{.spec.claimRef.name}')" = "Bound|ext-claim-sel" ]; }
pvc_sel()   { [ "$(g pvc ext-claim-sel '{.spec.selector.matchLabels.size}|{.status.capacity.storage}')" = "small|1Gi" ]; }
reuse()     { [ "$(g pvc ext-claim-again '{.status.phase}|{.spec.volumeName}|{.status.capacity.storage}')" = "Bound|ext-pv-big|3Gi" ]; }
old_gone()  { ! k get pvc ext-claim-2g -n ext && ! k get pvc ext-claim-5g -n ext; }
writer()    {
  [ "$(g deploy ext-writer '{.status.availableReplicas}')" = "2" ] &&
  [ "$(g deploy ext-writer '{.spec.template.spec.volumes[0].persistentVolumeClaim.claimName}')" = "ext-claim-again" ] &&
  [ "$(g deploy ext-writer '{.spec.template.spec.containers[0].volumeMounts[0].subPathExpr}')" = '$(POD_NAME)' ]
}
dirs()      { [ "$(find /srv/nfs/shop-share/ext -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)" -ge 4 ]; }
shop_ok()   { [ "$(g pvc shop-db-data '{.status.phase}' shop)" = "Bound" ] && [ "$(g pvc shop-share '{.status.phase}' shop)" = "Bound" ] && [ "$(g sts shop-db '{.status.readyReplicas}' shop)" = "1" ]; }

check "네임스페이스 ext 존재 (정리 전에 채점)"                     ns_ext
check "ext-pv-small ← ext-claim-sel (라벨 selector로 바인딩)"     pv_small
check "ext-claim-sel 용량 1Gi (PV 크기로 표시)"                    pvc_sel
check "ext-claim-again → Released였던 ext-pv-big 재사용 (3Gi)"     reuse
check "ext-claim-2g · ext-claim-5g 삭제됨"                         old_gone
check "ext-writer 2/2 · PVC ext-claim-again · subPathExpr"         writer
check "NFS 서버 /srv/nfs/shop-share/ext 아래 Pod별 폴더 4개 이상"  dirs
check "본편 shop-db · shop-share PVC · shop-db Ready 유지"         shop_ok
summary
