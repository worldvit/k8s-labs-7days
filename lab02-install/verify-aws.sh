#!/usr/bin/env bash
# Lab02 채점 (AWS 리소스) — CloudShell에서 실행 (AWS CLI --query만 사용, 추가 도구 불필요)
# 사용: bash ~/k8s-capstone-labs/lab02-install/verify-aws.sh
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"
export AWS_PAGER=""
REGION="${REGION:-ap-northeast-2}"
a() { aws "$@" --region "$REGION" --output text 2>/dev/null; }
NODES="Name=tag:Name,Values=cap-master,cap-node1,cap-node2"
RUN="Name=instance-state-name,Values=running"
inst() { a ec2 describe-instances --filters "$NODES" "$RUN" --query "$1"; }

echo "[Lab02  cap 클러스터 — AWS 리소스 검사]"
VPC_ID=$(a ec2 describe-vpcs --filters Name=tag:Name,Values=cap-vpc --query 'Vpcs[0].VpcId')
SG_ID=$(a ec2 describe-security-groups --filters Name=group-name,Values=cap-k8s-node-sg "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[0].GroupId')

vpc_ok()      { [ "$(a ec2 describe-vpcs --vpc-ids "$VPC_ID" --query 'Vpcs[0].CidrBlock')" = "10.20.0.0/16" ]; }
subnets_ok()  {
  local azs; azs=$(a ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=cidr-block,Values=10.20.1.0/24,10.20.2.0/24" \
    --query 'Subnets[].AvailabilityZone' | tr '\t' '\n' | sort -u | grep -c .)
  [ "$azs" = "2" ]
}
sg_self()     { [ "$(a ec2 describe-security-groups --group-ids "$SG_ID" \
                  --query "length(SecurityGroups[0].IpPermissions[?IpProtocol=='-1'].UserIdGroupPairs[] | [?GroupId=='$SG_ID'])")" -ge 1 ]; }
sg_no_world() { [ "$(a ec2 describe-security-groups --group-ids "$SG_ID" \
                  --query "length(SecurityGroups[0].IpPermissions[].IpRanges[] | [?CidrIp=='0.0.0.0/0'])")" = "0" ]; }
inst_count()  { [ "$(inst 'length(Reservations[].Instances[])')" = "3" ]; }
same_az()     { [ "$(inst 'Reservations[].Instances[].Placement.AvailabilityZone' | tr '\t' '\n' | sort -u | grep -c .)" = "1" ]; }
fixed_ip()    {
  local out; out=$(a ec2 describe-instances --filters "$NODES" "$RUN" \
    --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value|[0],PrivateIpAddress]' | sort)
  [ "$out" = "$(printf 'cap-master\t10.20.1.10\ncap-node1\t10.20.1.11\ncap-node2\t10.20.1.12')" ]
}
profile_ok()  { [ "$(inst "length(Reservations[].Instances[?IamInstanceProfile && ends_with(IamInstanceProfile.Arn, '/cap-k8s-node-role')][])")" = "3" ]; }
hop_ok()      { [ "$(inst 'length(Reservations[].Instances[?MetadataOptions.HttpPutResponseHopLimit >= `2`][])')" = "3" ]; }
tags_ok()     {
  [ "$(inst "length(Reservations[].Instances[?Tags[?Key=='Project' && Value=='capstone'] && Tags[?Key=='Owner' && Value=='cap']][])")" = "3" ] &&
  [ "$(a ec2 describe-vpcs --vpc-ids "$VPC_ID" --query 'Vpcs[0].Tags[?Key==`Project`].Value|[0]')" = "capstone" ]
}

check "VPC cap-vpc (10.20.0.0/16)"                vpc_ok
check "퍼블릭 서브넷 2개 · 서로 다른 AZ"          subnets_ok
check "보안 그룹 자기 참조 규칙"                  sg_self
check "보안 그룹에 0.0.0.0/0 인바운드 없음"       sg_no_world
check "인스턴스 3대 실행 중"                      inst_count
check "인스턴스 3대 동일 AZ"                      same_az
check "고정 프라이빗 IP 10.20.1.10~12"            fixed_ip
check "IAM 인스턴스 프로파일 cap-k8s-node-role"   profile_ok
check "메타데이터 홉 제한 2 이상"                 hop_ok
check "공통 태그 Project=capstone · Owner=cap"    tags_ok
summary
