-- SkillBoost 쇼핑몰 상품 데이터 (5장 shop-db-seed Job에서 사용)
CREATE TABLE IF NOT EXISTS products (
  id    INT PRIMARY KEY,
  name  VARCHAR(100) NOT NULL,
  price INT NOT NULL,
  stock INT NOT NULL
) DEFAULT CHARSET=utf8mb4;

INSERT INTO products (id, name, price, stock) VALUES
  (1, 'Kubernetes 머그컵', 12000, 30),
  (2, 'Pod 스티커 세트', 3000, 120),
  (3, 'Helm 후드티', 45000, 12),
  (4, 'etcd 키링', 5000, 8),
  (5, 'kubectl 치트시트 포스터', 9000, 55)
ON DUPLICATE KEY UPDATE name=VALUES(name), price=VALUES(price), stock=VALUES(stock);
