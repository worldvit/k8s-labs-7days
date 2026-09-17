#!/usr/bin/env bash
# 6일차(Lab10 · Lab11) 종료 상태로 맞춘다 — cap-master 노드 셸(root)에서 실행
# 사용: bash ~/k8s-labs-7days/catchup.sh day6
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../.." && pwd)"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
echo "[catchup day6] 5일차 상태 위에 Helm · NGF · Gateway(Lab10)와 NFS · PV/PVC · shop-db 영구화(Lab11)를 6일차 종료 상태로 맞춥니다."
echo "  AWS 보안 그룹 31080 규칙(Lab10 단계 19)은 직접 설정해야 합니다. shop-db가 emptyDir이면 데이터는 초기 데이터로 다시 적재됩니다."
if [ "${CATCHUP_YES:-}" != "1" ]; then read -r -p "계속하려면 yes 입력: " ans; [ "$ans" = "yes" ] || { echo "취소했습니다."; exit 1; }; fi

CATCHUP_YES=1 bash "$REPO/catchup/day5/catchup-day5.sh"

q() { echo "$1" | kubectl exec -i -n shop shop-db-0 -c mysql -- sh -c 'printf "[client]\npassword=\"%s\"\n" "$MYSQL_PASSWORD" > /tmp/c.cnf; mysql --defaults-extra-file=/tmp/c.cnf -N -u shop shop 2>/dev/null; rc=$?; rm -f /tmp/c.cnf; exit $rc'; }
dbwait() { for _ in $(seq 1 60); do [ "$(q 'SELECT 1' || true)" = "1" ] && return 0; sleep 5; done; echo "MySQL 준비 시간 초과"; return 1; }
nodeshell() {  # nodeshell <노드> '<명령>' — kubectl debug node로 노드 호스트에서 명령 실행
  local p
  p=$(kubectl debug "node/$1" -n default --image=busybox:1.37 --profile=sysadmin -- chroot /host sh -c "$2" | awk '{print $4}')
  kubectl wait "pod/$p" -n default --for=jsonpath='{.status.phase}'=Succeeded --timeout=300s
  kubectl logs "$p" -n default
  kubectl delete pod "$p" -n default --wait=false
}

# ---------- Lab10: Helm · Gateway API CRD · NGF · Gateway · HTTPRoute ----------
if ! helm version --short 2>/dev/null | grep -q '^v4\.3\.0'; then
  curl -fsSL -o /tmp/get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
  DESIRED_VERSION=v4.3.0 bash /tmp/get_helm.sh
fi
kubectl kustomize "https://github.com/nginx/nginx-gateway-fabric/config/crd/gateway-api/standard?ref=v2.7.1" | kubectl apply -f -
CHART=oci://ghcr.io/nginx/charts/nginx-gateway-fabric
if ! helm status ngf -n nginx-gateway >/dev/null 2>&1; then
  helm install ngf $CHART --version 2.7.1 -n nginx-gateway --create-namespace -f "$DIR/01-ngf-values.yaml" --wait --timeout 5m
  helm upgrade ngf $CHART --version 2.7.1 -n nginx-gateway -f "$DIR/01-ngf-values.yaml" --set nginxGateway.config.logging.level=debug --wait
  helm rollback ngf 1 -n nginx-gateway --wait
fi
kubectl apply -f "$DIR/02-shop-gateway.yaml"
kubectl wait --for=condition=Programmed gateway/shop-gateway -n shop --timeout=180s
kubectl apply -f "$DIR/03-shop-route.yaml"
kubectl delete httproute lab10-api-host lab10-canary-route lab10-header -n shop --ignore-not-found
kubectl delete deploy,svc lab10-canary -n shop --ignore-not-found

# ---------- Lab11: NFS 서버 (cap-master) ----------
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq -o DPkg::Lock::Timeout=300 nfs-kernel-server >/dev/null
mkdir -p /srv/nfs/shop-db /srv/nfs/shop-share
chown 999:999 /srv/nfs/shop-db && chmod 750 /srv/nfs/shop-db
chown nobody:nogroup /srv/nfs/shop-share && chmod 755 /srv/nfs/shop-share
mkdir -p /etc/exports.d && cp "$DIR/05-shop.exports" /etc/exports.d/shop.exports
systemctl enable --now nfs-server
exportfs -ra
exportfs -s

