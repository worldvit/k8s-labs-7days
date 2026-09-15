#!/usr/bin/env bash
# 채점 공통 함수: PASS/FAIL 출력과 결과 집계
PASS_CNT=0; TOTAL_CNT=0; FAILED=()
check() {  # check "설명" 명령...
  local desc="$1"; shift
  TOTAL_CNT=$((TOTAL_CNT+1))
  if "$@" >/dev/null 2>&1; then
    PASS_CNT=$((PASS_CNT+1)); printf '  \033[32mPASS\033[0m  %s\n' "$desc"
  else
    FAILED+=("$desc"); printf '  \033[31mFAIL\033[0m  %s\n' "$desc"
  fi
}
summary() {
  echo "  ---"
  if [ "$PASS_CNT" -eq "$TOTAL_CNT" ]; then
    printf '  결과: %d/%d  통과\n' "$PASS_CNT" "$TOTAL_CNT"
  else
    printf '  결과: %d/%d  — FAIL 항목은 실습 문서 태스크 14의 표에서 돌아갈 단계를 확인하세요\n' "$PASS_CNT" "$TOTAL_CNT"
  fi
  [ "$PASS_CNT" -eq "$TOTAL_CNT" ]
}
