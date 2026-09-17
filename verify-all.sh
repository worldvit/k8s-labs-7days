#!/usr/bin/env bash
# 누적 상태 점검 — 매일 아침 cap-master 노드 셸(root)에서 실행
# 사용: bash ~/k8s-labs-7days/verify-all.sh day2   (day2까지의 결과물을 검사)
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAY="${1:-}"
case "$DAY" in
  day1) LABS="lab02-install" ;;
  day2) LABS="lab02-install lab03-pod" ;;
  day3am) LABS="lab02-install lab04-node" ;;
  day3) LABS="lab02-install lab04-node lab05a-deployment" ;;
  day4am) LABS="lab02-install lab04-node lab05a-deployment lab05b-workloads" ;;
  day4) LABS="lab02-install lab04-node lab05a-deployment lab05b-workloads lab06-service" ;;
  day5am) LABS="lab02-install lab04-node lab05a-deployment lab05b-workloads lab06-service lab07-probe" ;;
  day5) LABS="lab02-install lab04-node lab05a-deployment lab05b-workloads lab06-service lab07-probe lab08-resources" ;;
  day6am) LABS="lab02-install lab04-node lab05a-deployment lab05b-workloads lab06-service lab07-probe lab08-resources lab10-gateway" ;;
  day6) LABS="lab02-install lab04-node lab05a-deployment lab05b-workloads lab06-service lab07-probe lab08-resources lab10-gateway lab11-volume" ;;
  day7) LABS="lab02-install lab04-node lab05a-deployment lab05b-workloads lab06-service lab07-probe lab08-resources lab10-gateway lab12-aws" ;;
  *) echo "사용법: bash verify-all.sh day1|day2|day3am|day3|day4am|day4|day5am|day5|day6am|day6|day7"; exit 1 ;;
esac
rc=0
for L in $LABS; do bash "$REPO/$L/verify.sh" || rc=1; echo; done
if [ $rc -ne 0 ]; then
  echo "FAIL이 있습니다. 전날 실습을 마무리하거나 강사 안내에 따라 bash $REPO/catchup.sh <전날> 을 실행하세요."
fi
exit $rc
