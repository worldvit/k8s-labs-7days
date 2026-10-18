#!/usr/bin/env bash
# Lab08 Part 4 용량 계획 계산 도구 — cap-master 노드 셸(root)에서 실행 (채점 아님)
# 표의 열: ALLOCATABLE(노드 가용량) FIXED(고정분) APP-SHARE(앱 몫) APP-USED(앱 사용 중) FREE(남은 자리), 값은 CPU m/메모리 Mi
# 사용: bash ~/k8s-labs-7days/lab08-resources/capacity-calc.sh [옵션]
#   --reserve-cpu=250m   여유분(maxSurge · N+1 등)으로 남겨 둘 CPU  (기본 0)
#   --reserve-mem=256Mi  여유분으로 남겨 둘 메모리                  (기본 0)
#   --only=team-a,team-b 이 네임스페이스들의 Quota만, "다른 네임스페이스가 지금 쓰는 몫을 뺀 남은 자리"와 비교
# 계산 기준 (모두 requests 기준 — 스케줄러가 보는 값)
#   앱 풀    = NoSchedule · NoExecute taint가 없는 노드
#   고정분   = 시스템 네임스페이스(kube-* · calico-* · tigera-operator) Pod + DaemonSet Pod
#   Pod 요청 = 컨테이너 합 + 사이드카(restartPolicy: Always 초기화 컨테이너)
#              일반 초기화 컨테이너가 더 크면 그 값 (Pod overhead는 무시)
set -uo pipefail
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
[ -f "$KUBECONFIG" ] || export KUBECONFIG=/etc/kubernetes/admin.conf

RES_CPU=0; RES_MEM=0; ONLY=""
FIXED_NS='^(kube-.*|calico-.*|tigera-operator)$'
for a in "$@"; do
  case "$a" in
    --reserve-cpu=*) RES_CPU="${a#*=}" ;;
    --reserve-mem=*) RES_MEM="${a#*=}" ;;
    --only=*)        ONLY="${a#*=}" ;;
    -h|--help)       sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "알 수 없는 옵션: $a  (--help 참고)" >&2; exit 2 ;;
  esac
done
command -v kubectl >/dev/null || { echo "kubectl이 없습니다" >&2; exit 1; }

nodes=$(kubectl get nodes -o jsonpath='{range .items[*]}N	{.metadata.name}	{.status.allocatable.cpu}	{.status.allocatable.memory}	{range .spec.taints[*]}{.key}={.value}:{.effect},{end}{"\n"}{end}') \
  || { echo "노드 정보를 읽지 못했습니다" >&2; exit 1; }
pods=$(kubectl get pods -A --field-selector=status.phase!=Succeeded,status.phase!=Failed \
  -o jsonpath='{range .items[*]}P	{.spec.nodeName}	{.metadata.namespace}	{.metadata.ownerReferences[0].kind}	{range .spec.containers[*]}{.resources.requests.cpu}/{.resources.requests.memory},{end}	{range .spec.initContainers[*]}{.restartPolicy}/{.resources.requests.cpu}/{.resources.requests.memory},{end}{"\n"}{end}')
quotas=$(kubectl get resourcequota -A \
  -o jsonpath='{range .items[*]}Q	{.metadata.namespace}	{.metadata.name}	{.spec.hard.requests\.cpu}	{.spec.hard.cpu}	{.spec.hard.requests\.memory}	{.spec.hard.memory}	{.status.used.requests\.cpu}	{.status.used.cpu}	{.status.used.requests\.memory}	{.status.used.memory}{"\n"}{end}')
limits=$(kubectl get limitrange -A \
  -o jsonpath='{range .items[*]}L	{.metadata.namespace}	{.metadata.name}	{range .spec.limits[?(@.type=="Container")]}{.max.cpu}	{.max.memory}{end}{"\n"}{end}')

printf '%s\n%s\n%s\n%s\n' "$nodes" "$pods" "$quotas" "$limits" | awk -F'\t' \
  -v rescpu="$RES_CPU" -v resmem="$RES_MEM" -v only="$ONLY" -v fixedns="$FIXED_NS" '
