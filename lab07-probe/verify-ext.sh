#!/usr/bin/env bash
# Lab07 Part 2(확장) 채점 — cap-master 노드 셸(root)에서 실행
# 사용: bash ~/k8s-labs-7days/lab07-probe/verify-ext.sh   (정리 단계 전에 실행)
# 누적 채점(verify-all.sh)에는 포함하지 않음
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
[ -f "$KUBECONFIG" ] || export KUBECONFIG=/etc/kubernetes/admin.conf
k() { kubectl "$@" 2>/dev/null; }
p() { k get pod "$1" -n ext -o jsonpath="$2"; }

echo "[Lab07 Part 2  Probe 종류와 재시작 백오프 — exec · tcpSocket · CrashLoopBackOff]"
ns_ext()     { k get namespace ext; }
exec_spec()  { [ "$(p ext-exec '{.spec.containers[0].livenessProbe.exec.command[*]}')" = "cat /tmp/healthy" ]; }
exec_rst()   { [ "$(p ext-exec '{.status.containerStatuses[0].restartCount}')" -ge 1 ] 2>/dev/null; }
tcp_spec()   { [ "$(p ext-tcp '{.spec.containers[0].readinessProbe.tcpSocket.port}')" = "8080" ] && [ -z "$(p ext-tcp '{.spec.containers[0].livenessProbe}')" ]; }
tcp_ready()  { [ "$(p ext-tcp '{.status.conditions[?(@.type=="Ready")].status}')" = "True" ] && [ "$(p ext-tcp '{.status.containerStatuses[0].restartCount}')" = "0" ]; }
loop_rst()   { [ "$(p ext-loop '{.status.containerStatuses[0].restartCount}')" -ge 3 ] 2>/dev/null; }
loop_port()  { [ "$(p ext-loop '{.spec.containers[0].livenessProbe.httpGet.port}')" = "9999" ]; }
shop_ok()    { [ "$(k get deploy shop-api -n shop -o jsonpath='{.spec.template.spec.containers[0].startupProbe.httpGet.path}|{.status.availableReplicas}')" = "/healthz|2" ]; }

check "네임스페이스 ext 존재 (정리 전에 채점)"            ns_ext
check "ext-exec  exec Probe (cat /tmp/healthy)"          exec_spec
check "ext-exec  파일 삭제 후 재시작 1회 이상"            exec_rst
check "ext-tcp  tcpSocket readiness 8080 · liveness 없음" tcp_spec
check "ext-tcp  Ready · 재시작 0"                         tcp_ready
check "ext-loop  liveness 포트 9999 (응답 없는 포트)"     loop_port
check "ext-loop  재시작 3회 이상 (백오프 관찰)"           loop_rst
check "본편 shop-api Probe · 2개 가용 유지"               shop_ok
summary
