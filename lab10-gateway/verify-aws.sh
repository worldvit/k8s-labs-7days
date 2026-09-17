#!/usr/bin/env bash
# Lab10 채점 (AWS 보안 그룹) — CloudShell에서 실행
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"
export AWS_PAGER=""
REGION="${REGION:-ap-northeast-2}"
a() { aws "$@" --region "$REGION" --output text 2>/dev/null; }
echo "[Lab10  AWS 보안 그룹 — Gateway NodePort 31080]"
VPC_ID=$(a ec2 describe-vpcs --filters Name=tag:Name,Values=cap-vpc --query 'Vpcs[0].VpcId')
SG_ID=$(a ec2 describe-security-groups --filters Name=group-name,Values=cap-k8s-node-sg "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[0].GroupId')
cidrs() { a ec2 describe-security-groups --group-ids "$SG_ID" --query "SecurityGroups[0].IpPermissions[?IpProtocol=='tcp' && FromPort==\`$1\` && ToPort==\`$1\`].IpRanges[].CidrIp" | tr '\t' '\n' | grep -v '^$'; }
r31080()  { [ -n "$(cidrs 31080)" ] && ! cidrs 31080 | grep -vq '/32$'; }
no30080() { [ -z "$(cidrs 30080)" ]; }
self_kept(){ [ "$(a ec2 describe-security-groups --group-ids "$SG_ID" --query "length(SecurityGroups[0].IpPermissions[?IpProtocol=='-1'].UserIdGroupPairs[] | [?GroupId=='$SG_ID'])")" -ge 1 ]; }
check "TCP 31080 인바운드 · 소스 /32 (내 IP)"   r31080
check "TCP 30080 외부 규칙 제거"               no30080
check "자기 참조 규칙 유지"                     self_kept
summary
