#!/usr/bin/env bash
# Lab09 장애 주입 — 사용: bash break.sh <1-6>   (6은 선택 장애)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; source "$DIR/common9.sh"
N="${1:-}"; case "$N" in 1|2|3|4|5|6) ;; *) echo "사용법: bash break.sh <1-6>"; exit 1;; esac
for i in 1 2 3 4 5 6; do
  if [ -f "$STATE/broken-$i" ] && [ ! -f "$STATE/fixed-$i" ]; then
    echo "장애 $i 이(가) 아직 복구 기록되지 않았습니다. 복구 후 bash check.sh $i 를 먼저 실행하세요."; exit 1
  fi
done
for d in shop-api shop-web; do rollout_ok "$d" || { echo "$d 롤아웃이 완료 상태가 아닙니다. 정상 상태에서 시작하세요."; exit 1; }; done
healthy 4 || { echo "shop-api Service가 정상이 아닙니다. 정상 상태에서 시작하세요."; exit 1; }

case "$N" in
  1) kubectl set image deploy/shop-web nginx=nginx:1.30-alpline -n shop >/dev/null
     MSG="[장애 1] shop-web 담당자가 nginx 버전을 올리는 배포를 했습니다. 배포 파이프라인에서 '배포가 끝나지 않는다'는 알림이 왔습니다." ;;
  2) kubectl patch deploy shop-api -n shop --type json -p '[{"op":"add","path":"/spec/template/spec/containers/0/command","value":["gunicorn","--bind","0.0.0.0:5000","app:application"]}]' >/dev/null
     MSG="[장애 2] shop-api 개발자가 실행 명령을 정리하는 배포를 했습니다. 배포가 실패로 표시되고, 새 Pod의 재시작 횟수가 계속 늘어납니다." ;;
  3) kubectl patch deploy shop-api -n shop --type merge -p '{"spec":{"template":{"spec":{"nodeSelector":{"tier":"fornt"}}}}}' >/dev/null
     MSG="[장애 3] shop-api의 배치 규칙을 정리하는 배포가 나갔습니다. 새 버전 Pod가 실행되지 않는다는 문의가 들어왔습니다." ;;
  4) kubectl patch svc shop-api -n shop --type merge -p '{"spec":{"selector":{"tier":"apl"}}}' >/dev/null
     MSG="[장애 4] 고객센터: '쇼핑몰 화면에 API 연결 실패가 뜹니다.' 방금 누군가 Service 설정을 손봤다고 합니다." ;;
  5) kubectl patch deploy shop-web -n shop --type json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"2Gi"}]' >/dev/null
     MSG="[장애 5] shop-web 메모리 한도를 넉넉히 늘리는 배포를 했습니다. 배포가 끝나지 않는데, 새 Pod가 목록에 보이지 않습니다." ;;
  6) kubectl patch deploy shop-api -n shop --type json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/envFrom/0/configMapRef/name","value":"shop-cofig"}]' >/dev/null
     MSG="[장애 6 · 선택] 설정 이름을 정리하는 배포가 나갔습니다. shop-api 새 Pod가 시작되지 못합니다." ;;
esac
rm -f "$STATE/fixed-$N"; date +%s > "$STATE/broken-$N"
echo "$MSG"
echo "→ 원인을 찾아 복구한 뒤  bash $DIR/check.sh $N  으로 확인하세요."
