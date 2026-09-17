#!/usr/bin/env bash
# Lab12 채점 (클러스터) — cap-master 노드 셸(root)에서 실행
# 사용: bash ~/k8s-labs-7days/lab12-aws/verify.sh
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
[ -f "$KUBECONFIG" ] || export KUBECONFIG=/etc/kubernetes/admin.conf
k() { kubectl "$@" 2>/dev/null; }
g() { k get "$1" "$2" -n shop -o jsonpath="$3"; }
n1() { k get node cap-node1 -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}'; }
dbq() { echo "$1" | k exec -i -n shop shop-db-0 -c mysql -- sh -c 'printf "[client]\npassword=\"%s\"\n" "$MYSQL_PASSWORD" > /tmp/v.cnf; mysql --defaults-extra-file=/tmp/v.cnf -N -u shop shop; rc=$?; rm -f /tmp/v.cnf; exit $rc'; }

echo "[Lab12  AWS 연동 — EBS CSI · gp3 · shop-db 이전 (클러스터)]"
helm_ok()   { helm list -n kube-system -f '^aws-ebs-csi-driver$' -o json 2>/dev/null | python3 -c 'import sys,json;r=json.load(sys.stdin);sys.exit(0 if r and r[0]["chart"]=="aws-ebs-csi-driver-2.66.0" and r[0]["status"]=="deployed" else 1)'; }
driver_up() { [ "$(k get deploy ebs-csi-controller -n kube-system -o jsonpath='{.status.availableReplicas}')" -ge 1 ] 2>/dev/null && [ "$(k get ds ebs-csi-node -n kube-system -o jsonpath='{.status.numberReady}/{.status.desiredNumberScheduled}')" = "3/3" ]; }
csinode()   { for n in cap-node1 cap-node2; do k get csinode "$n" -o jsonpath='{.spec.drivers[*].name}' | grep -qw ebs.csi.aws.com || return 1; done; }
sc_ok()     { [ "$(k get sc gp3 -o jsonpath='{.provisioner}|{.volumeBindingMode}|{.reclaimPolicy}|{.parameters.type}|{.parameters.csi\.storage\.k8s\.io/fstype}')" = "ebs.csi.aws.com|WaitForFirstConsumer|Delete|gp3|xfs" ]; }
pvc_ebs()   { local pv; [ "$(g pvc shop-db-ebs '{.status.phase}|{.spec.storageClassName}')" = "Bound|gp3" ] && pv=$(g pvc shop-db-ebs '{.spec.volumeName}') && [ "$(k get pv "$pv" -o jsonpath='{.spec.csi.driver}')" = "ebs.csi.aws.com" ] && k get pv "$pv" -o jsonpath='{.spec.csi.volumeHandle}' | grep -q '^vol-'; }
sts_ebs()   { [ "$(g sts shop-db '{.spec.template.spec.volumes[?(@.name=="data")].persistentVolumeClaim.claimName}|{.spec.template.spec.securityContext.runAsUser}|{.spec.template.spec.securityContext.fsGroup}')" = "shop-db-ebs|999|999" ]; }
db_mount()  { [ "$(g pod shop-db-0 '{.status.conditions[?(@.type=="Ready")].status}')" = "True" ] && k exec -n shop shop-db-0 -c mysql -- cat /proc/mounts | grep -q ' /var/lib/mysql xfs '; }
migrated()  { [ "$(dbq "SELECT note FROM lab11_marker WHERE id=1")" = "persist-ok" ] && [ "$(dbq "SELECT COUNT(*) FROM products")" = "5" ]; }
e2e()       { curl -s -m 5 "http://$(n1):31080/api/products" | python3 -c 'import sys,json;d=json.load(sys.stdin);sys.exit(0 if d["source"]=="mysql" and len(d["items"])==5 else 1)'; }
backup()    { local f="$HOME/shop/backup/shop-lab12.sql"; grep -q 'CREATE TABLE `products`' "$f" && grep -q 'CREATE TABLE `lab11_marker`' "$f"; } 2>/dev/null
nfs_kept()  { [ "$(k get pv shop-db-pv -o jsonpath='{.spec.persistentVolumeReclaimPolicy}')" = "Retain" ]; }
lab_clean() { [ -z "$( { k get pods,pvc -n shop -o name; k get pv -o jsonpath='{range .items[*]}{.spec.claimRef.name}{"\n"}{end}'; } | grep 'lab12-')" ]; }
file_sync() { local d="$HOME/shop"; grep -q 'region: ap-northeast-2' "$d/ebs-csi-values.yaml" && grep -q 'provisioner: ebs.csi.aws.com' "$d/gp3-sc.yaml" && grep -q 'storageClassName: gp3' "$d/shop-db-ebs-pvc.yaml" && grep -q 'claimName: shop-db-ebs' "$d/shop-db-sts.yaml"; } 2>/dev/null

check "Helm 릴리스 aws-ebs-csi-driver (차트 2.66.0 · deployed)"  helm_ok
check "EBS CSI 컨트롤러 가용 · 노드 플러그인 3/3"             driver_up
check "CSINode에 ebs.csi.aws.com 등록 (cap-node1 · cap-node2)" csinode
check "StorageClass gp3 (WaitForFirstConsumer · Delete · xfs)" sc_ok
check "PVC shop-db-ebs Bound → EBS 볼륨(vol-)"                 pvc_ebs
check "shop-db 볼륨 → shop-db-ebs · runAsUser/fsGroup 999"     sts_ebs
check "shop-db-0 Ready · /var/lib/mysql = xfs"                 db_mount
check "이전된 데이터 (lab11_marker · 상품 5행)"                 migrated
check "cap-node1:31080/api/products (mysql · 5개)"             e2e
check "백업 파일 ~/shop/backup/shop-lab12.sql"                 backup
check "NFS PV shop-db-pv 보존 (Retain · 롤백 경로)"            nfs_kept
check "연습 리소스(lab12-*) 정리"                              lab_clean
check "~/shop 파일 동기화 (values · sc · pvc · sts)"           file_sync
summary
