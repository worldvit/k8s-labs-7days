#!/usr/bin/env bash
# Lab12 채점 (AWS 리소스) — CloudShell에서 실행
# 사용: bash ~/k8s-labs-7days/lab12-aws/verify-aws.sh
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"
export AWS_PAGER=""
REGION="${REGION:-ap-northeast-2}"
a() { aws "$@" --region "$REGION" --output text 2>/dev/null; }
echo "[Lab12  AWS 연동 — IAM · ALB · 대상 그룹 · EBS (AWS)]"
VPC_ID=$(a ec2 describe-vpcs --filters Name=tag:Name,Values=cap-vpc --query 'Vpcs[0].VpcId')
NODE_SG=$(a ec2 describe-security-groups --filters Name=group-name,Values=cap-k8s-node-sg "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[0].GroupId')
ALB_SG=$(a ec2 describe-security-groups --filters Name=group-name,Values=cap-alb-sg "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[0].GroupId')
TG_ARN=$(a elbv2 describe-target-groups --names cap-shop-tg --query 'TargetGroups[0].TargetGroupArn')
ALB_ARN=$(a elbv2 describe-load-balancers --names cap-shop-alb --query 'LoadBalancers[0].LoadBalancerArn')
iid() { a ec2 describe-instances --filters "Name=tag:Name,Values=$1" Name=instance-state-name,Values=pending,running,stopping,stopped --query 'Reservations[0].Instances[0].InstanceId'; }

iam_ok()    { a iam list-attached-role-policies --role-name cap-k8s-node-role --query 'AttachedPolicies[].PolicyName' | tr '\t' '\n' | grep -qx AmazonEBSCSIDriverPolicyV2; }
alb_sg()    { local c; c=$(a ec2 describe-security-groups --group-ids "$ALB_SG" --query "SecurityGroups[0].IpPermissions[?IpProtocol=='tcp' && FromPort==\`80\`].IpRanges[].CidrIp" | tr '\t' '\n' | grep -v '^$'); [ -n "$c" ] && ! echo "$c" | grep -vq '/32$'; }
node_rule() { [ "$(a ec2 describe-security-groups --group-ids "$NODE_SG" --query "length(SecurityGroups[0].IpPermissions[?IpProtocol=='tcp' && FromPort==\`31080\`].UserIdGroupPairs[] | [?GroupId=='$ALB_SG'])")" -ge 1 ] 2>/dev/null; }
tg_ok()     { [ "$(a elbv2 describe-target-groups --target-group-arns "$TG_ARN" --query 'TargetGroups[0].[Protocol,Port,TargetType,HealthCheckPath,VpcId]' | tr '\t' '|')" = "HTTP|31080|instance|/|$VPC_ID" ]; }
targets()   { local ids; ids=$(a elbv2 describe-target-health --target-group-arn "$TG_ARN" --query 'TargetHealthDescriptions[?TargetHealth.State==`healthy`].Target.Id' | tr '\t' '\n' | sort | tr '\n' ' '); [ "$ids" = "$(printf '%s\n%s\n' "$(iid cap-node1)" "$(iid cap-node2)" | sort | tr '\n' ' ')" ]; }
alb_ok()    { [ "$(a elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" --query 'LoadBalancers[0].[State.Code,Scheme,Type,length(AvailabilityZones)]' | tr '\t' '|')" = "active|internet-facing|application|2" ]; }
listener()  { [ "$(a elbv2 describe-listeners --load-balancer-arn "$ALB_ARN" --query 'Listeners[?Port==`80`] | [0].[Protocol,DefaultActions[0].Type,DefaultActions[0].TargetGroupArn]' | tr '\t' '|')" = "HTTP|forward|$TG_ARN" ]; }
ebs_ok()    { [ "$(a ec2 describe-volumes --filters Name=tag:Project,Values=capstone Name=tag:ebs.csi.aws.com/cluster,Values=true Name=volume-type,Values=gp3 Name=status,Values=in-use --query 'length(Volumes)')" -ge 1 ] 2>/dev/null; }
node2_up()  { [ "$(a ec2 describe-instances --instance-ids "$(iid cap-node2)" --query 'Reservations[0].Instances[0].State.Name')" = "running" ]; }

check "IAM 역할 cap-k8s-node-role ← AmazonEBSCSIDriverPolicyV2" iam_ok
check "cap-alb-sg 인바운드 80 · 소스 /32만"                    alb_sg
check "cap-k8s-node-sg 31080 ← cap-alb-sg"                     node_rule
check "대상 그룹 cap-shop-tg (HTTP 31080 · instance · /)"      tg_ok
check "대상 cap-node1 · cap-node2 healthy"                      targets
check "ALB cap-shop-alb (active · internet-facing · 2 AZ)"      alb_ok
check "리스너 HTTP 80 → cap-shop-tg"                            listener
check "EBS gp3 볼륨 사용 중 (CSI 생성 · Project=capstone)"      ebs_ok
check "cap-node2 running (장애 실험 후 복구)"                    node2_up
summary
