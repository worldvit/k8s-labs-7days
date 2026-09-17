#!/usr/bin/env bash
# Lab10 채점 — cap-master 노드 셸(root)에서 실행
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
[ -f "$KUBECONFIG" ] || export KUBECONFIG=/etc/kubernetes/admin.conf
k() { kubectl "$@" 2>/dev/null; }
g() { k get "$1" "$2" -n shop -o jsonpath="$3"; }
nip() { k get node "$1" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}'; }

echo "[Lab10  Gateway API — Helm · NGINX Gateway Fabric · HTTPRoute]"
helm_ok()    { helm version --short 2>/dev/null | grep -q '^v4\.3\.'; }
crd_ok()     { [ "$(k get crd gateways.gateway.networking.k8s.io -o jsonpath='{.metadata.annotations.gateway\.networking\.k8s\.io/bundle-version},{.metadata.annotations.gateway\.networking\.k8s\.io/channel}')" = "v1.6.1,standard" ]; }
release_ok() { helm list -n nginx-gateway -o json 2>/dev/null | python3 -c 'import sys,json;r=[x for x in json.load(sys.stdin) if x["name"]=="ngf"];sys.exit(0 if r and r[0]["chart"]=="nginx-gateway-fabric-2.7.1" and r[0]["status"]=="deployed" else 1)'; }
history_ok() { helm history ngf -n nginx-gateway -o json 2>/dev/null | python3 -c 'import sys,json;h=json.load(sys.stdin);sys.exit(0 if len(h)>=3 and any("Rollback" in x.get("description","") for x in h) else 1)'; }
values_ok()  { helm get values ngf -n nginx-gateway -o json 2>/dev/null | python3 -c 'import sys,json;v=json.load(sys.stdin);s=v["nginx"]["service"];sys.exit(0 if v["nginxGateway"]["productTelemetry"]["enable"] is False and s["type"]=="NodePort" and s["externalTrafficPolicy"]=="Cluster" and s["nodePorts"][0]["port"]==31080 and "config" not in v["nginxGateway"] else 1)'; }
gc_ok()      { [ "$(k get gatewayclass nginx -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}')" = "True" ]; }
gw_ok()      { [ "$(g gateway shop-gateway '{.status.conditions[?(@.type=="Programmed")].status}')" = "True" ]; }
dp_svc()     { [ "$(g svc shop-gateway-nginx '{.spec.type}|{.spec.ports[0].nodePort}|{.spec.externalTrafficPolicy}')" = "NodePort|31080|Cluster" ]; }
route_ok()   { [ "$(g httproute shop-route '{.status.parents[0].conditions[?(@.type=="Accepted")].status}|{.status.parents[0].conditions[?(@.type=="ResolvedRefs")].status}')" = "True|True" ]; }
rules_ok()   { [ "$(g httproute shop-route '{range .spec.rules[*]}{.matches[0].path.value}={.backendRefs[0].name}:{.backendRefs[0].port} {end}')" = "/api=shop-api:5000 /=shop-web:80 " ]; }
e2e_web()    { curl -s -m 5 "http://$(nip cap-node1):31080/" | grep -q "<title>SkillBoost"; }
e2e_api()    { curl -s -m 5 "http://$(nip cap-node1):31080/api/products" | python3 -c 'import sys,json;d=json.load(sys.stdin);sys.exit(0 if d["source"]=="mysql" and len(d["items"])==5 else 1)'; }
e2e_node2()  { [ "$(curl -s -m 5 -o /dev/null -w '%{http_code}' "http://$(nip cap-node2):31080/api/version")" = "200" ]; }
clean_ok()   { [ "$(k get httproute -n shop -o name | tr '\n' ' ')" = "httproute.gateway.networking.k8s.io/shop-route " ] && [ -z "$(k get deploy,svc -n shop -o name | grep lab10-)" ]; }
files_ok()   { for f in ngf-values.yaml shop-gateway.yaml shop-route.yaml; do [ -s "$HOME/shop/$f" ] || return 1; done; }

check "Helm 4.3.x 설치"                                        helm_ok
check "Gateway API CRD v1.6.1 · standard"                      crd_ok
check "Helm 릴리스 ngf (nginx-gateway-fabric-2.7.1 · deployed)" release_ok
check "Helm 업그레이드 · 롤백 이력"                              history_ok
check "릴리스 values (NodePort 31080 · Cluster · 텔레메트리 끔)" values_ok
check "GatewayClass nginx Accepted"                            gc_ok
check "Gateway shop-gateway Programmed"                        gw_ok
check "데이터플레인 svc shop-gateway-nginx (31080 · Cluster)"   dp_svc
check "HTTPRoute shop-route Accepted · ResolvedRefs"           route_ok
check "shop-route 규칙 (/api → shop-api · / → shop-web)"        rules_ok
check "cap-node1:31080 쇼핑몰 화면"                              e2e_web
check "cap-node1:31080/api/products (mysql · 5개)"              e2e_api
check "cap-node2:31080 응답 (Cluster 정책)"                      e2e_node2
check "연습 리소스(lab10-*) 정리 · Route는 shop-route만"         clean_ok
check "~/shop manifest 파일 (values · gateway · route)"         files_ok
summary
