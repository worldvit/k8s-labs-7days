#!/usr/bin/env bash
# LabE 정리 — CloudShell에서 실행
# 순서: ① Ingress 삭제(ALB 제거) → ② PVC 삭제(EBS 제거) → ③ eksctl delete cluster → ④ 잔여 확인
# ⚠ EKS 클러스터와 노드 그룹을 되돌릴 수 없게 삭제합니다.
set -u
export AWS_PAGER=""
REGION="${REGION:-ap-northeast-2}"
CLUSTER="${CLUSTER:-cap-eks}"
ok() { printf '[✔] %s\n' "$1"; }
read -r -p "EKS 클러스터 $CLUSTER 와 ALB · EBS 볼륨을 삭제합니다. 계속하려면 delete 입력: " ans
[ "$ans" = "delete" ] || { echo "취소했습니다."; exit 1; }

ALB=$(kubectl get ingress shop -n shop -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
kubectl delete ingress shop -n shop --ignore-not-found && ok "Ingress 삭제 (컨트롤러가 ALB 제거)"
if [ -n "$ALB" ]; then
  for _ in $(seq 1 30); do
    [ -z "$(aws elbv2 describe-load-balancers --region "$REGION" --query "LoadBalancers[?DNSName=='$ALB'].LoadBalancerArn" --output text)" ] && { ok "ALB 삭제 확인"; break; }
    sleep 10
  done
fi
kubectl delete statefulset shop-db -n shop --ignore-not-found
kubectl delete pvc --all -n shop --ignore-not-found && ok "PVC 삭제 (EBS 볼륨 제거)"
sleep 20
eksctl delete cluster --name "$CLUSTER" --region "$REGION" --wait && ok "클러스터 삭제: $CLUSTER"

LB=$(aws elbv2 describe-load-balancers --region "$REGION" --query "length(LoadBalancers[?starts_with(LoadBalancerName,'k8s-shop')])" --output text)
VOL=$(aws ec2 describe-volumes --region "$REGION" --filters Name=tag:Project,Values=capstone Name=status,Values=available,in-use --query 'length(Volumes)' --output text)
CL=$(aws eks list-clusters --region "$REGION" --query "length(clusters[?@=='$CLUSTER'])" --output text)
ok "정리 완료 — 남은 ALB: $LB · Project=capstone 볼륨: $VOL · 클러스터: $CL"
