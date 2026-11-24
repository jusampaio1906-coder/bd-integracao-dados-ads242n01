-- 03_transformacoes.sql
-- Nome: Trabalho de Integração de Dados (ADS242N01)
-- SGBD de referência: PostgreSQL 16.
--
-- A trigger do item 4 é escrita para PostgreSQL. No MySQL o DDL correspondente
-- está em sql/01_ddl_mysql.sql; o equivalente da trigger está comentado no fim.

-- =====================================================================
-- 1. Concatenar produto_id e descricao_produto no formato
--    "12345 - Detergente" (usando apenas onde houver descrição)
-- =====================================================================

-- 1.1 Pedidos de compra
SELECT pc.pedido_id,
       pc.item,
       CASE
           WHEN pc.descricao_produto IS NOT NULL
            AND BTRIM(pc.descricao_produto) <> ''
           THEN pc.produto_id || ' - ' || BTRIM(pc.descricao_produto)
           ELSE pc.produto_id
       END AS produto,
       pc.qtde_pedida
FROM public.pedido_compra pc
ORDER BY pc.pedido_id, pc.item;

-- 1.2 Vendas (a descrição vem do cadastro de produtos; P21..P28 não têm cadastro)
SELECT v.venda_id,
       v.data_emissao,
       CASE
           WHEN p.descricao IS NOT NULL AND BTRIM(p.descricao) <> ''
           THEN v.produto_id || ' - ' || BTRIM(p.descricao)
           ELSE v.produto_id
       END AS produto,
       v.qtde_vendida,
       v.valor_unitario
FROM public.venda v
LEFT JOIN (
    SELECT produto_id, MAX(descricao) AS descricao
    FROM public.produtos_filial
    GROUP BY produto_id
) p ON p.produto_id = v.produto_id
ORDER BY v.data_emissao, v.venda_id;

-- 1.3 Cadastro de produtos
SELECT pf.filial_id,
       pf.produto_id || ' - ' || pf.descricao AS produto,
       pf.estoque,
       pf.preco_venda
FROM public.produtos_filial pf
ORDER BY pf.filial_id, pf.produto_id;

-- =====================================================================
-- 2. Datas no formato DD/MM/YYYY
-- =====================================================================
SELECT v.venda_id,
       TO_CHAR(v.data_emissao, 'DD/MM/YYYY') AS data_emissao,
       v.produto_id,
       v.qtde_vendida
FROM public.venda v
ORDER BY v.data_emissao, v.venda_id;

SELECT pc.pedido_id,
       TO_CHAR(pc.data_pedido, 'DD/MM/YYYY') AS data_pedido,
       TO_CHAR(pc.data_entrega, 'DD/MM/YYYY') AS data_entrega,
       pc.produto_id,
       pc.qtde_pedida
FROM public.pedido_compra pc
ORDER BY pc.pedido_id, pc.item;

SELECT em.nro_nfe,
       TO_CHAR(em.data_entrada, 'DD/MM/YYYY') AS data_entrada,
       em.ordem_compra,
       em.produto_id,
       em.qtde_recebida
FROM public.entradas_mercadoria em
ORDER BY em.data_entrada, em.nro_nfe;

