#!/usr/bin/env bash
# Lab02 리소스 개별 삭제 — CloudShell에서 실행
# ⚠ 누적 실습 기반 클러스터를 삭제합니다. 과정 종료 또는 강사 지시 시에만 사용하세요.
set -u
export AWS_PAGER=""
REGION="${REGION:-ap-northeast-2}"
read -r -p "cap 클러스터(EC2 3대, AMI, 보안 그룹, VPC, IAM 역할)를 삭제합니다. 계속하려면 delete 입력: " ans
[ "$ans" = "delete" ] || { echo "취소했습니다."; exit 1; }
ok() { printf '[✔] %s\n' "$1"; }

IDS=$(aws ec2 describe-instances --region "$REGION" --filters "Name=tag:Name,Values=cap-master,cap-node1,cap-node2" \
  "Name=instance-state-name,Values=pending,running,stopping,stopped" --query 'Reservations[].Instances[].InstanceId' --output text)
if [ -n "$IDS" ]; then
  aws ec2 terminate-instances --region "$REGION" --instance-ids $IDS >/dev/null
  aws ec2 wait instance-terminated --region "$REGION" --instance-ids $IDS && ok "인스턴스 종료: $IDS"
fi

for AMI in $(aws ec2 describe-images --region "$REGION" --owners self --filters Name=name,Values=cap-k8s-base-1.36 --query 'Images[].ImageId' --output text); do
  SNAPS=$(aws ec2 describe-images --region "$REGION" --image-ids "$AMI" --query 'Images[0].BlockDeviceMappings[].Ebs.SnapshotId' --output text)
  aws ec2 deregister-image --region "$REGION" --image-id "$AMI" && ok "AMI 등록 해제: $AMI"
  for S in $SNAPS; do aws ec2 delete-snapshot --region "$REGION" --snapshot-id "$S" && ok "스냅샷 삭제: $S"; done
done

VPC_ID=$(aws ec2 describe-vpcs --region "$REGION" --filters Name=tag:Name,Values=cap-vpc --query 'Vpcs[0].VpcId' --output text)
if [ "$VPC_ID" != "None" ] && [ -n "$VPC_ID" ]; then
  SG_ID=$(aws ec2 describe-security-groups --region "$REGION" --filters Name=group-name,Values=cap-k8s-node-sg Name=vpc-id,Values="$VPC_ID" --query 'SecurityGroups[0].GroupId' --output text)
  if [ "$SG_ID" != "None" ]; then
    RULES=$(aws ec2 describe-security-group-rules --region "$REGION" --filters Name=group-id,Values="$SG_ID" --query 'SecurityGroupRules[?IsEgress==`false`].SecurityGroupRuleId' --output text)
    [ -n "$RULES" ] && aws ec2 revoke-security-group-ingress --region "$REGION" --group-id "$SG_ID" --security-group-rule-ids $RULES >/dev/null
    aws ec2 delete-security-group --region "$REGION" --group-id "$SG_ID" && ok "보안 그룹 삭제: $SG_ID"
  fi
  for S in $(aws ec2 describe-subnets --region "$REGION" --filters Name=vpc-id,Values="$VPC_ID" --query 'Subnets[].SubnetId' --output text); do
    aws ec2 delete-subnet --region "$REGION" --subnet-id "$S" && ok "서브넷 삭제: $S"; done
  for R in $(aws ec2 describe-route-tables --region "$REGION" --filters Name=vpc-id,Values="$VPC_ID" --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text); do
    aws ec2 delete-route-table --region "$REGION" --route-table-id "$R" && ok "라우팅 테이블 삭제: $R"; done
  for G in $(aws ec2 describe-internet-gateways --region "$REGION" --filters Name=attachment.vpc-id,Values="$VPC_ID" --query 'InternetGateways[].InternetGatewayId' --output text); do
    aws ec2 detach-internet-gateway --region "$REGION" --internet-gateway-id "$G" --vpc-id "$VPC_ID"
    aws ec2 delete-internet-gateway --region "$REGION" --internet-gateway-id "$G" && ok "인터넷 게이트웨이 삭제: $G"; done
  aws ec2 delete-vpc --region "$REGION" --vpc-id "$VPC_ID" && ok "VPC 삭제: $VPC_ID"
fi

if aws iam get-role --role-name cap-k8s-node-role >/dev/null 2>&1; then
  aws iam remove-role-from-instance-profile --instance-profile-name cap-k8s-node-role --role-name cap-k8s-node-role 2>/dev/null
  aws iam delete-instance-profile --instance-profile-name cap-k8s-node-role 2>/dev/null
  for P in $(aws iam list-attached-role-policies --role-name cap-k8s-node-role --query 'AttachedPolicies[].PolicyArn' --output text); do
    aws iam detach-role-policy --role-name cap-k8s-node-role --policy-arn "$P"; done
  aws iam delete-role --role-name cap-k8s-node-role && ok "IAM 역할 · 인스턴스 프로파일 삭제"
fi
rm -f ~/cap-k8s.env
ok "Lab02 teardown 완료"
