#!/usr/bin/env bash
# Lab03 채점 — cap-master 노드 셸(root)에서 실행
# 사용: bash ~/k8s-labs-7days/lab03-pod/verify.sh
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
[ -f "$KUBECONFIG" ] || export KUBECONFIG=/etc/kubernetes/admin.conf
k() { kubectl "$@" 2>/dev/null; }
jp() { k get "$1" "$2" -n shop -o jsonpath="$3"; }

echo "[Lab03  shop 첫 배포 — Pod · ConfigMap · Secret · Label]"
ns_ok()        { k get ns shop; }
api_ready()    { [ "$(jp pod shop-api '{.status.conditions[?(@.type=="Ready")].status}')" = "True" ]; }
api_image()    { [ "$(jp pod shop-api '{.spec.containers[?(@.name=="api")].image}')" = "ghcr.io/worldvit/skillboost-api:v1" ]; }
api_labels()   { [ "$(jp pod shop-api '{.metadata.labels.app},{.metadata.labels.tier},{.metadata.labels.version}')" = "shop,api,v1" ]; }
api_envfrom()  { jp pod shop-api '{.spec.containers[?(@.name=="api")].envFrom[*].configMapRef.name}' | grep -qw shop-config; }
api_secret()   { [ "$(jp pod shop-api '{.spec.containers[?(@.name=="api")].env[?(@.name=="DB_PASSWORD")].valueFrom.secretKeyRef.name}')" = "shop-db-secret" ]; }
api_http()     { local ip; ip=$(jp pod shop-api '{.status.podIP}'); [ -n "$ip" ] && curl -s -m 5 "http://$ip:5000/api/products" | grep -q '"title"'; }
web_ready()    { [ "$(jp pod shop-web '{.status.conditions[?(@.type=="Ready")].status}')" = "True" ]; }
web_sidecar()  { [ "$(jp pod shop-web '{.spec.initContainers[?(@.name=="log-agent")].restartPolicy}')" = "Always" ]; }
web_shared()   {
  [ "$(jp pod shop-web '{.spec.initContainers[?(@.name=="log-agent")].volumeMounts[?(@.mountPath=="/var/log/nginx")].name}')" = "logs" ] &&
  [ "$(jp pod shop-web '{.spec.containers[?(@.name=="nginx")].volumeMounts[?(@.mountPath=="/var/log/nginx")].name}')" = "logs" ] &&
  [ -n "$(jp pod shop-web '{.spec.volumes[?(@.name=="logs")].emptyDir}')" ]
}
web_html()     { local ip; ip=$(jp pod shop-web '{.status.podIP}'); [ "$(jp pod shop-web '{.spec.volumes[?(@.configMap.name=="shop-web-html")].name}')" != "" ] && curl -s -m 5 "http://$ip/" | grep -q "SkillBoost"; }
cm_ok()        { [ "$(jp configmap shop-config '{.data.DB_MODE}')" = "memory" ] && [ -n "$(jp configmap shop-config '{.data.APP_TITLE}')" ] && k get configmap shop-web-html -n shop -o jsonpath='{.data}' | grep -q 'index.html'; }
secret_ok()    { [ "$(jp secret shop-db-secret '{.type}')" = "Opaque" ] && [ -n "$(jp secret shop-db-secret '{.data.DB_PASSWORD}')" ]; }
anno_ok()      { [ -n "$(jp pod shop-api '{.metadata.annotations.owner}')" ]; }

check "Namespace shop"                                   ns_ok
check "shop-api Pod Ready"                               api_ready
check "shop-api 이미지 skillboost-api:v1"                api_image
check "shop-api 라벨 app=shop · tier=api · version=v1"   api_labels
check "shop-api envFrom shop-config"                     api_envfrom
check "shop-api DB_PASSWORD ← Secret shop-db-secret"     api_secret
check "shop-api /api/products 응답"                      api_http
check "shop-web Pod Ready (nginx + 사이드카)"            web_ready
check "shop-web log-agent 네이티브 사이드카"             web_sidecar
check "shop-web emptyDir 공유 (/var/log/nginx)"          web_shared
check "shop-web 화면 (ConfigMap shop-web-html)"          web_html
check "ConfigMap shop-config · shop-web-html"            cm_ok
check "Secret shop-db-secret (Opaque · DB_PASSWORD)"     secret_ok
check "shop-api 어노테이션 owner"                        anno_ok
summary
