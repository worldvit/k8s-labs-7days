# SkillBoost 쇼핑몰 앱 (Kubernetes 7일 과정)

7일 누적 실습에서 배포하는 애플리케이션 소스입니다.

| 구성요소 | 경로 | 이미지 | 처음 사용 |
|---|---|---|---|
| shop-api | `app/shop-api` | `ghcr.io/worldvit/skillboost-api:v1`, `:v2` | 3장 Lab03 |
| shop-web | `app/shop-web` | `nginx` + ConfigMap(index.html · default.conf) | 3장 Lab03 (화면) · 6장 (프록시) |
| shop-db 데이터 | `app/shop-db/schema-seed.sql` | `mysql:8.4` + seed Job | 5장 Lab05-B |

## shop-api

| 엔드포인트 | 용도 | 사용 장 |
|---|---|---|
| `GET /api/products` | 상품 목록 (title · version · source · pod · items) | 3 · 6장 |
| `GET /api/version` | 버전 · 응답 Pod 이름 · DB 모드 | 5 · 6장 |
| `GET /healthz` | liveness (기동 전 503, hang 후 무응답) | 7장 |
| `GET /readyz` | readiness (mysql 모드면 DB 연결 확인, 실패 시 503) | 7장 |
| `POST /api/chaos/cpu?seconds=N` | N초 동안 CPU 1코어 사용 (최대 300) | 8장 HPA |
| `POST /api/chaos/memory?mb=N` | N MB 메모리 추가 점유 (최대 2048) | 8장 OOMKilled |
| `POST /api/chaos/hang` | 이후 /healthz 무응답 | 7장 liveness |

| 환경변수 | 기본값 | 설명 |
|---|---|---|
| `APP_VERSION` | 이미지에 고정 | `v1` · `v2` (v2는 재고 20 미만 상품에 badge) |
| `APP_TITLE` | `SkillBoost Shop` | 화면 제목 (ConfigMap) |
| `DB_MODE` | `memory` | `memory` · `mysql` |
| `DB_HOST` · `DB_PORT` · `DB_NAME` · `DB_USER` | `shop-db` · `3306` · `shop` · `shop` | mysql 연결 정보 |
| `DB_PASSWORD` | (없음) | Secret으로 주입 |
| `STARTUP_DELAY` | `0` | 기동 후 준비까지 초 (startupProbe) |

컨테이너 포트는 `5000`, 실행 사용자는 UID `10001`입니다.

## 이미지 게시 (강사)

1. 이 폴더를 저장소 루트의 `app/`에, `.github/workflows/shop-api-image.yml`을 루트의 `.github/workflows/`에 둡니다.
2. `main`에 push하거나 Actions 탭에서 **shop-api image** 워크플로를 수동 실행하면 `v1`, `v2` 태그가 GHCR에 게시됩니다.
3. **처음 게시 후 한 번**, GitHub 프로필 → Packages → `skillboost-api` → Package settings → **Change visibility → Public**으로 변경합니다. 비공개 상태면 노드에서 `ImagePullBackOff`가 발생합니다.
4. 확인: `crictl pull ghcr.io/worldvit/skillboost-api:v1` (노드) 또는 브라우저에서 패키지 페이지 확인.

## 로컬 실행 (선택)

```bash
cd app/shop-api
pip install -r requirements.txt
APP_VERSION=v2 python app.py
curl -s localhost:5000/api/products
```
