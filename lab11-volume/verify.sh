#!/usr/bin/env bash
# Lab11 채점 — cap-master 노드 셸(root)에서 실행
# 사용: bash ~/k8s-labs-7days/lab11-volume/verify.sh
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
[ -f "$KUBECONFIG" ] || export KUBECONFIG=/etc/kubernetes/admin.conf
k() { kubectl "$@" 2>/dev/null; }
g() { k get "$1" "$2" -n shop -o jsonpath="$3"; }
n1() { k get node cap-node1 -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}'; }
dbq() { echo "$1" | k exec -i -n shop shop-db-0 -c mysql -- sh -c 'printf "[client]\npassword=\"%s\"\n" "$MYSQL_PASSWORD" > /tmp/v.cnf; mysql --defaults-extra-file=/tmp/v.cnf -N -u shop shop; rc=$?; rm -f /tmp/v.cnf; exit $rc'; }

echo "[Lab11  Volume — emptyDir · hostPath · NFS · PV/PVC]"
nfs_server() { systemctl is-active --quiet nfs-server && exportfs -s | grep -q '^/srv/nfs/shop-db ' && exportfs -s | grep -q '^/srv/nfs/shop-share ' && ! exportfs -s | grep -q 'no_root_squash'; }
db_dir()     { [ "$(stat -c %u:%g /srv/nfs/shop-db)" = "999:999" ]; }
pv_db()      { [ "$(k get pv shop-db-pv -o jsonpath='{.spec.nfs.server}|{.spec.nfs.path}|{.spec.accessModes[0]}|{.spec.persistentVolumeReclaimPolicy}|{.status.phase}')" = "10.20.1.10|/srv/nfs/shop-db|ReadWriteOnce|Retain|Bound" ]; }
pvc_db()     { [ "$(g pvc shop-db-data '{.status.phase}|{.spec.volumeName}')" = "Bound|shop-db-pv" ]; }
share_ok()   { [ "$(k get pv shop-share-pv -o jsonpath='{.spec.nfs.path}|{.spec.accessModes[0]}|{.spec.persistentVolumeReclaimPolicy}|{.status.phase}')" = "/srv/nfs/shop-share|ReadWriteMany|Retain|Bound" ] && [ "$(g pvc shop-share '{.status.phase}|{.spec.volumeName}')" = "Bound|shop-share-pv" ]; }
sts_vol()    { [ "$(g sts shop-db '{.spec.template.spec.volumes[?(@.name=="data")].persistentVolumeClaim.claimName}')" = "shop-db-data" ] && [ -z "$(g sts shop-db '{.spec.template.spec.volumes[?(@.name=="data")].emptyDir}')" ]; }
sts_spec()   { [ "$(g sts shop-db '{.spec.template.spec.securityContext.runAsUser},{.spec.template.spec.containers[0].resources.requests.cpu},{.spec.template.spec.containers[0].resources.requests.memory},{.spec.template.spec.containers[0].resources.limits.cpu},{.spec.template.spec.containers[0].resources.limits.memory}')" = "999,250m,512Mi,500m,1Gi" ]; }
db_mount()   { [ "$(g pod shop-db-0 '{.status.conditions[?(@.type=="Ready")].status}')" = "True" ] && k exec -n shop shop-db-0 -c mysql -- cat /proc/mounts | grep -q ' /var/lib/mysql nfs4 '; }
marker()     { [ "$(dbq "SELECT note FROM lab11_marker WHERE id=1")" = "persist-ok" ]; }
e2e()        { curl -s -m 5 "http://$(n1):31080/api/products" | python3 -c 'import sys,json;d=json.load(sys.stdin);sys.exit(0 if d["source"]=="mysql" and len(d["items"])==5 else 1)'; }
cron_share() { [ "$(g cronjob shop-report '{.spec.jobTemplate.spec.template.spec.volumes[?(@.name=="report")].persistentVolumeClaim.claimName}|{.spec.jobTemplate.spec.template.spec.containers[0].volumeMounts[?(@.name=="report")].mountPath}')" = "shop-share|/report" ]; }
web_share()  { [ "$(g deploy shop-web '{.spec.template.spec.volumes[?(@.name=="report")].persistentVolumeClaim.claimName}|{.spec.template.spec.containers[?(@.name=="nginx")].volumeMounts[?(@.name=="report")].mountPath}|{.spec.template.spec.containers[?(@.name=="nginx")].volumeMounts[?(@.name=="report")].readOnly}|{.status.availableReplicas}')" = "shop-share|/usr/share/nginx/report|true|2" ] && g configmap shop-web-nginx '{.data.default\.conf}' | grep -q 'location /report/'; }
report_web() { curl -s -m 5 "http://$(n1):31080/report/products.log" | grep -q 'products=5'; }
lab_clean()  { [ -z "$( { k get pods,jobs -n shop -o name; k get pv -o name; } | grep 'lab11-')" ] && [ -z "$(k get pods -n default -o name | grep 'node-debugger-')" ]; }
file_sync()  { local d="$HOME/shop"; grep -q 'claimName: shop-db-data' "$d/shop-db-sts.yaml" && grep -q 'path: /srv/nfs/shop-db' "$d/shop-db-storage.yaml" && grep -q 'path: /srv/nfs/shop-share' "$d/shop-share-storage.yaml" && grep -q 'mountPath: /report' "$d/shop-report-cronjob.yaml" && grep -q 'claimName: shop-share' "$d/shop-web-deploy.yaml" && grep -q 'location /report/' "$d/shop-web-default.conf"; } 2>/dev/null

check "NFS 서버 · export 2개 (root_squash 유지)"               nfs_server
check "/srv/nfs/shop-db 소유자 999:999 (mysql)"                db_dir
check "PV shop-db-pv (NFS · RWO · Retain · Bound)"             pv_db
check "PVC shop-db-data → shop-db-pv Bound"                    pvc_db
check "PV/PVC shop-share (RWX · Retain · Bound)"               share_ok
check "shop-db 볼륨 data → PVC (emptyDir 제거)"                sts_vol
check "shop-db runAsUser 999 · 자원 250m·512Mi / 500m·1Gi"     sts_spec
check "shop-db-0 Ready · /var/lib/mysql = nfs4"                db_mount
check "Pod 재생성 후 표식 데이터 유지 (lab11_marker)"           marker
check "cap-node1:31080/api/products (mysql · 5개)"             e2e
check "CronJob shop-report → PVC shop-share (/report)"         cron_share
check "shop-web nginx → PVC shop-share 읽기 전용 · /report/ 설정" web_share
check "cap-node1:31080/report/products.log 응답"               report_web
check "연습 리소스(lab11-* · node-debugger) 정리"               lab_clean
check "~/shop 파일 동기화 (storage · sts · cronjob · web)"     file_sync
summary
