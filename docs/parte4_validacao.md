# Parte 4: Roteiro de validação com o cliente (fevereiro/2025)

## Contexto da reunião

- **Base validada:** dados carregados de `dados/base_teste.xlsx` em PostgreSQL 16
  (a carga também foi executada em MySQL 8.0.46; ver `docs/parte1_importacao.md`).
- **Escopo:** vendas com `data_emissao` entre 01/02/2025 e 28/02/2025, além dos
  pedidos e recebimentos usados para explicar essas vendas.
- **Fonte da verdade:** a planilha do cliente e os documentos fiscais/pedidos
  originais. O banco é a fonte consultada; divergências não foram corrigidas
  silenciosamente.
- **Consultas:** todas as consultas citadas estão em `sql/04_validacao.sql`,
  identificadas por `[V1]` a `[V15]`.

Números de fevereiro apurados: **14 linhas de venda, 14 produtos distintos,
173,22 unidades e R$ 14.093,17** (`[V1]`). No total da base há 33 vendas
(12 em janeiro, 14 em fevereiro e 7 em março), R$ 34.768,21 (`[V13]`).

## 1. Pontos a validar

1. **Fechamento do período.** Confirmar que o corte de fevereiro é
   `data_emissao >= 01/02/2025` e `< 01/03/2025`, sem vendas canceladas,
   devoluções ou notas fora do período. Conferir a quantidade e o valor totais
   de `[V1]` com o relatório do cliente.
2. **Produtos vendidos sem cadastro.** Em fevereiro há vendas de P22, P23, P24,
   P25, P26 e P27 sem registro em `produtos_filial`; no total são 8 produtos
   (P21..P28) e 13 linhas de venda (`[V3]`). Validar se são produtos novos, de
   outra filial ou códigos digitados incorretamente.
3. **Cobertura por filial.** O cadastro de produtos só existe para a filial 1;
   as filiais 2 e 3 têm vendas de P27/P28 sem cadastro na própria filial
   (`[V15]`). Confirmar se a base de produtos deve ser por filial e se faltam
   linhas para as filiais 2 e 3.
4. **Pendências de compra/recebimento.** Em fevereiro há 14 linhas de pedido com
   saldo pendente (`[V14]`). Confirmar quais foram efetivamente recebidas e se
   as entradas foram lançadas na ordem de compra correta.
5. **Ligação pedido × entrada.** A ligação é feita por
   `ordem_compra` + `item` + `produto_id`. Existem 2 entradas sem pedido
   (ordens 19 e 20, `[V5]`) e 11 pedidos com `ordem_compra = 0` (`[V6]`).
   Perguntar qual é a ordem correta desses pedidos e por que a ordem 0 se repete.
6. **Datas incoerentes.** 20 pedidos têm entrega anterior ao pedido (`[V4]`) e 9
   entradas foram registradas antes da data do pedido (`[V10]`). Confirmar se é
   erro de digitação, data de digitação do sistema ou antecipação permitida.
7. **Quantidades.** 18 pedidos têm `qtde_entregue` diferente da soma das entradas
   (`[V7]`) e 7 entradas receberam mais do que foi pedido (`[V8]`). Definir com o
   cliente qual campo prevalece: `qtde_entregue` do pedido ou a soma das NFe.
8. **Pedidos sem entrada.** 11 pedidos não têm nenhuma entrada vinculada
   (`[V9]`), todos com `ordem_compra = 0`. Verificar se são pedidos em aberto,
   cancelados ou se a entrada foi lançada sem a ordem.
9. **Fornecedores.** Confirmar a lista de 20 fornecedores e a correspondência
   dos ids. Na origem os ids aparecem como `F1`..`F20` em uma tabela e como
   `1`..`20` em outra; a carga normalizou para inteiro, sem perda de vínculo
   (`[V11]` não aponta fornecedor órfão).
