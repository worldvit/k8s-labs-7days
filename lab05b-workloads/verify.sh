#!/usr/bin/env bash
# Lab05-B 채점 — cap-master 노드 셸(root)에서 실행
# 사용: bash ~/k8s-labs-7days/lab05b-workloads/verify.sh
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
[ -f "$KUBECONFIG" ] || export KUBECONFIG=/etc/kubernetes/admin.conf
k() { kubectl "$@" 2>/dev/null; }
g() { k get "$1" "$2" -n shop -o jsonpath="$3"; }

echo "[Lab05-B  DaemonSet · StatefulSet · Job · CronJob]"
ds_count()   { [ "$(g ds shop-log-agent '{.status.desiredNumberScheduled},{.status.numberReady}')" = "2,2" ]; }
ds_nodes()   { [ "$(k get pods -n shop -l tier=log-agent -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort | tr '\n' ' ')" = "cap-node1 cap-node2 " ]; }
ds_tol()     { g ds shop-log-agent '{range .spec.template.spec.tolerations[*]}{.key}={.value}:{.effect}{"\n"}{end}' | grep -qx 'dedicated=db:NoSchedule'; }
ds_host()    { [ "$(g ds shop-log-agent '{.spec.template.spec.volumes[?(@.name=="pod-logs")].hostPath.path},{.spec.template.spec.containers[0].volumeMounts[?(@.name=="pod-logs")].readOnly}')" = "/var/log/pods,true" ]; }
svc_head()   { [ "$(g svc shop-db '{.spec.clusterIP},{.spec.ports[0].port}')" = "None,3306" ]; }
sts_ready()  { [ "$(g sts shop-db '{.status.readyReplicas},{.spec.serviceName}')" = "1,shop-db" ]; }
sts_node()   { [ "$(g pod shop-db-0 '{.spec.nodeName}')" = "cap-node2" ]; }
sts_place()  { [ "$(g sts shop-db '{.spec.template.spec.nodeSelector.disk}')" = "ssd" ] && g sts shop-db '{range .spec.template.spec.tolerations[*]}{.key}{"\n"}{end}' | grep -qx dedicated; }
sts_secret() { [ "$(g sts shop-db '{.spec.template.spec.containers[0].env[?(@.name=="MYSQL_PASSWORD")].valueFrom.secretKeyRef.name}')" = "shop-db-secret" ]; }
job_done()   { [ "$(g job shop-db-seed '{.status.succeeded}')" = "1" ]; }
db_rows()    {
  local n; n=$(k exec -n shop shop-db-0 -c mysql -- sh -c 'printf "[client]\npassword=\"%s\"\n" "$MYSQL_PASSWORD" > /tmp/v.cnf && mysql --defaults-extra-file=/tmp/v.cnf -N -u shop shop -e "SELECT COUNT(*) FROM products"; rm -f /tmp/v.cnf')
  [ "$n" = "5" ]
}
cron_spec()  { [ "$(g cronjob shop-report '{.spec.schedule}|{.spec.timeZone}|{.spec.concurrencyPolicy}|{.spec.suspend}')" = "*/2 * * * *|Asia/Seoul|Forbid|false" ]; }
cron_ran()   { [ -n "$(g cronjob shop-report '{.status.lastSuccessfulTime}')" ]; }
deploys()    { [ "$(g deploy shop-api '{.status.availableReplicas}')" = "2" ] && [ "$(g deploy shop-web '{.status.availableReplicas}')" = "2" ]; }

check "DaemonSet shop-log-agent 2/2 Ready"                   ds_count
check "shop-log-agent가 cap-node1 · cap-node2에 1개씩"         ds_nodes
check "shop-log-agent toleration dedicated=db"               ds_tol
check "shop-log-agent hostPath /var/log/pods 읽기 전용"        ds_host
check "Headless Service shop-db (None · 3306)"               svc_head
check "StatefulSet shop-db Ready · serviceName"              sts_ready
check "shop-db-0이 cap-node2에 배치"                          sts_node
check "shop-db nodeSelector disk=ssd · toleration"           sts_place
check "shop-db 비밀번호 ← Secret shop-db-secret"              sts_secret
check "Job shop-db-seed 완료"                                job_done
check "products 테이블 5행"                                   db_rows
check "CronJob shop-report 스케줄 · 시간대 · Forbid · 실행 중"  cron_spec
check "CronJob shop-report 성공 실행 이력"                    cron_ran
check "shop-api · shop-web Deployment 유지 (2/2)"            deploys
summary
