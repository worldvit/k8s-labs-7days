#!/usr/bin/env bash
# 누적 상태 점검 — 매일 아침 cap-master 노드 셸(root)에서 실행
# 사용: bash ~/k8s-labs-7days/verify-all.sh day2   (day2까지의 결과물을 검사)
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAY="${1:-}"
case "$DAY" in
  day1) LABS="lab02-install" ;;
  day2) LABS="lab02-install lab03-pod" ;;
  day3am) LABS="lab02-install lab04-node" ;;
  *) echo "사용법: bash verify-all.sh day1|day2|day3am"; exit 1 ;;
esac
rc=0
for L in $LABS; do bash "$REPO/$L/verify.sh" || rc=1; echo; done
if [ $rc -ne 0 ]; then
  echo "FAIL이 있습니다. 전날 실습을 마무리하거나 강사 안내에 따라 bash $REPO/catchup.sh <전날> 을 실행하세요."
fi
exit $rc