10. **Preços e custos.** Conferir se `preco_compra` do cadastro deve acompanhar
    o `custo_unitario` da entrada. Na base atual os 20 recebimentos têm custos
    diferentes do cadastro; isso pode ser normal se o cadastro guardar o custo
    médio/atual, mas precisa ser confirmado com o cliente.
11. **Duplicidades e chaves.** Não há duplicidade nas chaves primárias, mas a
    ordem 0 se repete em P19 e P20 (`[V6]`). Confirmar a unicidade de
    pedido/item/produto e de ordem/item/produto/NFE.
12. **Cadastro e descrições.** Validar descrições, unidades (`UN`) e a
    nomenclatura usada no relatório final (`produto_id - descrição`).

## 2. Técnicas para garantir exatidão e precisão

1. **Reconciliação origem × destino:** comparar a contagem de linhas de cada aba
   com `COUNT(*)` de cada tabela (20/20, 20/20, 29/29, 20/20, 33/33) e repetir
   a soma de quantidade/valor de fevereiro por produto, filial e total.
2. **Conferência de totais por dimensão:** somar por mês, filial e produto e
   comparar com tabelas dinâmicas da planilha; qualquer diferença é investigada
   antes da reunião (`[V1]`, `[V2]`, `[V13]`).
3. **Integridade referencial:** usar `NOT EXISTS`/`LEFT JOIN` para localizar
   vendas sem produto, entradas sem pedido, pedidos sem fornecedor e produtos
   sem fornecedor (`[V3]`, `[V5]`, `[V11]`, `[V15]`).
4. **Regras de negócio:** verificar `data_entrega >= data_pedido`,
   `data_entrada >= data_pedido`, `qtde_recebida >= 0`,
   `qtde_entregue <= qtde_pedida` e coerência entre pedido e entradas
   (`[V4]`, `[V8]`, `[V10]`).
5. **Detecção de sentinelas e duplicidades:** procurar ordem 0, chaves repetidas
   e registros com quantidade/valor nulo ou negativo (`[V6]`, `[V11]`).
6. **Rastreabilidade por documento:** para cada divergência, guardar
   `pedido_id`, `ordem_compra`, `nro_nfe`, produto e data, permitindo abrir a NFe
   ou o pedido original na reunião (`[V7]`, `[V8]`, `[V10]`).
7. **Amostragem dirigida:** selecionar os casos de maior impacto (maiores
   diferenças de quantidade, datas invertidas e produtos sem cadastro) e
   conferir manualmente com o cliente antes de fechar o relatório.
8. **Consultas parametrizadas e versionadas:** manter o período como parâmetro
   (`2025-02-01` a `2025-03-01`) e as consultas em `sql/04_validacao.sql`, para
   repetir a validação em outros meses sem reescrever SQL.
9. **Evidência e aceite:** registrar a execução das consultas, os números
   apurados e as decisões do cliente; só corrigir os dados após autorização,
   com script de correção transacional e nova conferência de contagens.
10. **Reprodutibilidade:** a carga é feita pelo `scripts/importar.py`, com
    relatório de linhas inseridas e rejeitadas; a conferência é repetível a
    partir de uma base recriada pelos DDLs corrigidos.
11. **Segregação de funções:** quem importa não deve ser a única pessoa a
    validar; outra pessoa revisa as consultas e a amostragem antes do aceite.

## 3. Consultas preparadas para a reunião

Todas estão em `sql/04_validacao.sql`.