# ---------- Lab11: 워커 노드 NFS 클라이언트 ----------
for N in cap-node1 cap-node2; do
  nodeshell "$N" 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq -o DPkg::Lock::Timeout=300 nfs-common >/dev/null && /sbin/mount.nfs -V'
done

# ---------- Lab11: PV/PVC · shop-db 영구화 ----------
kubectl apply -f "$DIR/10-shop-db-storage.yaml" -f "$DIR/11-shop-share-storage.yaml"
kubectl wait pvc/shop-db-data pvc/shop-share -n shop --for=jsonpath='{.status.phase}'=Bound --timeout=120s
kubectl apply -f "$DIR/20-shop-db-sts.yaml"
kubectl rollout status sts/shop-db -n shop --timeout=300s
echo "MySQL 준비 대기..."; dbwait
if [ "$(q 'SELECT COUNT(*) FROM products' || true)" != "5" ]; then
  kubectl delete job shop-db-seed -n shop --ignore-not-found --wait=true
  kubectl apply -f "$REPO/catchup/day4/80-shop-db-seed-job.yaml"
  kubectl wait --for=condition=complete job/shop-db-seed -n shop --timeout=300s
fi
if [ "$(q 'SELECT note FROM lab11_marker WHERE id=1' || true)" != "persist-ok" ]; then
  q "CREATE TABLE IF NOT EXISTS lab11_marker (id INT PRIMARY KEY, note VARCHAR(50)); REPLACE INTO lab11_marker VALUES (1, 'persist-ok');"
  kubectl delete pod shop-db-0 -n shop --wait=true
  dbwait
  [ "$(q 'SELECT note FROM lab11_marker WHERE id=1' || true)" = "persist-ok" ] || { echo "Pod 재생성 후 데이터가 사라졌습니다. NFS 마운트를 확인하세요."; exit 1; }
fi

# ---------- Lab11: NFS 공유 볼륨 (CronJob → shop-web) ----------
kubectl apply -f "$DIR/30-shop-report-cronjob.yaml"
kubectl create configmap shop-web-nginx -n shop --from-file=default.conf="$DIR/40-shop-web-default.conf" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "$DIR/41-shop-web-deploy.yaml"
kubectl rollout status deploy/shop-web -n shop --timeout=300s
if [ ! -s /srv/nfs/shop-share/products.log ]; then
  kubectl delete job shop-report-catchup -n shop --ignore-not-found --wait=true
  kubectl create job shop-report-catchup --from=cronjob/shop-report -n shop
  kubectl wait --for=condition=complete job/shop-report-catchup -n shop --timeout=180s
  kubectl delete job shop-report-catchup -n shop
fi

# 연습 리소스 정리
for r in $(kubectl get pods,jobs -n shop -o name | grep 'lab11-' || true); do kubectl delete "$r" -n shop --ignore-not-found; done
for r in $(kubectl get pv -o name | grep 'lab11-' || true); do kubectl delete "$r" --ignore-not-found; done
for r in $(kubectl get pods -n default -o name | grep 'node-debugger-' || true); do kubectl delete "$r" -n default --ignore-not-found; done

# 교육생 작업 파일 갱신
mkdir -p "$HOME/shop"
cp "$DIR/01-ngf-values.yaml" "$HOME/shop/ngf-values.yaml"
cp "$DIR/02-shop-gateway.yaml" "$HOME/shop/shop-gateway.yaml"
cp "$DIR/03-shop-route.yaml" "$HOME/shop/shop-route.yaml"
cp "$DIR/10-shop-db-storage.yaml" "$HOME/shop/shop-db-storage.yaml"
cp "$DIR/11-shop-share-storage.yaml" "$HOME/shop/shop-share-storage.yaml"
cp "$DIR/20-shop-db-sts.yaml" "$HOME/shop/shop-db-sts.yaml"
cp "$DIR/30-shop-report-cronjob.yaml" "$HOME/shop/shop-report-cronjob.yaml"
cp "$DIR/40-shop-web-default.conf" "$HOME/shop/shop-web-default.conf"
cp "$DIR/41-shop-web-deploy.yaml" "$HOME/shop/shop-web-deploy.yaml"
echo "[catchup day6] 완료 — 확인: bash $REPO/verify-all.sh day6  (보안 그룹은 CloudShell에서 lab10-gateway/verify-aws.sh)"
