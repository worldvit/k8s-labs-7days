"""SkillBoost 쇼핑몰 API (Kubernetes 7일 과정 실습용)

환경변수
  APP_VERSION    이미지 빌드 시 고정 (v1, v2)
  APP_TITLE      화면 제목 (ConfigMap으로 주입, 3장)
  DB_MODE        memory | mysql (6장에서 mysql로 전환)
  DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD   (DB_PASSWORD는 Secret, 3장)
  STARTUP_DELAY  기동 후 준비까지 걸리는 초 (startupProbe 실습, 7장)
"""
import os
import socket
import threading
import time

from flask import Flask, jsonify, request

APP_VERSION = os.environ.get("APP_VERSION", "v1")
APP_TITLE = os.environ.get("APP_TITLE", "SkillBoost Shop")
DB_MODE = os.environ.get("DB_MODE", "memory").lower()
DB_HOST = os.environ.get("DB_HOST", "shop-db")
DB_PORT = int(os.environ.get("DB_PORT", "3306"))
DB_NAME = os.environ.get("DB_NAME", "shop")
DB_USER = os.environ.get("DB_USER", "shop")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "")
STARTUP_DELAY = float(os.environ.get("STARTUP_DELAY", "0"))

STARTED_AT = time.monotonic()
HOSTNAME = socket.gethostname()

MEMORY_PRODUCTS = [
    {"id": 1, "name": "Kubernetes 머그컵", "price": 12000, "stock": 30},
    {"id": 2, "name": "Pod 스티커 세트", "price": 3000, "stock": 120},
    {"id": 3, "name": "Helm 후드티", "price": 45000, "stock": 12},
]

_hang = threading.Event()   # /api/chaos/hang 이후 /healthz가 응답하지 않음
_ballast = []               # /api/chaos/memory 가 잡아 두는 메모리

app = Flask(__name__)
app.json.ensure_ascii = False  # 한글을 그대로 출력 (curl 확인용)


def started() -> bool:
    return time.monotonic() - STARTED_AT >= STARTUP_DELAY


def db_connect(timeout=2):
    import pymysql
    return pymysql.connect(host=DB_HOST, port=DB_PORT, user=DB_USER, password=DB_PASSWORD,
                           database=DB_NAME, connect_timeout=timeout, read_timeout=timeout,
                           cursorclass=pymysql.cursors.DictCursor)


def load_products():
    if DB_MODE != "mysql":
        return MEMORY_PRODUCTS, "memory"
    conn = db_connect()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT id, name, price, stock FROM products ORDER BY id")
            return list(cur.fetchall()), "mysql"
    finally:
        conn.close()


def decorate(items):
    """v2 기능: 재고가 적은 상품에 badge 표시 (롤링 업데이트 실습에서 v1과 구분)"""
    if APP_VERSION == "v1":
        return items
    out = []
    for p in items:
        q = dict(p)
        q["badge"] = "품절 임박" if int(q["stock"]) < 20 else ""
        out.append(q)
    return out


@app.get("/api/products")
def products():
    try:
        items, source = load_products()
    except Exception as e:  # DB 연결 실패는 503으로 알림
        return jsonify(error="database unavailable", detail=str(e), pod=HOSTNAME), 503
    return jsonify(title=APP_TITLE, version=APP_VERSION, source=source, pod=HOSTNAME, items=decorate(items))


@app.get("/api/version")
def version():
    return jsonify(version=APP_VERSION, pod=HOSTNAME, db_mode=DB_MODE)


@app.get("/healthz")
def healthz():
    """liveness: 프로세스가 응답 가능한가"""
    if _hang.is_set():
        time.sleep(3600)
    if not started():
        return jsonify(status="starting"), 503
    return jsonify(status="ok")


@app.get("/readyz")
def readyz():
    """readiness: 트래픽을 받아도 되는가 (mysql 모드면 DB 연결까지 확인)"""
    if not started():
        return jsonify(status="starting"), 503
    if DB_MODE == "mysql":
        try:
            conn = db_connect()
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
            conn.close()
        except Exception as e:
            return jsonify(status="db-unavailable", detail=str(e)), 503
    return jsonify(status="ready", db_mode=DB_MODE)


@app.post("/api/chaos/cpu")
def chaos_cpu():
    """HPA 실습(8장): seconds 동안 CPU 1코어 사용"""
    seconds = min(float(request.args.get("seconds", "30")), 300)

    def burn():
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            pass
    threading.Thread(target=burn, daemon=True).start()
    return jsonify(action="cpu", seconds=seconds, pod=HOSTNAME)


@app.post("/api/chaos/memory")
def chaos_memory():
    """OOMKilled 실습(8장): mb 만큼 메모리 추가 점유 (재시작 전까지 유지)"""
    mb = min(int(request.args.get("mb", "100")), 2048)
    _ballast.append(bytearray(mb * 1024 * 1024))
    return jsonify(action="memory", added_mb=mb, total_mb=sum(len(b) for b in _ballast) // (1024 * 1024), pod=HOSTNAME)


@app.post("/api/chaos/hang")
def chaos_hang():
    """liveness 실습(7장): 이후 /healthz가 응답하지 않음 → kubelet이 컨테이너 재시작"""
    _hang.set()
    return jsonify(action="hang", pod=HOSTNAME)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
