-- 04_validacao.sql
-- Nome: Trabalho de Integração de Dados (ADS242N01)
-- Consultas de apoio ao roteiro de validação (docs/parte4_validacao.md).
-- SGBD de referência: PostgreSQL 16.
--
-- Convenção: [Vn] é o identificador citado na documentação da Parte 4.
-- As consultas de erro são somente de leitura; nenhuma corrige os dados, pois
-- as divergências precisam ser confirmadas com o cliente.

-- =====================================================================
-- [V1] Reconciliação de fevereiro/2025: totais e volume
-- =====================================================================
SELECT COUNT(*)                                                     AS linhas_venda,
       COUNT(DISTINCT produto_id)                                   AS produtos_distintos,
       SUM(COALESCE(qtde_vendida, 0))                               AS qtde_vendida,
       CAST(SUM(COALESCE(qtde_vendida, 0) * valor_unitario) AS DECIMAL(14, 2)) AS valor_vendido
FROM public.venda
WHERE data_emissao >= DATE '2025-02-01'
  AND data_emissao <  DATE '2025-03-01';

-- =====================================================================
-- [V2] Vendas de fevereiro por produto (quantidade e R$)
-- =====================================================================
WITH vendas_fevereiro AS (
    SELECT produto_id,
           SUM(COALESCE(qtde_vendida, 0))                  AS qtde_vendida,
           SUM(COALESCE(qtde_vendida, 0) * valor_unitario) AS valor_vendido
    FROM public.venda
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
    FROM public.produtos_filial
    GROUP BY produto_id
) p ON p.produto_id = v.produto_id
GROUP BY v.produto_id, v.qtde_vendida, v.valor_vendido
ORDER BY v.produto_id;

-- =====================================================================
-- [V3] ERRO E01: vendas de produtos sem cadastro em produtos_filial
--      Resultado esperado: P21..P28 (8 produtos, 13 linhas de venda).
-- =====================================================================
SELECT v.produto_id,
       COUNT(*)                                AS linhas_venda,
       SUM(COALESCE(v.qtde_vendida, 0))        AS qtde_vendida,
       CAST(SUM(COALESCE(v.qtde_vendida, 0) * v.valor_unitario) AS DECIMAL(14, 2)) AS valor_vendido,
       MIN(v.data_emissao)                     AS primeira_venda,
       MAX(v.data_emissao)                     AS ultima_venda
FROM public.venda v
WHERE NOT EXISTS (
    SELECT 1 FROM public.produtos_filial p WHERE p.produto_id = v.produto_id
)
GROUP BY v.produto_id
ORDER BY v.produto_id;

-- Mesmo erro restrito a fevereiro/2025 (produtos P22..P27).
SELECT v.produto_id, v.venda_id, v.data_emissao, v.qtde_vendida, v.valor_unitario
FROM public.venda v
WHERE v.data_emissao >= DATE '2025-02-01'
  AND v.data_emissao <  DATE '2025-03-01'
  AND NOT EXISTS (
      SELECT 1 FROM public.produtos_filial p WHERE p.produto_id = v.produto_id
  )
ORDER BY v.data_emissao, v.venda_id;

-- =====================================================================
-- [V4] ERRO E02: data de entrega anterior à data do pedido
--      Resultado esperado: 20 linhas.
-- =====================================================================
SELECT pc.pedido_id,
       pc.produto_id,
       pc.data_pedido,
       pc.data_entrega,
       (pc.data_entrega - pc.data_pedido) AS dias_de_diferenca
FROM public.pedido_compra pc
WHERE pc.data_entrega < pc.data_pedido
ORDER BY pc.pedido_id, pc.item;

-- =====================================================================
-- [V5] ERRO E03: entradas de mercadoria sem pedido de compra
--      (não existe pedido com a mesma ordem_compra)
--      Resultado esperado: ordens 19 e 20.
-- =====================================================================
SELECT em.data_entrada,
       em.nro_nfe,
       em.ordem_compra,
       em.item,
       em.produto_id,
       em.qtde_recebida
FROM public.entradas_mercadoria em
WHERE NOT EXISTS (
    SELECT 1 FROM public.pedido_compra pc WHERE pc.ordem_compra = em.ordem_compra
)
ORDER BY em.ordem_compra, em.item;

-- =====================================================================
-- [V6] ERRO E04: pedidos com ordem_compra = 0 (sem vínculo com entrada)
--      e chaves repetidas nesse grupo.
-- =====================================================================
SELECT pc.pedido_id, pc.item, pc.produto_id, pc.qtde_pedida, pc.qtde_entregue
FROM public.pedido_compra pc
WHERE pc.ordem_compra = 0
ORDER BY pc.pedido_id, pc.item;

