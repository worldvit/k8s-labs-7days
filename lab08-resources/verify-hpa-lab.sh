#!/usr/bin/env bash
# Lab08 Part 3(공식 예제 HPA) 채점 — cap-master 노드 셸(root)에서 실행
# 사용: bash ~/k8s-labs-7days/lab08-resources/verify-hpa-lab.sh   (정리 단계 전에 실행)
# 누적 채점(verify-all.sh)에는 포함하지 않음
# 주의: 확장 이력은 Events(기본 1시간 보관)로 확인하므로, 태스크 10부터 1시간 안에 채점합니다.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
[ -f "$KUBECONFIG" ] || export KUBECONFIG=/etc/kubernetes/admin.conf
NS=hpa-lab
F="$HOME/hpa-lab/php-apache-hpa.yaml"
k() { kubectl "$@" 2>/dev/null; }
h() { k get hpa php-apache -n "$NS" -o jsonpath="$1"; }
rescale() { k get events -n "$NS" --field-selector reason=SuccessfulRescale -o jsonpath='{range .items[*]}{.message}{"\n"}{end}'; }
ge() { [ -n "$1" ] && [ "$1" -ge "$2" ] 2>/dev/null; }

echo "[Lab08 Part 3  공식 예제 HPA — php-apache · 노드 용량의 한계 · 확장 속도 제어]"
ns_ok()      { k get namespace "$NS"; }
app_ok()     { [ "$(k get deploy php-apache -n "$NS" -o jsonpath='{.spec.template.spec.containers[0].image}|{.spec.template.spec.containers[0].resources.requests.cpu}')" = "registry.k8s.io/hpa-example|200m" ] \
               && k get svc php-apache -n "$NS" >/dev/null; }
hpa_spec()   { [ "$(h '{.spec.minReplicas}|{.spec.maxReplicas}|{.spec.metrics[0].resource.name}|{.spec.metrics[0].resource.target.averageUtilization}')" = "1|4|cpu|50" ]; }
hpa_beh()    { [ "$(h '{.spec.behavior.scaleUp.policies[0].type}|{.spec.behavior.scaleUp.policies[0].value}|{.spec.behavior.scaleUp.policies[0].periodSeconds}|{.spec.behavior.scaleDown.stabilizationWindowSeconds}')" = "Pods|1|30|30" ] \
               && [ -f "$F" ] && grep -q 'autoscaling/v2' "$F"; }
hit_max()    { local m; m=$(rescale | sed -n 's/^New size: \([0-9]*\);.*/\1/p' | sort -n | tail -1); ge "$m" 6; }
pending_seen() { k get events -n "$NS" --field-selector reason=FailedScheduling -o jsonpath='{range .items[*]}{.message}{"\n"}{end}' | grep -q 'Insufficient cpu'; }
step_up()    { local m; m=$(rescale); echo "$m" | grep -q 'New size: 2;' && echo "$m" | grep -q 'New size: 3;' && echo "$m" | grep -q 'New size: 4;'; }
back_one()   { [ -z "$(k get pods -n "$NS" -l run=load -o name)" ] && [ "$(h '{.status.currentReplicas}')" = "1" ]; }
shop_ok()    { [ "$(k get hpa shop-api -n shop -o jsonpath='{.spec.minReplicas}|{.spec.maxReplicas}')" = "2|5" ] \
               && ge "$(k get deploy shop-api -n shop -o jsonpath='{.status.availableReplicas}')" 2; }

check "네임스페이스 hpa-lab 존재 (정리 전에 채점)"                         ns_ok
check "php-apache  공식 hpa-example 이미지 · requests cpu 200m · Service"  app_ok
check "HPA php-apache  1~4 · CPU 50% (선언형 v2)"                          hpa_spec
check "HPA behavior  scaleUp 30초마다 1개 · scaleDown 안정화 30초"          hpa_beh
check "명령형 HPA로 6개 이상(노드 수용량 초과)까지 확장한 기록"             hit_max
check "노드 용량 부족 Pending(FailedScheduling: Insufficient cpu) 관찰"     pending_seen
check "behavior 적용 후 2 → 3 → 4 단계적 확장 기록"                         step_up
check "부하 Pod 정리 · 1개로 축소 복귀"                                      back_one
check "본편 shop-api HPA 2~5 · 2개 이상 가용 유지"                          shop_ok
summary
