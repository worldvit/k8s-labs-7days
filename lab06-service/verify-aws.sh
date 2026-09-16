#!/usr/bin/env bash
# Lab06 채점 (AWS 보안 그룹) — CloudShell에서 실행
# 사용: bash ~/k8s-labs-7days/lab06-service/verify-aws.sh
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"
export AWS_PAGER=""
REGION="${REGION:-ap-northeast-2}"
a() { aws "$@" --region "$REGION" --output text 2>/dev/null; }
echo "[Lab06  AWS 보안 그룹 — NodePort 30080]"
VPC_ID=$(a ec2 describe-vpcs --filters Name=tag:Name,Values=cap-vpc --query 'Vpcs[0].VpcId')
SG_ID=$(a ec2 describe-security-groups --filters Name=group-name,Values=cap-k8s-node-sg "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[0].GroupId')
cidrs() { a ec2 describe-security-groups --group-ids "$SG_ID" --query "SecurityGroups[0].IpPermissions[?IpProtocol=='tcp' && FromPort==\`30080\` && ToPort==\`30080\`].IpRanges[].CidrIp" | tr '\t' '\n' | grep -v '^$'; }
rule_exists() { [ -n "$(cidrs)" ]; }
rule_32()     { [ -n "$(cidrs)" ] && ! cidrs | grep -vq '/32$'; }
no_world()    { ! cidrs | grep -qx '0.0.0.0/0'; }
self_kept()   { [ "$(a ec2 describe-security-groups --group-ids "$SG_ID" --query "length(SecurityGroups[0].IpPermissions[?IpProtocol=='-1'].UserIdGroupPairs[] | [?GroupId=='$SG_ID'])")" -ge 1 ]; }
check "TCP 30080 인바운드 규칙 존재"          rule_exists
check "30080 소스가 /32 (내 IP)"               rule_32
check "30080에 0.0.0.0/0 없음"                 no_world
check "자기 참조 규칙 유지"                     self_kept
summary