SELECT ordem_compra, item, produto_id, COUNT(*) AS repeticoes
FROM public.pedido_compra
WHERE ordem_compra = 0
GROUP BY ordem_compra, item, produto_id
HAVING COUNT(*) > 1
ORDER BY produto_id;

-- =====================================================================
-- [V7] ERRO E05: divergência entre qtde_entregue do pedido e a soma
--      efetivamente recebida em entradas_mercadoria (por ordem/item/produto).
--      Resultado esperado: 18 linhas.
-- =====================================================================
WITH recebido_por_pedido AS (
    SELECT ordem_compra,
           item,
           produto_id,
           SUM(COALESCE(qtde_recebida, 0)) AS qtde_recebida
    FROM public.entradas_mercadoria
    GROUP BY ordem_compra, item, produto_id
)
SELECT pc.pedido_id,
       pc.ordem_compra,
       pc.produto_id,
       pc.qtde_pedida,
       pc.qtde_entregue,
       COALESCE(r.qtde_recebida, 0) AS qtde_recebida_nas_entradas,
       COALESCE(pc.qtde_entregue, 0) - COALESCE(r.qtde_recebida, 0) AS diferenca
FROM public.pedido_compra pc
LEFT JOIN recebido_por_pedido r
       ON r.ordem_compra = pc.ordem_compra
      AND r.item         = pc.item
      AND r.produto_id   = pc.produto_id
WHERE pc.ordem_compra <> 0
  AND ABS(COALESCE(pc.qtde_entregue, 0) - COALESCE(r.qtde_recebida, 0)) > 0.001
ORDER BY pc.pedido_id, pc.item;

-- =====================================================================
-- [V8] ERRO E06: quantidade recebida maior que a quantidade pedida
--      Resultado esperado: 7 linhas.
-- =====================================================================
WITH recebido_por_pedido AS (
    SELECT ordem_compra,
           item,
           produto_id,
           SUM(COALESCE(qtde_recebida, 0)) AS qtde_recebida
    FROM public.entradas_mercadoria
    GROUP BY ordem_compra, item, produto_id
)
SELECT pc.pedido_id,
       pc.ordem_compra,
       pc.produto_id,
       pc.qtde_pedida,
       r.qtde_recebida,
       r.qtde_recebida - COALESCE(pc.qtde_pedida, 0) AS excedente
FROM public.pedido_compra pc
JOIN recebido_por_pedido r
  ON r.ordem_compra = pc.ordem_compra
 AND r.item         = pc.item
 AND r.produto_id   = pc.produto_id
WHERE pc.ordem_compra <> 0
  AND r.qtde_recebida > COALESCE(pc.qtde_pedida, 0)
ORDER BY pc.pedido_id, pc.item;

-- =====================================================================
-- [V9] ERRO E07: pedidos sem nenhuma entrada vinculada por
--      ordem_compra/item/produto. Resultado esperado: 11 linhas (os de ordem 0).
-- =====================================================================
SELECT pc.pedido_id,
       pc.ordem_compra,
       pc.produto_id,
       pc.qtde_pedida,
       pc.data_pedido,
       pc.data_entrega
FROM public.pedido_compra pc
WHERE NOT EXISTS (
    SELECT 1
    FROM public.entradas_mercadoria em
    WHERE em.ordem_compra = pc.ordem_compra
      AND em.item         = pc.item
      AND em.produto_id   = pc.produto_id
)
ORDER BY pc.pedido_id, pc.item;

-- =====================================================================
-- [V10] ERRO E08: entrada registrada antes da data do pedido
--       Resultado esperado: 9 linhas.
-- =====================================================================
SELECT pc.pedido_id,
       pc.ordem_compra,
       pc.produto_id,
       pc.data_pedido,
       em.nro_nfe,
       em.data_entrada
FROM public.pedido_compra pc
JOIN public.entradas_mercadoria em
  ON em.ordem_compra = pc.ordem_compra
 AND em.item         = pc.item
 AND em.produto_id   = pc.produto_id
WHERE em.data_entrada < pc.data_pedido
ORDER BY pc.pedido_id, pc.item;

-- =====================================================================
-- [V11] Checagens de qualidade que devem retornar zero ocorrências
-- =====================================================================
SELECT 'venda com quantidade nula/negativa' AS problema, COUNT(*) AS ocorrencias
FROM public.venda
WHERE qtde_vendida IS NULL OR qtde_vendida <= 0
UNION ALL
SELECT 'venda com valor unitário nulo/negativo', COUNT(*)
FROM public.venda
WHERE valor_unitario IS NULL OR valor_unitario <= 0
UNION ALL
SELECT 'venda sem data de emissão', COUNT(*)
FROM public.venda
WHERE data_emissao IS NULL
UNION ALL
SELECT 'pedido sem fornecedor válido', COUNT(*)
FROM public.pedido_compra pc
WHERE pc.fornecedor_id IS NULL
   OR NOT EXISTS (SELECT 1 FROM public.fornecedor f WHERE f.idfornecedor = pc.fornecedor_id)
