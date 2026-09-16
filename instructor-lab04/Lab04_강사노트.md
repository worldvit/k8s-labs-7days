# Lab04 강사 노트 (학생 비공개)

## 배포 구분

| 파일                                                                                   | 학생 저장소 반영 시점                                      |
| -------------------------------------------------------------------------------------- | ---------------------------------------------------------- |
| `lab04-node/verify.sh`, `lab04-node/verify-advanced.sh`, `verify-all.sh` (day3am 추가) | 3일차 수업 전                                              |
| `catchup.sh`, `catchup/day2/` (Lab03 강사노트 참고)                                    | 3일차 수업 전                                              |
| catchup day3                                                                           | Lab05-A와 함께 제작 (3일차 종료 상태 = Deployment 전환 후) |

## 시간 운영 (4교시)

| 교시 | 이론                                | Lab04                       |
| ---- | ----------------------------------- | --------------------------- |
| 1    | 4-1 노드 상태 · cordon · drain      | 사전 준비 · 태스크 1        |
| 2    | 4-2 label · nodeSelector · affinity | 태스크 2                    |
| 3    | 4-3 taint · toleration              | 태스크 3 · 4                |
| 4    | 심화 안내                           | 태스크 5 채점 · 지시형 심화 |

## 설계상 의도된 결과 (교육생 질문 대비)

- **Lab04 종료 시 shop-api · shop-web이 모두 없음:** shop-api는 `cap-node2`에 있었다면 태스크 3.2 NoExecute로, `cap-node1`에 있었다면 태스크 4 drain으로 삭제됩니다. 어느 경우든 결과가 같아지도록 설계했습니다. 오후 Lab05-A가 Deployment로 복구합니다.
- **CoreDNS가 cap-master로 이동:** `cap-node1` drain 중 `cap-node2`는 taint로 막혀 있고, CoreDNS는 control-plane taint를 허용하기 때문입니다. uncordon 후에도 자동으로 돌아오지 않지만 동작에는 문제가 없습니다.
- **drain 중 일부 시스템 Pod Pending:** 갈 수 있는 노드가 없는 Deployment Pod(Calico 부가 구성요소 등)는 uncordon 후 배치됩니다.

## 이후 장에 대한 설계 메모 (확인 필요)

- `cap-node2` 전용화로 **앱 Pod는 모두 `cap-node1`에 배치**됩니다. 8장 HPA 최대 replicas와 `cap-node1`의 Allocatable(2 vCPU)을 함께 계산해야 합니다.
- 12장 ALB 실습의 "노드 drain 시 대상 unhealthy · 우회 관찰"은 앱 Pod가 `cap-node1`에만 있으면 drain 동안 서비스가 중단됩니다. 12장 제작 시 관찰 방식(예: `cap-node1` drain 대신 Gateway 데이터플레인 Pod 위치 기준)을 재설계합니다.
- 5장 DaemonSet(shop-log-agent)은 `dedicated=db` toleration을 넣어야 `cap-node2`에도 배치됩니다.

## 자주 막히는 지점

| 지점                                      | 원인                                       | 대응                                          |
| ----------------------------------------- | ------------------------------------------ | --------------------------------------------- |
| 태스크 1.2 이후 모든 Pod Pending          | `cap-node2` uncordon 누락                  | `kubectl get nodes`로 SchedulingDisabled 확인 |
| 태스크 2.2 `sed` 결과 이상                | `~/shop/shop-web.yaml`이 없거나 두 번 실행 | 파일 확인, catchup day2 매니페스트 복사       |
| 태스크 3.2 이후 cap-node2 Pod 계속 사라짐 | maintenance taint 미제거                   | verify.sh 4번 항목으로 확인                   |

## 실측 확인이 필요한 항목 (첫 운영 전)

| 항목                                                             | 문서 위치              |
| ---------------------------------------------------------------- | ---------------------- |
| `kubectl drain --dry-run=client` 출력 형식 (오류 목록 표시 여부) | 태스크 1.3             |
| FailedScheduling 메시지의 노드별 사유 순서 · 문구                | 태스크 1.2 · 2.2 · 3.1 |
| NoExecute 축출 시각 (30초 + 종료 유예)                           | 태스크 3.2             |
| drain 출력의 Warning · evicting 문구                             | 태스크 4               |
| drain 중 Pending이 되는 Calico 부가 구성요소 여부                | 태스크 4               |
| taint 중복 오류 문구                                             | 문제 해결              |
