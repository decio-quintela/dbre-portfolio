-- Criar tabela de exemplo (rode no psql do container)
docker exec -it pg-lab psql -U postgres -c "
CREATE TABLE IF NOT EXISTS vendas (
  id          SERIAL PRIMARY KEY,
  vendedor    TEXT,
  mes         DATE,
  valor       NUMERIC
);

INSERT INTO vendas (vendedor, mes, valor) VALUES
  ('Ana',    '2025-01-01', 12000),
  ('Ana',    '2025-02-01',  9500),
  ('Ana',    '2025-03-01', 14000),
  ('Carlos', '2025-01-01',  8000),
  ('Carlos', '2025-02-01', 11000),
  ('Carlos', '2025-03-01',  7500),
  ('Beatriz','2025-01-01', 15000),
  ('Beatriz','2025-02-01', 13000),
  ('Beatriz','2025-03-01', 16000);
"

---

-- 1. WINDOW FUNCTION: ranking por mês
SELECT vendedor, mes, valor,
  RANK() OVER (PARTITION BY mes ORDER BY valor DESC) AS rank_mes,
  LAG(valor) OVER (PARTITION BY vendedor ORDER BY mes) AS mes_anterior,
  valor - LAG(valor) OVER (PARTITION BY vendedor ORDER BY mes) AS variacao
FROM vendas;

-- 2. CTE: top vendedor por mês
WITH ranking AS (
  SELECT vendedor, mes, valor,
    RANK() OVER (PARTITION BY mes ORDER BY valor DESC) AS pos
  FROM vendas
)
SELECT vendedor, mes, valor
FROM ranking
WHERE pos = 1
ORDER BY mes;

-- 3. SUBQUERY: vendedores acima da média geral
SELECT vendedor, AVG(valor) AS media_pessoal
FROM vendas
GROUP BY vendedor
HAVING AVG(valor) > (
  SELECT AVG(valor) FROM vendas
);