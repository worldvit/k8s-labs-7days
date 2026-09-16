#!/usr/bin/env bash
# Lab09 채점 — cap-master 노드 셸(root)에서 실행
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"; source "$DIR/common9.sh"
echo "[Lab09  트러블슈팅 — 장애 5종 진단 · 복구]"
fixed() { [ -f "$STATE/broken-$1" ] && [ -f "$STATE/fixed-$1" ]; }
for i in 1 2 3 4 5; do check "장애 $i 주입 후 복구 기록" fixed $i; done
all_ok() { for i in 1 2 3 4 5 6; do healthy $i || return 1; done; }
api_spec() { [ "$(g deploy shop-api '{.spec.template.spec.containers[0].image}|{.spec.template.spec.containers[0].resources.requests.cpu}|{.spec.template.spec.containers[0].startupProbe.httpGet.path}')" = "ghcr.io/worldvit/skillboost-api:v2|100m|/healthz" ]; }
web_spec() { [ -n "$(g deploy shop-web '{.spec.template.spec.volumes[?(@.name=="nginx-conf")].configMap.name}')" ] && [ "$(g deploy shop-web '{.spec.template.spec.initContainers[0].resources.limits.memory}')" = "32Mi" ]; }
files_ok() { grep -q 'skillboost-api:v2' "$HOME/shop/shop-api-deploy.yaml" && ! grep -q 'command:' "$HOME/shop/shop-api-deploy.yaml" && grep -q 'nginx:1.30-alpine' "$HOME/shop/shop-web-deploy.yaml" && grep -q 'memory: 128Mi}' "$HOME/shop/shop-web-deploy.yaml" && grep -q 'tier: api' "$HOME/shop/shop-api-svc.yaml"; }
check "현재 모든 장애 판정 항목 정상 (선택 장애 6 포함)"   all_ok
check "shop-api가 이전 실습 설정 유지 (v2 · 자원 · Probe)"  api_spec
check "shop-web이 이전 실습 설정 유지 (프록시 · 사이드카 자원)" web_spec
check "~/shop manifest 파일이 장애 전 내용 유지"           files_ok
summary