-- =====================================================================
-- 3. Produtos requisitados mais de 10 vezes no período
--
--    INTERPRETAÇÃO ADOTADA: "mais de 10 vezes" foi lido como "quantidade total
--    requisitada maior que 10 unidades" no período de 01/01/2025 a 31/03/2025
--    (todo o período da planilha). O enunciado pede a coluna "Qtde Requisitada"
--    no exemplo, com valor 15 para um único produto, o que indica soma de
--    quantidade, e não contagem de linhas de pedido.
--
--    A alternativa literal (contar quantas linhas de pedido o produto teve)
--    está logo abaixo, comentada; com esta base ela retorna 0 linhas, pois
--    nenhum produto aparece em mais de 10 pedidos.
-- =====================================================================
WITH periodo AS (
    SELECT DATE '2025-01-01' AS inicio,
           DATE '2025-03-31' AS fim
),
requisicoes AS (
    SELECT pc.produto_id,
           MAX(pc.descricao_produto)           AS descricao,
           SUM(COALESCE(pc.qtde_pedida, 0))    AS qtde_requisitada,
           COUNT(*)                            AS num_requisicoes,
           MIN(pc.data_pedido)                 AS primeira_solicitacao
    FROM public.pedido_compra pc
    CROSS JOIN periodo p
    WHERE pc.data_pedido BETWEEN p.inicio AND p.fim
    GROUP BY pc.produto_id
)
SELECT r.produto_id || ' - ' || COALESCE(r.descricao, '') AS produto,
       r.qtde_requisitada,
       TO_CHAR(r.primeira_solicitacao, 'DD/MM/YYYY') AS data_solicitacao,
       r.num_requisicoes
FROM requisicoes r
WHERE r.qtde_requisitada > 10
ORDER BY r.qtde_requisitada DESC, r.produto_id;

-- Interpretação alternativa: produtos com MAIS DE 10 LINHAS de pedido no período.
-- Basta trocar o WHERE anterior por: HAVING COUNT(*) > 10 (ou usar a consulta abaixo).
/*
WITH periodo AS (
    SELECT DATE '2025-01-01' AS inicio,
           DATE '2025-03-31' AS fim
)
SELECT pc.produto_id,
       COUNT(*) AS num_requisicoes,
       SUM(COALESCE(pc.qtde_pedida, 0)) AS qtde_requisitada
FROM public.pedido_compra pc
CROSS JOIN periodo p
WHERE pc.data_pedido BETWEEN p.inicio AND p.fim
GROUP BY pc.produto_id
HAVING COUNT(*) > 10
ORDER BY num_requisicoes DESC;
*/

-- =====================================================================
-- 4. Trigger: gera automaticamente um idfornecedor numérico na tabela de
--    produtos, relacionado à tabela fornecedor.
--
--    Quando um produto é inserido/atualizado sem idfornecedor, a função cria
--    um novo fornecedor (id gerado pela identidade, a partir de 21), grava esse
--    id em NEW.idfornecedor e devolve o registro. A FK existente garante o
--    relacionamento. Se o id informado não existir, a própria FK rejeita.
-- =====================================================================
CREATE OR REPLACE FUNCTION public.fn_produto_define_fornecedor()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_idfornecedor integer;
BEGIN
    IF NEW.idfornecedor IS NULL THEN
        INSERT INTO public.fornecedor (razao_social)
        VALUES ('Fornecedor gerado automaticamente')
        RETURNING idfornecedor INTO v_idfornecedor;

        NEW.idfornecedor := v_idfornecedor;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_produto_define_fornecedor ON public.produtos_filial;

CREATE TRIGGER trg_produto_define_fornecedor
BEFORE INSERT OR UPDATE OF idfornecedor ON public.produtos_filial
FOR EACH ROW
EXECUTE FUNCTION public.fn_produto_define_fornecedor();

-- Teste da trigger (execute manualmente; o ROLLBACK não altera a base):
/*
BEGIN;
INSERT INTO public.produtos_filial (filial_id, produto_id, descricao)
VALUES (99, 'TESTE-TRIGGER', 'Produto de teste da trigger')
RETURNING produto_id, idfornecedor;

SELECT idfornecedor, razao_social
FROM public.fornecedor
WHERE idfornecedor >= 21;
ROLLBACK;
*/

-- Equivalente MySQL (opcional; execute no MySQL com DELIMITER):
/*
DELIMITER $$
CREATE TRIGGER trg_produto_define_fornecedor
BEFORE INSERT ON produtos_filial
FOR EACH ROW
BEGIN
    IF NEW.idfornecedor IS NULL THEN
        INSERT INTO fornecedor (razao_social)
        VALUES ('Fornecedor gerado automaticamente');
        SET NEW.idfornecedor = LAST_INSERT_ID();
    END IF;
END$$
DELIMITER ;
*/