UNION ALL
SELECT 'produto com fornecedor inexistente', COUNT(*)
FROM public.produtos_filial p
WHERE p.idfornecedor IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.fornecedor f WHERE f.idfornecedor = p.idfornecedor)
UNION ALL
SELECT 'entrada de produto sem cadastro', COUNT(*)
FROM public.entradas_mercadoria em
WHERE NOT EXISTS (SELECT 1 FROM public.produtos_filial p WHERE p.produto_id = em.produto_id)
UNION ALL
SELECT 'entrada sem data de entrada', COUNT(*)
FROM public.entradas_mercadoria
WHERE data_entrada IS NULL;

-- =====================================================================
-- [V12] Contagens de reconciliação da carga
-- =====================================================================
SELECT 'fornecedor' AS tabela, COUNT(*) AS linhas FROM public.fornecedor
UNION ALL SELECT 'produtos_filial', COUNT(*) FROM public.produtos_filial
UNION ALL SELECT 'pedido_compra', COUNT(*) FROM public.pedido_compra
UNION ALL SELECT 'entradas_mercadoria', COUNT(*) FROM public.entradas_mercadoria
UNION ALL SELECT 'venda', COUNT(*) FROM public.venda;

-- =====================================================================
-- [V13] Distribuição das vendas por mês (delimita o escopo de fevereiro)
-- =====================================================================
SELECT TO_CHAR(data_emissao, 'YYYY-MM') AS mes,
       COUNT(*)                         AS linhas,
       SUM(COALESCE(qtde_vendida, 0))   AS qtde_vendida,
       CAST(SUM(COALESCE(qtde_vendida, 0) * valor_unitario) AS DECIMAL(14, 2)) AS valor_vendido
FROM public.venda
GROUP BY TO_CHAR(data_emissao, 'YYYY-MM')
ORDER BY mes;

-- =====================================================================
-- [V14] Pendências de fevereiro/2025 para a reunião (detalhe por pedido)
-- =====================================================================
WITH recebido_por_pedido AS (
    SELECT ordem_compra,
           item,
           produto_id,
           SUM(COALESCE(qtde_recebida, 0)) AS qtde_recebida
    FROM public.entradas_mercadoria
    GROUP BY ordem_compra, item, produto_id
)
SELECT pc.pedido_id,
       pc.data_pedido,
       pc.ordem_compra,
       pc.produto_id,
       pc.qtde_pedida,
       COALESCE(r.qtde_recebida, 0) AS qtde_recebida,
       GREATEST(COALESCE(pc.qtde_pedida, 0) - COALESCE(r.qtde_recebida, 0), 0) AS saldo_pendente
FROM public.pedido_compra pc
LEFT JOIN recebido_por_pedido r
       ON r.ordem_compra = pc.ordem_compra
      AND r.item         = pc.item
      AND r.produto_id   = pc.produto_id
WHERE pc.data_pedido >= DATE '2025-02-01'
  AND pc.data_pedido <  DATE '2025-03-01'
  AND GREATEST(COALESCE(pc.qtde_pedida, 0) - COALESCE(r.qtde_recebida, 0), 0) > 0
ORDER BY pc.pedido_id, pc.item;

-- =====================================================================
-- [V15] ERRO E09: vendas em filiais sem cadastro de produto naquela filial.
--       O cadastro de produtos só existe para a filial 1; as filiais 2 e 3
--       têm vendas de P27/P28 sem produto cadastrado na própria filial.
--       Resultado esperado: 4 linhas (2 produtos).
-- =====================================================================
SELECT v.filial_id,
       v.produto_id,
       COUNT(*)                          AS linhas_venda,
       SUM(COALESCE(v.qtde_vendida, 0))  AS qtde_vendida
FROM public.venda v
WHERE v.filial_id <> 1
  AND NOT EXISTS (
      SELECT 1
      FROM public.produtos_filial p
      WHERE p.filial_id = v.filial_id
        AND p.produto_id = v.produto_id
  )
GROUP BY v.filial_id, v.produto_id
ORDER BY v.filial_id, v.produto_id;

-- Cobertura do cadastro por filial (evidencia que só a filial 1 tem produtos).
SELECT filial_id, COUNT(*) AS produtos_cadastrados
FROM public.produtos_filial
GROUP BY filial_id
ORDER BY filial_id;