function cpu(v) {            # → 밀리코어
  if (v == "") return 0
  if (v ~ /n$/) return substr(v, 1, length(v)-1) / 1000000
  if (v ~ /u$/) return substr(v, 1, length(v)-1) / 1000
  if (v ~ /m$/) return substr(v, 1, length(v)-1) + 0
  return v * 1000
}
function mem(v,   n, s) {    # → Mi
  if (v == "") return 0
  if (match(v, /[A-Za-z]+$/)) { n = substr(v, 1, RSTART-1); s = substr(v, RSTART) } else { n = v; s = "" }
  if (s == "Ki") return n / 1024
  if (s == "Mi") return n + 0
  if (s == "Gi") return n * 1024
  if (s == "Ti") return n * 1048576
  if (s == "k")  return n * 1000 / 1048576
  if (s == "M")  return n * 1000000 / 1048576
  if (s == "G")  return n * 1000000000 / 1048576
  if (s == "T")  return n * 1000000000000 / 1048576
  if (s == "m")  return n / 1000 / 1048576
  return n / 1048576
}
function r(x) { return sprintf("%d", x + 0.5) }
function podreq(c, ic,   a, b, f, i, n, sc, sm, kc, km, ic_c, ic_m) {
  sc = sm = kc = km = 0
  n = split(c, a, ",")
  for (i = 1; i <= n; i++) if (a[i] != "") { split(a[i], f, "/"); sc += cpu(f[1]); sm += mem(f[2]) }
  n = split(ic, b, ",")
  for (i = 1; i <= n; i++) if (b[i] != "") {
    split(b[i], f, "/")
    if (f[1] == "Always") { sc += cpu(f[2]); sm += mem(f[3]) }      # 사이드카는 계속 실행 → 합산
    else { if (cpu(f[2]) > kc) kc = cpu(f[2]); if (mem(f[3]) > km) km = mem(f[3]) }
  }
  PC = (kc > sc ? kc : sc); PM = (km > sm ? km : sm)
}
BEGIN {
  nsel = split(only, sel, ","); for (i = 1; i <= nsel; i++) if (sel[i] != "") pick[sel[i]] = 1
  rc = cpu(rescpu); rm = mem(resmem)
}
$1 == "N" {
  nn++; nm[nn] = $2; ac[$2] = cpu($3); am[$2] = mem($4); tn = ""
  k = split($5, t, ",")
  for (i = 1; i <= k; i++) if (t[i] ~ /:(NoSchedule|NoExecute)$/) { s = t[i]; sub(/:.*/, "", s); sub(/=$/, "", s); tn = (tn == "" ? s : tn " " s) }
  taint[$2] = tn; app[$2] = (tn == "")
}
$1 == "P" {
  podreq($5, $6)
  if ($2 == "") { pendc += PC; pendm += PM; if ($3 in pick) { pkpc += PC; pkpm += PM }; next }
  if ($3 ~ fixedns || $4 == "DaemonSet") { fc[$2] += PC; fm[$2] += PM }
  else { uc[$2] += PC; um[$2] += PM; if ($3 in pick) { kpc[$2] += PC; kpm[$2] += PM } }
}
$1 == "Q" {
  nq++; qn[nq] = $2 "/" $3
  qhc[nq] = ($4 != "" ? $4 : $5); qhm[nq] = ($6 != "" ? $6 : $7)
  quc[nq] = ($8 != "" ? $8 : $9); qum[nq] = ($10 != "" ? $10 : $11); qns[nq] = $2
}
$1 == "L" && ($4 != "" || $5 != "") { nl++; ln[nl] = $2 "/" $3; lc[nl] = $4; lm[nl] = $5 }
END {
  if (nn == 0) { print "노드가 없습니다"; exit 1 }
  print "[용량 계산 — 노드 · 고정분 · 앱 몫 · Quota 합계]  (requests 기준 · CPU m · 메모리 Mi)"
  print ""
  print "① 노드별"
  printf "  %-12s %-6s %-13s %-13s %-13s %-13s %-13s\n", "NODE", "POOL", "ALLOCATABLE", "FIXED", "APP-SHARE", "APP-USED", "FREE"
  for (i = 1; i <= nn; i++) {
    n = nm[i]; sc = ac[n] - fc[n]; sm = am[n] - fm[n]
    printf "  %-12s %-6s %-13s %-13s %-13s %-13s %-13s\n", n, (app[n] ? "app" : "other"),
      r(ac[n]) "/" r(am[n]), r(fc[n]) "/" r(fm[n]), r(sc) "/" r(sm), r(uc[n]) "/" r(um[n]), r(sc - uc[n]) "/" r(sm - um[n])
    if (!app[n]) printf "  %-12s └ taint: %s\n", "", taint[n]
    if (app[n]) {
      apn++; tac += sc; tam += sm; tuc += uc[n]; tum += um[n]; tkc += kpc[n]; tkm += kpm[n]
      if (sc > mxc) mxc = sc; if (sm > mxm) mxm = sm
    }
  }
  printf "  배치 대기(Pending) Pod의 requests: %sm / %sMi\n", r(pendc), r(pendm)
  print ""
  print "② 앱 풀 합계 (taint 없는 노드 " apn + 0 "대)"
  if (apn == 0) { print "  앱 풀 노드가 없습니다"; exit 0 }
  pc = tac - rc; pm = tam - rm
  printf "  앱 몫 합계                %6sm / %6sMi\n", r(tac), r(tam)
  printf "  여유분(--reserve)       - %5sm / - %5sMi\n", r(rc), r(rm)
  printf "  계획 가능한 몫            %6sm / %6sMi\n", r(pc), r(pm)
  print ""
  if (nsel > 0 && only != "") {
    fc2 = tac - (tuc - tkc) - rc; fm2 = tam - (tum - tkm) - rm
    print "③ 선택한 네임스페이스의 Quota (" only ")"
    printf "  다른 네임스페이스가 쓰는 몫을 뺀 남은 자리 %6sm / %6sMi  (여유분 제외 후)\n", r(fc2), r(fm2)
    capc = fc2; capm = fm2; lbl = "남은 자리"
  } else {
    print "③ 네임스페이스 Quota (전체)"
    capc = pc; capm = pm; lbl = "계획 가능한 몫"
  }
  printf "  %-26s %-15s %-15s\n", "NAMESPACE/QUOTA", "HARD", "USED"
  for (i = 1; i <= nq; i++) {
    if (nsel > 0 && only != "" && !(qns[i] in pick)) continue
    if (qhc[i] == "" && qhm[i] == "") continue
    hc = cpu(qhc[i]); hm = mem(qhm[i]); shown++
    printf "  %-26s %-15s %-15s\n", qn[i], (qhc[i] == "" ? "-" : r(hc)) "/" (qhm[i] == "" ? "-" : r(hm)), r(cpu(quc[i])) "/" r(mem(qum[i]))
    if (qhc[i] == "") nocpu = 1; else sqc += hc
    if (qhm[i] == "") nomem = 1; else sqm += hm
  }
  if (!shown) { print "  (CPU · 메모리 Quota 없음)"; print ""; }
  else {
    printf "  %-26s %s\n", "TOTAL", r(sqc) "/" r(sqm)
    print ""
    print "④ 판정 — Σ Quota(requests) ≤ " lbl " 이면 각 팀 몫이 보장됩니다"
    judge("CPU", sqc, capc, "m", nocpu); judge("메모리", sqm, capm, "Mi", nomem)
    if (!nocpu && !nomem && capc > 0 && capm > 0) {
      xc = sqc / capc * 100; xm = sqm / capm * 100
      printf "  먼저 막히는 자원: %s  (CPU %s%% · 메모리 %s%% 사용 예정)\n", (xc >= xm ? "CPU" : "메모리"), r(xc), r(xm)
    }
    print ""
  }
  print "⑤ LimitRange 컨테이너 max ≤ 노드 1대의 앱 몫(" r(mxc) "m / " r(mxm) "Mi)"
  if (nl == 0) print "  (max가 있는 LimitRange 없음)"
  for (i = 1; i <= nl; i++) {
    okc = (lc[i] == "" || cpu(lc[i]) <= mxc); okm = (lm[i] == "" || mem(lm[i]) <= mxm)
    printf "  %-26s CPU %-7s 메모리 %-8s %s\n", ln[i], (lc[i] == "" ? "-" : r(cpu(lc[i])) "m"), (lm[i] == "" ? "-" : r(mem(lm[i])) "Mi"),
      ((okc && okm) ? "OK" : "초과 — 노드를 늘려도 들어갈 수 없는 Pod를 허용함")
  }
}
function judge(name, q, c, u, missing) {
  if (missing) { printf "  %-6s 일부 Quota에 상한이 없음 → 합계를 정할 수 없음 (보장 불가)\n", name; return }
  if (q <= c) printf "  %-6s Σ %s%s ≤ %s%s  → 보장 (남는 몫 %s%s)\n", name, r(q), u, r(c), u, r(c - q), u
  else        printf "  %-6s Σ %s%s > %s%s  → 초과 %s%s (Quota를 다 쓰면 Pending 발생)\n", name, r(q), u, r(c), u, r(q - c), u
}
'
