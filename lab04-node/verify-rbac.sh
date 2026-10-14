#!/usr/bin/env bash
# Lab04 Part 3(RBAC 기초) 채점 — cap-master 노드 셸(root)에서 실행
# 사용: bash ~/k8s-labs-7days/lab04-node/verify-rbac.sh   (Part 3 정리 단계 전에 실행)
# 누적 채점(verify-all.sh)에는 포함하지 않음
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$DIR/../lib/common.sh"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
[ -f "$KUBECONFIG" ] || export KUBECONFIG=/etc/kubernetes/admin.conf
k() { kubectl "$@" 2>/dev/null; }
SA=system:serviceaccount:rbac:viewer
can() { [ "$(k auth can-i "$@" --as="$SA")" = "yes" ]; }
F="$HOME/rbac/rbac-viewer.yaml"

echo "[Lab04 Part 3  RBAC 기초 — ServiceAccount · Role · RoleBinding]"
ns_sa()      { k get namespace rbac && k get serviceaccount viewer -n rbac; }
rb_role()    { [ "$(k get rolebinding viewer-pod-reader -n rbac -o jsonpath='{.roleRef.kind}/{.roleRef.name}|{.subjects[0].kind}/{.subjects[0].namespace}/{.subjects[0].name}')" = "Role/pod-reader|ServiceAccount/rbac/viewer" ]; }
rb_view()    { [ "$(k get rolebinding viewer-view -n rbac -o jsonpath='{.roleRef.kind}/{.roleRef.name}|{.subjects[0].name}')" = "ClusterRole/view|viewer" ]; }
read_ok()    { can list pods -n rbac && can get pods --subresource=log -n rbac; }
deploy_ok()  { can list deployments -n rbac; }
denied()     { ! can delete pods -n rbac && ! can list pods -n shop && ! can list secrets -n rbac; }
no_crb()     { ! k get clusterrolebindings -o jsonpath='{range .items[*]}{range .subjects[*]}{.kind}/{.namespace}/{.name}{"\n"}{end}{end}' | grep -qx 'ServiceAccount/rbac/viewer'; }
web_sa()     { [ "$(k get deploy rbac-web -n rbac -o jsonpath='{.spec.template.spec.serviceAccountName}|{.status.availableReplicas}')" = "viewer|1" ]; }
file_ok()    { [ -f "$F" ] && grep -q 'apiGroups: \["apps"\]' "$F" && grep -q 'kind: RoleBinding' "$F"; }

check "네임스페이스 rbac · ServiceAccount viewer (정리 전에 채점)"  ns_sa
check "RoleBinding viewer-pod-reader → Role pod-reader · SA viewer"  rb_role
check "RoleBinding viewer-view → ClusterRole view"                    rb_view
check "viewer  rbac에서 Pod 목록 · 로그 읽기 가능"                    read_ok
check "viewer  rbac에서 Deployment 목록 가능 (apps 그룹 수정)"        deploy_ok
check "viewer  Pod 삭제 · shop 조회 · Secret 조회 모두 거부"          denied
check "viewer에 ClusterRoleBinding 없음 (클러스터 전체 권한 아님)"    no_crb
check "rbac-web  serviceAccountName viewer · 1/1 가용"                web_sa
check "~/rbac/rbac-viewer.yaml (apps 그룹 · RoleBinding 포함)"        file_ok
summary
