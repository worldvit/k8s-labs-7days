#!/usr/bin/env bash
# 과정 종료 정리 — CloudShell에서 실행
# 순서: ① Lab12 ALB · 대상 그룹 · 보안 그룹  ② Lab02 teardown(EC2 · AMI · VPC · IAM)  ③ 남은 EBS CSI 볼륨
# ⚠ 누적 실습 클러스터 전체를 삭제합니다. 과정 종료 또는 강사 지시 시에만 사용하세요.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export AWS_PAGER=""
REGION="${REGION:-ap-northeast-2}"
a() { aws "$@" --region "$REGION"; }
ok() { printf '[✔] %s\n' "$1"; }
read -r -p "ALB · 대상 그룹 · cap-alb-sg · EBS 볼륨을 삭제한 뒤 Lab02 teardown을 이어서 실행합니다. 계속하려면 delete 입력: " ans
[ "$ans" = "delete" ] || { echo "취소했습니다."; exit 1; }

# ① ALB → 대상 그룹 → 노드 SG 규칙 → ALB SG
ALB_ARN=$(a elbv2 describe-load-balancers --names cap-shop-alb --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null)
if [ -n "$ALB_ARN" ] && [ "$ALB_ARN" != "None" ]; then
  a elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN" && a elbv2 wait load-balancers-deleted --load-balancer-arns "$ALB_ARN" && ok "ALB 삭제: cap-shop-alb"
fi
TG_ARN=$(a elbv2 describe-target-groups --names cap-shop-tg --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null)
if [ -n "$TG_ARN" ] && [ "$TG_ARN" != "None" ]; then
  a elbv2 delete-target-group --target-group-arn "$TG_ARN" && ok "대상 그룹 삭제: cap-shop-tg"
fi
VPC_ID=$(a ec2 describe-vpcs --filters Name=tag:Name,Values=cap-vpc --query 'Vpcs[0].VpcId' --output text)
NODE_SG=$(a ec2 describe-security-groups --filters Name=group-name,Values=cap-k8s-node-sg "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[0].GroupId' --output text)
ALB_SG=$(a ec2 describe-security-groups --filters Name=group-name,Values=cap-alb-sg "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[0].GroupId' --output text)
if [ -n "$ALB_SG" ] && [ "$ALB_SG" != "None" ]; then
  if [ "$NODE_SG" != "None" ]; then
    R=$(a ec2 describe-security-group-rules --filters Name=group-id,Values="$NODE_SG" --query "SecurityGroupRules[?ReferencedGroupInfo.GroupId=='$ALB_SG'].SecurityGroupRuleId" --output text)
    [ -n "$R" ] && a ec2 revoke-security-group-ingress --group-id "$NODE_SG" --security-group-rule-ids $R >/dev/null && ok "노드 SG 규칙 삭제: 31080 ← cap-alb-sg"
  fi
  for i in $(seq 1 30); do   # ALB 네트워크 인터페이스 해제 대기
    a ec2 delete-security-group --group-id "$ALB_SG" 2>/dev/null && { ok "보안 그룹 삭제: cap-alb-sg"; break; }
    sleep 10
  done
fi

# ② Lab02 teardown (EC2 종료 → EBS 볼륨 분리)
bash "$DIR/../lab02-install/teardown.sh"

# ③ EBS CSI가 만든 볼륨 중 남은 것 (PVC를 지우지 않고 인스턴스를 종료한 경우)
for V in $(a ec2 describe-volumes --filters Name=tag:Project,Values=capstone Name=tag:ebs.csi.aws.com/cluster,Values=true --query 'Volumes[].VolumeId' --output text); do
  a ec2 wait volume-available --volume-ids "$V" 2>/dev/null
  a ec2 delete-volume --volume-id "$V" && ok "EBS 볼륨 삭제: $V"
done
LEFT=$(a ec2 describe-volumes --filters Name=tag:Project,Values=capstone --query 'length(Volumes)' --output text)
ok "과정 정리 완료 — 남은 Project=capstone 볼륨: $LEFT개"
