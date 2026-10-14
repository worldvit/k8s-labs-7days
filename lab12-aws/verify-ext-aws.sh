#!/usr/bin/env bash
# Lab12 Part 2(확장) 채점 (AWS 리소스) — CloudShell에서 실행
# 사용: bash ~/k8s-labs-7days/lab12-aws/verify-ext-aws.sh   (Part 2 정리 단계 전에 실행)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"
export AWS_PAGER=""
REGION="${REGION:-ap-northeast-2}"
a() { aws "$@" --region "$REGION" --output text 2>/dev/null; }
echo "[Lab12 Part 2  EBS 확장 · 볼륨 AZ · ALB 등록 해제 (AWS)]"
TG_ARN=$(a elbv2 describe-target-groups --names cap-shop-tg --query 'TargetGroups[0].TargetGroupArn')
iid() { a ec2 describe-instances --filters "Name=tag:Name,Values=$1" Name=instance-state-name,Values=pending,running,stopping,stopped --query 'Reservations[0].Instances[0].InstanceId'; }
N1_ID=$(iid cap-node1); N2_ID=$(iid cap-node2)
N1_AZ=$(a ec2 describe-instances --instance-ids "$N1_ID" --query 'Reservations[0].Instances[0].Placement.AvailabilityZone')
vol() { a ec2 describe-volumes --filters "Name=tag:kubernetes.io/created-for/pvc/name,Values=$1" --query "Volumes[0].$2"; }

dereg()     { [ "$(a elbv2 describe-target-group-attributes --target-group-arn "$TG_ARN" --query 'Attributes[?Key==`deregistration_delay.timeout_seconds`].Value')" = "30" ]; }
targets()   { local ids; ids=$(a elbv2 describe-target-health --target-group-arn "$TG_ARN" --query 'TargetHealthDescriptions[?TargetHealth.State==`healthy`].Target.Id' | tr '\t' '\n' | sort | tr '\n' ' '); [ "$ids" = "$(printf '%s\n%s\n' "$N1_ID" "$N2_ID" | sort | tr '\n' ' ')" ]; }
grow_vol()  { [ "$(vol ext-data Size)" = "2" ]; }
grow_mod()  { local id st; id=$(vol ext-data VolumeId); st=$(a ec2 describe-volumes-modifications --volume-ids "$id" --query 'VolumesModifications[0].[TargetSize,ModificationState]' | tr '\t' '|'); [ "$st" = "2|optimizing" ] || [ "$st" = "2|completed" ]; }
far_vol()   { local z; z=$(vol ext-far AvailabilityZone); [ -n "$z" ] && [ "$z" != "None" ] && [ "$z" != "$N1_AZ" ] && [ "$(vol ext-far State)" = "available" ]; }
roll_log()  { local f="$HOME/ext-alb-roll.log"; [ "$(grep -c . "$f")" -ge 30 ] && grep -q ' 200$' "$f"; } 2>/dev/null
dereg_log() { local f="$HOME/ext-alb-dereg.log"; grep -q 'node2:draining' "$f" && grep -q 'node2:unused' "$f" && ! grep -q '/:000' "$f"; } 2>/dev/null

check "대상 그룹 등록 해제 지연 30초"                          dereg
check "대상 cap-node1 · cap-node2 다시 healthy"                 targets
check "ext-data EBS 볼륨 크기 2GiB"                             grow_vol
check "ext-data 볼륨 수정 상태 (optimizing · completed)"        grow_mod
check "ext-far EBS 볼륨 — 노드와 다른 AZ · 미연결(available)"   far_vol
check "~/ext-alb-roll.log 기록 (롤링 재시작 중 요청)"           roll_log
check "~/ext-alb-dereg.log draining → unused · 시간 초과 없음"  dereg_log
summary
