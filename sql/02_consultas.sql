-- 02_consultas.sql
-- Nome: Trabalho de Integração de Dados (ADS242N01)
-- SGBD de referência: PostgreSQL 16. As consultas também executam no MySQL 8
-- quando a conexão já aponta para o banco (não há prefixo de schema).
--
-- Execute depois de sql/01_ddl_postgres.sql e de scripts/importar.py.

-- =====================================================================
-- 2.1 Consumo por produto em fevereiro/2025
--     Total vendido em quantidade e em R$ por produto.
--     O período é [2025-02-01, 2025-03-01), evitando depender de EXTRACT
--     e incluindo corretamente todo o mês de fevereiro.
-- =====================================================================
WITH vendas_fevereiro AS (
    SELECT produto_id,
           SUM(COALESCE(qtde_vendida, 0))                    AS qtde_vendida,
           SUM(COALESCE(qtde_vendida, 0) * valor_unitario)   AS valor_vendido
    FROM venda
    WHERE data_emissao >= DATE '2025-02-01'
      AND data_emissao <  DATE '2025-03-01'
    GROUP BY produto_id
)
SELECT v.produto_id,
       COALESCE(MAX(p.descricao), 'Produto sem cadastro') AS descricao,
       v.qtde_vendida,
       CAST(v.valor_vendido AS DECIMAL(14, 2)) AS valor_vendido
FROM vendas_fevereiro v
LEFT JOIN (
    SELECT produto_id, MAX(descricao) AS descricao
    FROM produtos_filial
    GROUP BY produto_id
) p ON p.produto_id = v.produto_id
GROUP BY v.produto_id, v.qtde_vendida, v.valor_vendido
ORDER BY v.produto_id;

-- Total geral de fevereiro (conferência rápida dos mesmos dados).
SELECT SUM(COALESCE(qtde_vendida, 0))                  AS qtde_total,
       CAST(SUM(COALESCE(qtde_vendida, 0) * valor_unitario) AS DECIMAL(14, 2)) AS valor_total
FROM venda
WHERE data_emissao >= DATE '2025-02-01'
  AND data_emissao <  DATE '2025-03-01';

-- =====================================================================
-- 2.2 Produtos requisitados e não recebidos
--
--     Interpretação: o pedido é a "requisição". Um produto continua pendente
--     quando (a) não há nenhuma entrada de mercadoria ligada ao pedido pela
--     ORDEM_COMPRA (e também item/produto) ou (b) a quantidade recebida é
--     menor que a quantidade pedida. O saldo é calculado pela soma real das
--     entradas, e não apenas pelo campo denormalizado qtde_entregue.
-- =====================================================================
WITH recebido_por_pedido AS (
    SELECT ordem_compra,
           item,
           produto_id,
           SUM(COALESCE(qtde_recebida, 0)) AS qtde_recebida
    FROM entradas_mercadoria
    GROUP BY ordem_compra, item, produto_id
),
produtos AS (
    SELECT produto_id, MAX(descricao) AS descricao
    FROM produtos_filial
    GROUP BY produto_id
)
SELECT pc.produto_id,
       COALESCE(MAX(pc.descricao_produto), MAX(p.descricao), 'Produto sem cadastro') AS descricao,
       SUM(COALESCE(pc.qtde_pedida, 0))                            AS qtde_pedida,
       COALESCE(SUM(r.qtde_recebida), 0)                           AS qtde_recebida,
       SUM(GREATEST(COALESCE(pc.qtde_pedida, 0) - COALESCE(r.qtde_recebida, 0), 0)) AS saldo_pendente,
       SUM(CASE WHEN r.ordem_compra IS NULL THEN 1 ELSE 0 END)     AS linhas_sem_entrada
FROM pedido_compra pc
LEFT JOIN recebido_por_pedido r
       ON r.ordem_compra = pc.ordem_compra
      AND r.item         = pc.item
      AND r.produto_id   = pc.produto_id
LEFT JOIN produtos p ON p.produto_id = pc.produto_id
GROUP BY pc.produto_id
HAVING SUM(GREATEST(COALESCE(pc.qtde_pedida, 0) - COALESCE(r.qtde_recebida, 0), 0)) > 0
    OR SUM(CASE WHEN r.ordem_compra IS NULL THEN 1 ELSE 0 END) > 0
ORDER BY saldo_pendente DESC, pc.produto_id;

-- Variante detalhada (uma linha por pedido pendente), útil para a conferência
-- linha a linha com o cliente.
WITH recebido_por_pedido AS (
    SELECT ordem_compra,
           item,
           produto_id,
           SUM(COALESCE(qtde_recebida, 0)) AS qtde_recebida
    FROM entradas_mercadoria
    GROUP BY ordem_compra, item, produto_id
)
SELECT pc.pedido_id,
       pc.ordem_compra,
       pc.produto_id,
       pc.descricao_produto,
       pc.qtde_pedida,
       COALESCE(r.qtde_recebida, 0)                                  AS qtde_recebida,
       COALESCE(pc.qtde_pedida, 0) - COALESCE(r.qtde_recebida, 0)    AS saldo_pendente
FROM pedido_compra pc
LEFT JOIN recebido_por_pedido r
       ON r.ordem_compra = pc.ordem_compra
      AND r.item         = pc.item
      AND r.produto_id   = pc.produto_id
WHERE COALESCE(pc.qtde_pedida, 0) > COALESCE(r.qtde_recebida, 0)
ORDER BY pc.pedido_id, pc.item;
