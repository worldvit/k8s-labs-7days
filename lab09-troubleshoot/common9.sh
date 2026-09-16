#!/usr/bin/env bash
# Lab09 공통 — 장애 판정 함수
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
[ -f "$KUBECONFIG" ] || export KUBECONFIG=/etc/kubernetes/admin.conf
STATE="$HOME/.lab09"; mkdir -p "$STATE"
k() { kubectl "$@" 2>/dev/null; }
g() { k get "$1" "$2" -n shop -o jsonpath="$3"; }
rollout_ok() { kubectl rollout status "deploy/$1" -n shop --timeout=10s >/dev/null 2>&1; }
n1ip() { k get node cap-node1 -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}'; }

healthy() {  # healthy <N>
  case "$1" in
    1) [ "$(g deploy shop-web '{.spec.template.spec.containers[?(@.name=="nginx")].image}')" = "nginx:1.30-alpine" ] && rollout_ok shop-web ;;
    2) [ -z "$(g deploy shop-api '{.spec.template.spec.containers[0].command}')" ] && rollout_ok shop-api ;;
    3) [ "$(g deploy shop-api '{.spec.template.spec.nodeSelector.tier}')" = "front" ] && rollout_ok shop-api ;;
    4) [ "$(g svc shop-api '{.spec.selector}')" = '{"app":"shop","tier":"api"}' ] &&
       [ "$(k get endpointslice -n shop -l kubernetes.io/service-name=shop-api -o jsonpath='{range .items[*].endpoints[?(@.conditions.ready==true)]}{.addresses[0]}{"\n"}{end}' | grep -c .)" -ge 2 ] &&
       [ "$(curl -s -m 5 -o /dev/null -w '%{http_code}' "http://$(n1ip):30080/api/products")" = "200" ] ;;
    5) [ "$(g deploy shop-web '{.spec.template.spec.containers[?(@.name=="nginx")].resources.limits.memory}')" = "128Mi" ] && rollout_ok shop-web ;;
    6) [ "$(g deploy shop-api '{.spec.template.spec.containers[0].envFrom[0].configMapRef.name}')" = "shop-config" ] && rollout_ok shop-api ;;
    *) return 1 ;;
  esac
}
