#!/usr/bin/env bash
# LabE 채점 — CloudShell에서 실행 (kubectl + aws CLI)
# 사용: bash ~/k8s-labs-7days/labE-eks/verify.sh
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"
export AWS_PAGER=""
REGION="${REGION:-ap-northeast-2}"
CLUSTER="${CLUSTER:-cap-eks}"
a() { aws "$@" --region "$REGION" --output text 2>/dev/null; }
k() { kubectl "$@" 2>/dev/null; }
g() { k get "$1" "$2" -n shop -o jsonpath="$3"; }
ALB=$(k get ingress shop -n shop -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
dbq() { echo "$1" | k exec -i -n shop shop-db-0 -c mysql -- sh -c 'printf "[client]\npassword=\"%s\"\n" "$MYSQL_PASSWORD" > /tmp/v.cnf; mysql --defaults-extra-file=/tmp/v.cnf -N -u shop shop; rc=$?; rm -f /tmp/v.cnf; exit $rc'; }

echo "[LabE  AWS EKS — 클러스터 · 애드온 · 이전 · ALB Controller]"
cluster_ok()  { [ "$(a eks describe-cluster --name "$CLUSTER" --query 'cluster.[status,version]' | tr '\t' '|')" = "ACTIVE|1.36" ]; }
nodegroup()   { [ "$(a eks describe-nodegroup --cluster-name "$CLUSTER" --nodegroup-name ng-app --query 'nodegroup.[status,scalingConfig.desiredSize]' | tr '\t' '|')" = "ACTIVE|2" ]; }
nodes_ready() { [ "$(k get nodes -l tier=front --no-headers | grep -c ' Ready')" -ge 2 ]; }
addons()      { for n in vpc-cni coredns kube-proxy eks-pod-identity-agent aws-ebs-csi-driver; do [ "$(a eks describe-addon --cluster-name "$CLUSTER" --addon-name "$n" --query 'addon.status')" = "ACTIVE" ] || return 1; done; }
oidc()        { local i; i=$(a eks describe-cluster --name "$CLUSTER" --query 'cluster.identity.oidc.issuer'); [ -n "$i" ] && a iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[].Arn' | tr '\t' '\n' | grep -q "${i#https://}"; }
sc_ok()       { [ "$(k get sc gp3 -o jsonpath='{.provisioner}|{.volumeBindingMode}|{.parameters.type}|{.parameters.csi\.storage\.k8s\.io/fstype}')" = "ebs.csi.aws.com|WaitForFirstConsumer|gp3|xfs" ]; }
pvc_ok()      { local pv; [ "$(g pvc data-shop-db-0 '{.status.phase}|{.spec.storageClassName}')" = "Bound|gp3" ] && pv=$(g pvc data-shop-db-0 '{.spec.volumeName}') && k get pv "$pv" -o jsonpath='{.spec.csi.volumeHandle}' | grep -q '^vol-'; }
db_ok()       { [ "$(g pod shop-db-0 '{.status.conditions[?(@.type=="Ready")].status}')" = "True" ] && k exec -n shop shop-db-0 -c mysql -- cat /proc/mounts | grep -q ' /var/lib/mysql xfs '; }
app_ok()      { [ "$(g deploy shop-api '{.status.availableReplicas}')" -ge 2 ] 2>/dev/null && [ "$(g deploy shop-web '{.status.availableReplicas}')" -ge 2 ] 2>/dev/null; }
data_ok()     { [ "$(dbq 'SELECT COUNT(*) FROM products')" = "5" ]; }
lbc_ok()      { [ "$(k get deploy aws-load-balancer-controller -n kube-system -o jsonpath='{.status.availableReplicas}')" -ge 1 ] 2>/dev/null && k get sa aws-load-balancer-controller -n kube-system -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' | grep -q '^arn:aws:iam::'; }
ingclass()    { [ "$(k get ingressclass alb -o jsonpath='{.spec.controller}')" = "ingress.k8s.aws/alb" ]; }
ingress_ok()  { [ -n "$ALB" ] && [ "$(g ingress shop '{.spec.rules[0].http.paths[0].path}|{.spec.rules[0].http.paths[0].backend.service.name}')" = "/api|shop-api" ]; }
alb_http()    { [ "$(curl -s -o /dev/null -m 10 -w '%{http_code}' "http://$ALB/")" = "200" ] && curl -s -m 10 "http://$ALB/api/products" | python3 -c 'import sys,json;d=json.load(sys.stdin);sys.exit(0 if d["source"]=="mysql" and len(d["items"])==5 else 1)'; }
alb_aws()     { local arn; arn=$(a elbv2 describe-load-balancers --query "LoadBalancers[?DNSName=='$ALB'].LoadBalancerArn"); [ -n "$arn" ] && [ "$(a elbv2 describe-load-balancers --load-balancer-arns "$arn" --query 'LoadBalancers[0].Scheme')" = "internet-facing" ] && [ "$(a elbv2 describe-target-groups --load-balancer-arn "$arn" --query 'TargetGroups[0].TargetType')" = "ip" ]; }
files_ok()    { local d="$HOME/eks"; grep -q 'name: cap-eks' "$d/cap-eks.yaml" && grep -q 'ingressClassName: alb' "$d/shop-ingress.yaml" && grep -q 'storageClassName: gp3' "$d/shop-db-sts.yaml"; } 2>/dev/null

check "EKS 클러스터 cap-eks (ACTIVE · v1.36)"                 cluster_ok
check "관리형 노드 그룹 ng-app (ACTIVE · 2대)"                 nodegroup
check "노드 2대 Ready · 라벨 tier=front"                       nodes_ready
check "애드온 5종 ACTIVE (vpc-cni · coredns · kube-proxy · pod-identity · ebs-csi)" addons
check "IRSA용 OIDC 공급자 등록"                                oidc
check "StorageClass gp3 (ebs.csi.aws.com · WaitForFirstConsumer · xfs)" sc_ok
check "PVC data-shop-db-0 Bound → EBS 볼륨(vol-)"              pvc_ok
check "shop-db-0 Ready · /var/lib/mysql = xfs"                 db_ok
check "shop-api · shop-web 각각 2개 가용"                       app_ok
check "상품 데이터 5행 (seed 적재)"                             data_ok
check "AWS Load Balancer Controller 가용 · IRSA 역할 연결"      lbc_ok
check "IngressClass alb (ingress.k8s.aws/alb)"                 ingclass
check "Ingress shop — /api → shop-api · ALB 주소 할당"          ingress_ok
check "ALB 응답 (/ 200 · /api/products mysql 5개)"              alb_http
check "ALB internet-facing · 대상 그룹 target-type ip"          alb_aws
check "~/eks 파일 (cap-eks · ingress · sts)"                   files_ok
summary
