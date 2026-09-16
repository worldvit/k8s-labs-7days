#!/usr/bin/env bash
# Lab09 복구 확인 — 사용: bash check.sh <1-6>
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$DIR/common9.sh"
N="${1:-}"; case "$N" in 1|2|3|4|5|6) ;; *) echo "사용법: bash check.sh <1-6>"; exit 1;; esac
HINT=( "" "배포가 끝났는지부터 확인하세요 (rollout status → 새 Pod의 describe)" \
          "재시작되는 컨테이너의 직전 로그를 보세요 (logs --previous)" \
          "새 Pod의 Events에서 스케줄 실패 사유를 보세요" \
          "Service 뒤에 실제 대상이 있는지 보세요 (EndpointSlice)" \
          "Pod가 없으면 ReplicaSet의 Events를 보세요" \
          "새 Pod의 STATUS와 describe의 Events를 보세요" )
if healthy "$N"; then
  if [ -f "$STATE/broken-$N" ]; then
    now=$(date +%s); st=$(cat "$STATE/broken-$N"); echo "$now" > "$STATE/fixed-$N"
    printf '  \033[32mPASS\033[0m  장애 %s 복구 확인 (소요 %d분)\n' "$N" $(( (now-st)/60 ))
  else
    printf '  \033[32mPASS\033[0m  정상 상태 (장애 %s을(를) 주입한 기록은 없습니다)\n' "$N"
  fi
else
  printf '  \033[31mFAIL\033[0m  장애 %s 아직 복구되지 않음 — 힌트: %s\n' "$N" "${HINT[$N]}"; exit 1
fi
