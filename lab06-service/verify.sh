#!/usr/bin/env bash
# Lab06 채점 — cap-master 노드 셸(root)에서 실행
# 사용: bash ~/k8s-labs-7days/lab06-service/verify.sh
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
[ -f "$KUBECONFIG" ] || export KUBECONFIG=/etc/kubernetes/admin.conf
k() { kubectl "$@" 2>/dev/null; }
g() { k get "$1" "$2" -n shop -o jsonpath="$3"; }
nip() { k get node "$1" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}'; }

echo "[Lab06  Service — ClusterIP · DNS · NodePort]"
api_svc()    { [ "$(g svc shop-api '{.spec.type}|{.spec.ports[0].port}|{.spec.selector}')" = 'ClusterIP|5000|{"app":"shop","tier":"api"}' ]; }
api_eps()    { [ "$(k get endpointslice -n shop -l kubernetes.io/service-name=shop-api -o jsonpath='{range .items[*].endpoints[?(@.conditions.ready==true)]}{.addresses[0]}{"\n"}{end}' | grep -c .)" = "2" ]; }
cfg_mysql()  { [ "$(g configmap shop-config '{.data.DB_MODE}')" = "mysql" ]; }
api_mysql()  { local ip; ip=$(g svc shop-api '{.spec.clusterIP}'); curl -s -m 5 "http://$ip:5000/api/products" | python3 -c 'import sys,json;d=json.load(sys.stdin);sys.exit(0 if d["source"]=="mysql" and len(d["items"])==5 else 1)'; }
nginx_cm()   { g configmap shop-web-nginx '{.data.default\.conf}' | grep -q 'proxy_pass http://shop-api:5000'; }
web_mount()  { [ "$(g deploy shop-web '{.spec.template.spec.containers[?(@.name=="nginx")].volumeMounts[?(@.mountPath=="/etc/nginx/conf.d")].name}')" = "nginx-conf" ] && [ "$(g deploy shop-web '{.status.availableReplicas}')" = "2" ]; }
web_svc()    { [ "$(g svc shop-web '{.spec.type}|{.spec.ports[0].port}|{.spec.ports[0].nodePort}|{.spec.externalTrafficPolicy}')" = "NodePort|80|30080|Cluster" ]; }
np_page()    { curl -s -m 5 "http://$(nip cap-node1):30080/" | grep -q "<title>SkillBoost"; }
np_api()     { curl -s -m 5 "http://$(nip cap-node2):30080/api/products" | python3 -c 'import sys,json;sys.exit(0 if json.load(sys.stdin)["source"]=="mysql" else 1)'; }
lab_clean()  { [ -z "$(k get svc -n shop -o name | grep '/lab06-')" ]; }
prev_ok()    { [ "$(g sts shop-db '{.status.readyReplicas}')" = "1" ] && [ "$(g ds shop-log-agent '{.status.numberReady}')" = "2" ]; }
file_sync()  { grep -q 'DB_MODE: "mysql"' "$HOME/shop/shop-config.yaml" 2>/dev/null && grep -q 'nginx-conf' "$HOME/shop/shop-web-deploy.yaml" 2>/dev/null; }

check "Service shop-api (ClusterIP · 5000 · selector)"        api_svc
check "shop-api EndpointSlice ready 엔드포인트 2개"            api_eps
check "shop-config DB_MODE=mysql"                             cfg_mysql
check "ClusterIP로 /api/products — mysql · 5개"               api_mysql
check "ConfigMap shop-web-nginx (/api → shop-api:5000)"       nginx_cm
check "shop-web nginx 설정 마운트 · 2/2 가용"                  web_mount
check "Service shop-web (NodePort 30080 · Cluster 정책)"       web_svc
check "cap-node1:30080 쇼핑몰 화면"                            np_page
check "cap-node2:30080/api/products — mysql (다른 노드 경유)"  np_api
check "연습 Service(lab06-*) 정리"                             lab_clean
check "shop-db · shop-log-agent 유지"                         prev_ok
check "~/shop 파일 동기화 (shop-config · shop-web-deploy)"     file_sync
summary
