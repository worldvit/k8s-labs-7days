#!/usr/bin/env bash
# 4일차(Lab05-B · Lab06) 종료 상태로 맞춘다 — cap-master 노드 셸(root)에서 실행
# 사용: bash ~/k8s-labs-7days/catchup.sh day4
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../.." && pwd)"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
echo "[catchup day4] 3일차 상태 위에 DaemonSet · StatefulSet · Job · CronJob · Service를 4일차 종료 상태로 맞춥니다."
echo "  shop-db 데이터가 비어 있으면 초기 데이터를 다시 적재합니다. AWS 보안 그룹 30080 규칙은 직접 추가해야 합니다."
read -r -p "계속하려면 yes 입력: " ans; [ "$ans" = "yes" ] || { echo "취소했습니다."; exit 1; }

CATCHUP_YES=1 bash "$REPO/catchup/day3/catchup-day3.sh"

# Lab05-B
kubectl apply -f "$DIR/60-shop-log-agent.yaml" -f "$DIR/70-shop-db-svc.yaml" -f "$DIR/71-shop-db-sts.yaml"
kubectl rollout status ds/shop-log-agent -n shop --timeout=180s
kubectl rollout status sts/shop-db -n shop --timeout=300s
q() { kubectl exec -n shop shop-db-0 -c mysql -- sh -c 'printf "[client]\npassword=\"%s\"\n" "$MYSQL_PASSWORD" > /tmp/c.cnf && mysql --defaults-extra-file=/tmp/c.cnf -N -u shop shop -e "'"$1"'" 2>/dev/null; rm -f /tmp/c.cnf'; }
echo "MySQL 준비 대기..."; for i in $(seq 1 60); do q "SELECT 1" | grep -qx 1 && break; sleep 5; done
kubectl create configmap shop-db-seed-sql -n shop --from-file=schema-seed.sql="$REPO/app/shop-db/schema-seed.sql" --dry-run=client -o yaml | kubectl apply -f -
if [ "$(q 'SELECT COUNT(*) FROM products' || true)" != "5" ]; then
  kubectl delete job shop-db-seed -n shop --ignore-not-found --wait=true
  kubectl apply -f "$DIR/80-shop-db-seed-job.yaml"
  kubectl wait --for=condition=complete job/shop-db-seed -n shop --timeout=300s
fi
kubectl apply -f "$DIR/90-shop-report-cronjob.yaml"

# Lab06
kubectl apply -f "$DIR/45-shop-api-svc.yaml"
kubectl patch configmap shop-config -n shop --type merge -p '{"data":{"DB_MODE":"mysql"}}'
kubectl rollout restart deploy/shop-api -n shop
kubectl rollout status deploy/shop-api -n shop --timeout=180s
kubectl create configmap shop-web-nginx -n shop --from-file=default.conf="$REPO/app/shop-web/default.conf" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "$DIR/50-shop-web-deploy-v2.yaml"
kubectl rollout status deploy/shop-web -n shop --timeout=180s
kubectl apply -f "$DIR/55-shop-web-svc.yaml"
kubectl delete svc -n shop lab06-broken lab06-lb --ignore-not-found

# 교육생 작업 파일 갱신
mkdir -p "$HOME/shop"
cp "$DIR/50-shop-web-deploy-v2.yaml" "$HOME/shop/shop-web-deploy.yaml"
cp "$DIR/45-shop-api-svc.yaml" "$HOME/shop/shop-api-svc.yaml"
cp "$DIR/55-shop-web-svc.yaml" "$HOME/shop/shop-web-svc.yaml"
cp "$DIR/60-shop-log-agent.yaml" "$HOME/shop/shop-log-agent.yaml"
cp "$DIR/70-shop-db-svc.yaml" "$HOME/shop/shop-db-svc.yaml"
cp "$DIR/71-shop-db-sts.yaml" "$HOME/shop/shop-db-sts.yaml"
cp "$DIR/80-shop-db-seed-job.yaml" "$HOME/shop/shop-db-seed-job.yaml"
cp "$DIR/90-shop-report-cronjob.yaml" "$HOME/shop/shop-report-cronjob.yaml"
cp "$REPO/catchup/day2/10-shop-config.yaml" "$HOME/shop/shop-config.yaml"
sed -i 's|DB_MODE: "memory"|DB_MODE: "mysql"|' "$HOME/shop/shop-config.yaml"
echo "[catchup day4] 완료 — 확인: bash $REPO/lab06-service/verify.sh  (보안 그룹은 CloudShell에서 verify-aws.sh)"
