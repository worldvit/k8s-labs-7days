#!/usr/bin/env bash
# Lab05-A Part 2(확장) 채점 — cap-master 노드 셸(root)에서 실행
# 사용: bash ~/k8s-labs-7days/lab05a-deployment/verify-ext.sh   (정리 단계 전에 실행)
# 누적 채점(verify-all.sh)에는 포함하지 않음
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
[ -f "$KUBECONFIG" ] || export KUBECONFIG=/etc/kubernetes/admin.conf
k() { kubectl "$@" 2>/dev/null; }
dj() { k get deploy "$1" -n "${2:-ext}" -o jsonpath="$3"; }
F="$HOME/ext/ext-roll.yaml"

echo "[Lab05-A Part 2  교체 방식과 이력 관리 — Recreate · set image · restart · revisionHistoryLimit]"
ns_ext()     { k get namespace ext; }
avail()      { [ "$(dj ext-roll ext '{.status.availableReplicas},{.spec.replicas}')" = "4,4" ]; }
recreate()   { [ "$(dj ext-roll ext '{.spec.strategy.type}')" = "Recreate" ] && [ -z "$(dj ext-roll ext '{.spec.strategy.rollingUpdate}')" ]; }
image129()   { [ "$(dj ext-roll ext '{.spec.template.spec.containers[?(@.name=="nginx")].image}')" = "nginx:1.29-alpine" ] && [ "$(dj ext-roll ext '{.spec.template.metadata.labels.version}')" = "1.29" ]; }
histlimit()  { [ "$(dj ext-roll ext '{.spec.revisionHistoryLimit}')" = "2" ]; }
rs_pruned()  { [ "$(k get rs -n ext -l app=ext-roll --no-headers | wc -l)" -le 3 ]; }
rev6()       { local r; r=$(k get deploy ext-roll -n ext -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}'); [ -n "$r" ] && [ "$r" -ge 6 ]; }
file_sync()  {
  [ -f "$F" ] && grep -q 'image: nginx:1.29-alpine' "$F" && grep -q 'type: Recreate' "$F" &&
  grep -q 'revisionHistoryLimit: 2' "$F" && ! grep -q 'rollingUpdate:' "$F"
}
shop_ok()    { [ "$(dj shop-api shop '{.status.availableReplicas}')" = "2" ] && [ "$(dj shop-api shop '{.spec.template.spec.containers[?(@.name=="api")].image}')" = "ghcr.io/worldvit/skillboost-api:v2" ]; }

check "네임스페이스 ext 존재 (정리 전에 채점)"               ns_ext
check "ext-roll  가용 4/4"                                   avail
check "ext-roll  전략 Recreate (rollingUpdate 없음)"        recreate
check "ext-roll  이미지 1.29 · 라벨 version=1.29 (revision 지정 롤백)" image129
check "ext-roll  revisionHistoryLimit 2"                     histlimit
check "ext-roll  ReplicaSet 3개 이하 (이력 정리됨)"          rs_pruned
check "ext-roll  revision 6 이상 (set image · restart · undo 수행)" rev6
check "~/ext/ext-roll.yaml 파일이 클러스터와 일치"           file_sync
check "본편 shop-api 영향 없음 (v2 · 2/2)"                   shop_ok
summary
