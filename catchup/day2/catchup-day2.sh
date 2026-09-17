#!/usr/bin/env bash
# 2일차(Lab03) 종료 상태로 shop 네임스페이스를 맞춘다 — cap-master 노드 셸(root)에서 실행
# 사용: bash ~/k8s-labs-7days/catchup.sh day2
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../.." && pwd)"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
echo "[catchup day2] shop 네임스페이스의 shop-api · shop-web · ConfigMap · Secret을 Lab03 종료 상태로 맞춥니다."
echo "  기존 shop-api · shop-web Pod는 삭제 후 다시 만듭니다 (Pod spec은 대부분 수정 불가)."
read -r -p "계속하려면 yes 입력: " ans; [ "$ans" = "yes" ] || { echo "취소했습니다."; exit 1; }

kubectl apply -f "$DIR/00-namespace.yaml"
kubectl apply -f "$DIR/10-shop-config.yaml"
kubectl create secret generic shop-db-secret -n shop --from-literal=DB_PASSWORD='ShopDB#2026' \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl create configmap shop-web-html -n shop --from-file=index.html="$REPO/app/shop-web/index.html" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl delete pod shop-api shop-web -n shop --ignore-not-found --wait=true
kubectl apply -f "$DIR/20-shop-api.yaml"
kubectl apply -f "$DIR/30-shop-web.yaml"
kubectl wait --for=condition=Ready pod/shop-api pod/shop-web -n shop --timeout=180s
echo "[catchup day2] 완료 — bash $REPO/lab03-pod/verify.sh 로 확인하세요."
