#!/usr/bin/env bash
# 5일차(Lab07 · Lab08 · Lab09) 종료 상태로 맞춘다 — cap-master 노드 셸(root)에서 실행
# 사용: bash ~/k8s-labs-7days/catchup.sh day5
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../.." && pwd)"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
echo "[catchup day5] 4일차 상태 위에 Probe · 자원 설정 · metrics-server · LimitRange · Quota · HPA를 5일차 종료 상태로 맞춥니다."
read -r -p "계속하려면 yes 입력: " ans; [ "$ans" = "yes" ] || { echo "취소했습니다."; exit 1; }

CATCHUP_YES=1 bash "$REPO/catchup/day4/catchup-day4.sh"

# Lab09 장애 흔적 제거 (Service selector · 템플릿은 아래 apply로 복구)
kubectl apply -f "$REPO/catchup/day4/45-shop-api-svc.yaml"

# Lab08: metrics-server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.9.0/components.yaml
if ! kubectl get deploy metrics-server -n kube-system -o jsonpath='{.spec.template.spec.containers[0].args}' | grep -q -- --kubelet-insecure-tls; then
  kubectl patch deploy metrics-server -n kube-system --type json -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
fi
kubectl rollout status deploy/metrics-server -n kube-system --timeout=180s

# Lab08: LimitRange → Quota (순서 중요)
kubectl apply -f "$DIR/30-shop-limits.yaml"
kubectl apply -f "$DIR/31-shop-quota.yaml"

# Lab07 · Lab08: shop-api (replicas 없는 manifest — last-applied 기록부터 교체)
kubectl apply set-last-applied -f "$DIR/10-shop-api-deploy.yaml" --create-annotation=true
kubectl apply -f "$DIR/10-shop-api-deploy.yaml"
[ "$(kubectl get deploy shop-api -n shop -o jsonpath='{.spec.replicas}')" -ge 2 ] || kubectl scale deploy shop-api -n shop --replicas=2
kubectl rollout status deploy/shop-api -n shop --timeout=300s
kubectl apply -f "$DIR/20-shop-web-deploy.yaml"
kubectl rollout status deploy/shop-web -n shop --timeout=300s
kubectl apply -f "$DIR/40-shop-api-hpa.yaml"

mkdir -p "$HOME/shop"
cp "$DIR/10-shop-api-deploy.yaml" "$HOME/shop/shop-api-deploy.yaml"
cp "$DIR/20-shop-web-deploy.yaml" "$HOME/shop/shop-web-deploy.yaml"
cp "$DIR/30-shop-limits.yaml" "$HOME/shop/shop-limits.yaml"
cp "$DIR/31-shop-quota.yaml" "$HOME/shop/shop-quota.yaml"
cp "$DIR/40-shop-api-hpa.yaml" "$HOME/shop/shop-api-hpa.yaml"
echo "[catchup day5] 완료 — 확인: bash $REPO/verify-all.sh day5"
echo "  참고: HPA 확장 이력(lastScaleTime)은 부하를 준 적이 없으면 비어 있어 Lab08 채점 1개 항목이 FAIL일 수 있습니다."
