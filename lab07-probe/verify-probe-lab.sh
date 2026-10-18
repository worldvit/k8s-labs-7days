#!/usr/bin/env bash
# Lab07 Part 3(공식 예제 Probe) 채점 — cap-master 노드 셸(root)에서 실행
# 사용: bash ~/k8s-labs-7days/lab07-probe/verify-probe-lab.sh   (정리 단계 전에 실행)
# 누적 채점(verify-all.sh)에는 포함하지 않음
# shellcheck disable=SC2088  # 라벨 문자열의 ~ 는 표시용
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
[ -f "$KUBECONFIG" ] || export KUBECONFIG=/etc/kubernetes/admin.conf
NS=probe-lab
F="$HOME/probe-lab/pl-api.yaml"
k() { kubectl "$@" 2>/dev/null; }
p() { k get pod "$1" -n "$NS" -o jsonpath="$2"; }
rst() { p "$1" '{.status.containerStatuses[0].restartCount}'; }
ge() { [ -n "$1" ] && [ "$1" -ge "$2" ] 2>/dev/null; }

echo "[Lab07 Part 3  공식 예제 Probe — 재시작의 의미 · 느린 기동 · 설정 실수]"
ns_ok()      { k get namespace "$NS"; }
web_spec()   { [ "$(p pl-web '{.spec.containers[0].livenessProbe.httpGet.path}|{.spec.containers[0].livenessProbe.httpGet.port}')" = "/|80" ] && ge "$(rst pl-web)" 1; }
web_files()  { k exec pl-web -n "$NS" -- sh -c 'test -f /usr/share/nginx/html/index.html && ! test -e /usr/share/nginx/html/note.txt && test -f /data/keep.txt'; }
none_loop()  { [ -z "$(p pl-none '{.spec.containers[0].livenessProbe.initialDelaySeconds}')" ] && [ -z "$(p pl-none '{.spec.containers[0].startupProbe}')" ] && ge "$(rst pl-none)" 2; }
delay_ok()   { ge "$(p pl-delay '{.spec.containers[0].livenessProbe.initialDelaySeconds}')" 25 && [ "$(rst pl-delay)" = "0" ]; }
start_ok()   { [ "$(p pl-startup '{.spec.containers[0].startupProbe.periodSeconds}|{.spec.containers[0].startupProbe.failureThreshold}')" = "3|10" ] \
               && [ "$(rst pl-startup)" = "0" ] \
               && [ "$(p pl-startup '{.status.containerStatuses[0].started}|{.status.containerStatuses[0].ready}')" = "true|true" ]; }
file_fix()   { [ -f "$F" ] && grep -q 'tcpSocket:' "$F" && grep -Eq 'port: 80$' "$F" && ! grep -Eq 'port: 22$' "$F"; }
api_fix()    { [ "$(k get deploy pl-api -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.tcpSocket.port}|{.status.availableReplicas}')" = "80|1" ] || return 1
               local P; P=$(k get pods -n "$NS" -l app=pl-api --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')
               [ -n "$P" ] && [ "$(rst "$P")" = "0" ]; }
shop_ok()    { local v; v=$(k get deploy shop-api -n shop -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.httpGet.path}|{.spec.template.spec.containers[0].readinessProbe.httpGet.path}|{.status.availableReplicas}')
               [ "${v%|*}" = "/healthz|/readyz" ] && ge "${v##*|}" 2; }

check "네임스페이스 probe-lab 존재 (정리 전에 채점)"                      ns_ok
check "pl-web  httpGet / :80 liveness · index.html 삭제로 재시작 1회 이상"  web_spec
check "pl-web  재시작 후 index.html 복구 · note.txt 사라짐 · /data 유지"    web_files
check "pl-none  지연 없는 liveness → 재시작 반복(2회 이상)"                 none_loop
check "pl-delay  initialDelaySeconds 25 이상 · 재시작 0"                    delay_ok
check "pl-startup  startupProbe 3초 × 10회 · 재시작 0 · started · ready"   start_ok
check "~/probe-lab/pl-api.yaml  tcpSocket 포트 22 → 80 수정"               file_fix
check "pl-api  liveness tcpSocket 80 · 1/1 가용 · 새 Pod 재시작 0"          api_fix
check "본편 shop-api Probe(/healthz · /readyz) · 2개 이상 가용 유지"        shop_ok
summary
