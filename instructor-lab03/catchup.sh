#!/usr/bin/env bash
# 누적 실습 따라잡기 진입점 — 사용: bash ~/k8s-labs-7days/catchup.sh dayN
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAY="${1:-}"
[ -n "$DAY" ] || { echo "사용법: bash catchup.sh day2"; exit 1; }
SCRIPT="$REPO/catchup/$DAY/catchup-$DAY.sh"
[ -f "$SCRIPT" ] || { echo "$DAY 따라잡기 파일이 아직 공개되지 않았습니다. git pull 후 다시 시도하세요."; exit 1; }
bash "$SCRIPT"
