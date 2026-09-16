#!/usr/bin/env bash
# 3일차(Lab04 · Lab05-A) 종료 상태로 맞춘다 — cap-master 노드 셸(root)에서 실행
# 사용: bash ~/k8s-labs-7days/catchup.sh day3
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../.." && pwd)"
DAY2="$REPO/catchup/day2"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
echo "[catchup day3] 노드 역할(라벨 · taint)과 shop-api · shop-web Deployment를 3일차 종료 상태로 맞춥니다."
echo "  shop 네임스페이스의 직접 만든 Pod는 삭제되고, shop-api는 v1 → v2 두 번 배포됩니다."
read -r -p "계속하려면 yes 입력: " ans; [ "$ans" = "yes" ] || { echo "취소했습니다."; exit 1; }

# 노드 역할 (Lab04)
kubectl uncordon cap-node1 cap-node2 >/dev/null
kubectl label node cap-node1 tier=front --overwrite
kubectl label node cap-node2 disk=ssd --overwrite
kubectl taint nodes cap-node2 maintenance- 2>/dev/null || true
kubectl taint nodes cap-node2 dedicated=db:NoSchedule --overwrite

# 설정 (Lab03)
kubectl apply -f "$DAY2/00-namespace.yaml" -f "$DAY2/10-shop-config.yaml"
kubectl create secret generic shop-db-secret -n shop --from-literal=DB_PASSWORD='ShopDB#2026' --dry-run=client -o yaml | kubectl apply -f -
kubectl create configmap shop-web-html -n shop --from-file=index.html="$REPO/app/shop-web/index.html" --dry-run=client -o yaml | kubectl apply -f -

# 직접 만든 Pod · 연습 리소스 정리
for P in $(kubectl get pods -n shop --no-headers -o custom-columns=NAME:.metadata.name,OWNER:.metadata.ownerReferences[0].kind | awk '$2=="<none>"{print $1}'); do
  kubectl delete pod "$P" -n shop --wait=false
done
kubectl delete rs -n shop -l app=lab05 --ignore-not-found
kubectl delete pods -n shop -l app=lab05 --ignore-not-found

# Deployment (Lab05-A)
if ! kubectl get deploy shop-api -n shop >/dev/null 2>&1; then
  kubectl apply -f "$DIR/40-shop-api-deploy-v1.yaml"
  kubectl rollout status deploy/shop-api -n shop --timeout=180s
fi
kubectl apply -f "$DIR/41-shop-api-deploy-v2.yaml"
kubectl rollout status deploy/shop-api -n shop --timeout=180s
kubectl apply -f "$DIR/50-shop-web-deploy.yaml"
kubectl rollout status deploy/shop-web -n shop --timeout=180s

mkdir -p "$HOME/shop"
cp "$DIR/41-shop-api-deploy-v2.yaml" "$HOME/shop/shop-api-deploy.yaml"
cp "$DIR/50-shop-web-deploy.yaml" "$HOME/shop/shop-web-deploy.yaml"
echo "[catchup day3] 완료 — ~/shop/shop-api-deploy.yaml · shop-web-deploy.yaml 을 갱신했습니다."
echo "  확인: bash $REPO/lab05a-deployment/verify.sh"