| Consulta | O que mostra |
| --- | --- |
| `[V1]` | Totais de fevereiro: linhas, produtos distintos, quantidade e R$ |
| `[V2]` | Vendas de fevereiro por produto, com descrição e valor |
| `[V3]` | Vendas de produtos sem cadastro (total e recorte de fevereiro) |
| `[V4]` | Pedidos com data de entrega anterior à data do pedido |
| `[V5]` | Entradas de mercadoria sem pedido de compra |
| `[V6]` | Pedidos com `ordem_compra = 0` e chaves repetidas |
| `[V7]` | Divergência entre `qtde_entregue` e a soma das entradas |
| `[V8]` | Entradas com quantidade recebida maior que a pedida |
| `[V9]` | Pedidos sem nenhuma entrada vinculada |
| `[V10]` | Entradas registradas antes da data do pedido |
| `[V11]` | Checagens de qualidade (nulos, negativos, órfãos) |
| `[V12]` | Contagens de reconciliação das cinco tabelas |
| `[V13]` | Distribuição das vendas por mês |
| `[V14]` | Pendências de fevereiro por pedido, para discussão linha a linha |
| `[V15]` | Vendas em filiais sem cadastro de produto na própria filial |

## Erros encontrados nos dados

Todos os números abaixo foram confirmados executando `sql/04_validacao.sql` na
base carregada. Nenhuma correção foi aplicada: são pendências para validação.

| ID | Tabela | Problema | Quantidade | Consulta que mostra |
| --- | --- | --- | --- | --- |
| E01 | venda / produtos_filial | vendas de produtos sem cadastro (P21..P28) | 8 produtos e 13 linhas de venda (6 linhas em fevereiro) | `[V3]` |
| E02 | pedido_compra | `data_entrega` anterior a `data_pedido` | 20 pedidos (de 29) | `[V4]` |
| E03 | entradas_mercadoria | entrada sem pedido com a mesma `ordem_compra` | 2 entradas (ordens 19 e 20) | `[V5]` |
| E04 | pedido_compra | `ordem_compra = 0`, sem vínculo confiável com entrada | 11 pedidos; 2 chaves `(0, 1, produto)` repetidas | `[V6]` |
| E05 | pedido_compra × entradas_mercadoria | `qtde_entregue` diferente da soma real recebida | 18 pedidos | `[V7]` |
| E06 | entradas_mercadoria | `qtde_recebida` maior que `qtde_pedida` | 7 entradas | `[V8]` |
| E07 | pedido_compra | pedido sem nenhuma entrada vinculada | 11 pedidos (todos com ordem 0) | `[V9]` |
| E08 | entradas_mercadoria | `data_entrada` anterior a `data_pedido` | 9 entradas | `[V10]` |
| E09 | venda / produtos_filial | vendas em filiais 2 e 3 sem produto cadastrado naquela filial | 4 linhas e 2 produtos (P27 na filial 2, P28 na filial 3) | `[V15]` |

### Observações que não foram classificadas como erro

- **Custos divergentes:** os 20 custos de entrada diferem do `preco_compra` do
  cadastro. Pode ser comportamento esperado (custo médio/atualização), por isso
  deve ser confirmado, não tratado como erro automaticamente.
- **Chaves primárias:** não foram encontradas duplicidades nas PKs de `venda`,
  `pedido_compra` nem `entradas_mercadoria`.
- **Nulos/negativos:** as checagens de `[V11]` retornaram zero ocorrências.
- **Fornecedores:** após normalizar `F1`..`F20` para `1`..`20`, não há produto
  nem pedido apontando para fornecedor inexistente.

## Decisões que precisam do cliente

1. Cadastrar P21..P28 ou corrigir os códigos de produto nas vendas?
2. Qual é a `ordem_compra` correta dos pedidos 19 a 29 (hoje em 0) e das
   entradas 19 e 20?
3. Para as quantidades, vale o `qtde_entregue` do pedido ou a soma das NFe?
4. As datas de entrega/entrada anteriores ao pedido devem ser corrigidas ou
   representam lançamento retroativo?
5. O cadastro de produtos deve ser replicado para as filiais 2 e 3?
6. O `preco_compra` do cadastro deve ser atualizado pelo custo da entrada?
7. Quais pendências de fevereiro podem ser baixadas e quais continuam em aberto?

Após as respostas, a correção deve ser feita por script transacional, com nova
execução de `[V1]` a `[V15]`, comparação de contagens e registro do aceite do
cliente.
