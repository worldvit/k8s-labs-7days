#!/usr/bin/env bash
# Lab05-B Part 2(확장) 채점 — cap-master 노드 셸(root)에서 실행
# 사용: bash ~/k8s-labs-7days/lab05b-workloads/verify-ext.sh   (정리 단계 전에 실행)
# 누적 채점(verify-all.sh)에는 포함하지 않음
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
[ -f "$KUBECONFIG" ] || export KUBECONFIG=/etc/kubernetes/admin.conf
k() { kubectl "$@" 2>/dev/null; }
g() { k get "$1" "$2" -n "${4:-ext}" -o jsonpath="$3"; }

echo "[Lab05-B Part 2  순서 · 병렬 · 실패 처리 · 노드 선택 — StatefulSet · Job · DaemonSet]"
ns_ext()      { k get namespace ext; }
sts_headless(){ [ "$(g svc ext-sts '{.spec.clusterIP}')" = "None" ] && [ "$(g sts ext-sts '{.spec.serviceName}')" = "ext-sts" ]; }
sts_final()   { [ "$(g sts ext-sts '{.spec.replicas},{.status.readyReplicas}')" = "1,1" ]; }
sts_image()   { [ "$(g sts ext-sts '{.spec.template.spec.containers[0].image}')" = "busybox:1.36" ] && [ "$(g pod ext-sts-0 '{.spec.containers[0].image}')" = "busybox:1.36" ]; }
sts_part()    { [ "$(g sts ext-sts '{.spec.updateStrategy.rollingUpdate.partition}')" = "0" ] && [ "$(g sts ext-sts '{.status.currentRevision}')" = "$(g sts ext-sts '{.status.updateRevision}')" ]; }
job_par()     { [ "$(g job ext-batch '{.spec.completions},{.spec.parallelism},{.status.succeeded}')" = "6,2,6" ]; }
job_fail()    { [ "$(g job ext-fail '{.status.conditions[?(@.type=="Failed")].reason}')" = "BackoffLimitExceeded" ] && [ "$(g job ext-fail '{.spec.backoffLimit},{.status.failed}')" = "2,3" ]; }
job_never()   { [ "$(g job ext-fail '{.spec.template.spec.restartPolicy}')" = "Never" ]; }
job_ttl()     { [ -f "$HOME/ext/ext-ttl.yaml" ] && ! k get job ext-ttl -n ext; }
ds_sel()      { [ "$(g ds ext-agent '{.spec.template.spec.nodeSelector.agent}')" = "ext" ]; }
ds_follow()   {
  [ "$(g ds ext-agent '{.status.desiredNumberScheduled},{.status.numberReady}')" = "1,1" ] &&
  [ "$(k get pods -n ext -l app=ext-agent -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort -u)" = "cap-node2" ]
}
n1_unlabel()  { [ -z "$(k get node cap-node1 -o jsonpath='{.metadata.labels.agent}')" ]; }
shop_ok()     { [ "$(g sts shop-db '{.status.readyReplicas}' shop)" = "1" ] && [ "$(g ds shop-log-agent '{.status.numberReady}' shop)" = "2" ]; }

check "네임스페이스 ext 존재 (정리 전에 채점)"                 ns_ext
check "ext-sts  Headless Service · serviceName"               sts_headless
check "ext-sts  replicas 1로 축소 · Ready"                     sts_final
check "ext-sts  busybox:1.36으로 전체 업데이트"                sts_image
check "ext-sts  partition 0 · 현재/갱신 revision 일치"         sts_part
check "ext-batch  completions 6 · parallelism 2 · 6개 성공"    job_par
check "ext-fail  backoffLimit 2 · 실패 3회 · BackoffLimitExceeded" job_fail
check "ext-fail  restartPolicy Never"                          job_never
check "ext-ttl  완료 후 자동 삭제됨"                           job_ttl
check "ext-agent  nodeSelector agent=ext"                   ds_sel
check "ext-agent  라벨을 따라 cap-node2에만 1개"               ds_follow
check "cap-node1 agent 라벨 제거"                          n1_unlabel
check "본편 shop-db · shop-log-agent 영향 없음"                shop_ok
summary
