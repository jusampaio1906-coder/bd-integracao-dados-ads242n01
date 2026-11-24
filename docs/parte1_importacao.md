# Parte 1: Documentação do processo de importação

## Ferramenta utilizada

- **Script:** `scripts/importar.py` (versão corrigida), em Python 3.15, com
  `pandas` 3.1.1, `openpyxl` 3.1.5, `psycopg2` 2.9.13 (PostgreSQL) e
  `PyMySQL` 2.2.8 (MySQL).
- **SGBDs de teste:** PostgreSQL 16.16 e MySQL 8.0.46, executados em contêineres
  Docker locais. O DBeaver pode ser usado para conferência manual das mesmas consultas.
- O script recebe a conexão por variáveis de ambiente; **nenhuma senha real fica
  gravada no código**.

```powershell
# PostgreSQL
$env:DB_DIALECT="postgres"; $env:DB_PORT="5432"; $env:DB_NAME="base_teste"
$env:DB_USER="postgres"; $env:DB_PASSWORD="postgres"
python scripts/importar.py

# MySQL
$env:DB_DIALECT="mysql"; $env:DB_PORT="3306"; $env:DB_NAME="base_teste"
$env:DB_USER="root"; $env:DB_PASSWORD="root"
python scripts/importar.py
```

Antes do script, o DDL corrigido deve ser aplicado:

```bash
psql -U postgres -d base_teste -f sql/01_ddl_postgres.sql
mysql -u root -p base_teste < sql/01_ddl_mysql.sql
```

## Estrutura da planilha

`dados/base_teste.xlsx` possui 5 abas e 122 linhas de dados. As abas `venda`,
`pedido_compra` e `produtos_filial` trazem colunas extras totalmente vazias,
descartadas na leitura.

| Aba | Coluna | Tipo observado | Observação |
| --- | --- | --- | --- |
| fornecedor | idfornecedor | texto (`F1`..`F20`) | normalizado para inteiro (1..20) |
| fornecedor | razao_social | texto | 20 fornecedores |
| produtos_filial | filial_id | inteiro | 1 |
| produtos_filial | idproduto | texto (`P1`..`P20`) | vira `produto_id` |
| produtos_filial | descricao | texto | vira `descricao` no DDL corrigido |
| produtos_filial | estoque | decimal | |
| produtos_filial | preco_unitario | decimal | |
| produtos_filial | preco_compra | decimal | |
| produtos_filial | preco_venda | decimal | |
| produtos_filial | idfornecedor | texto (`F1`..`F20`) | normalizado para inteiro e usado na FK |
| pedido_compra | pedido_id | inteiro | 1..29 |
| pedido_compra | data_pedido | data | |
| pedido_compra | item | inteiro | |
| pedido_compra | produto_id | texto | |
| pedido_compra | descricao_produto | texto | |
| pedido_compra | ordem_compra | inteiro | 0..18; chave de ligação com a entrada |
| pedido_compra | qtde_pedida | decimal | |
| pedido_compra | filial_id | inteiro | 1 |
| pedido_compra | data_entrega | data | contém datas anteriores ao pedido (ver Parte 4) |
| pedido_compra | qtde_entregue | decimal | |
| pedido_compra | preco_compra | decimal | |
| pedido_compra | fornecedor_id | inteiro | 1..20 |
| entradas_mercadoria | data_entrada | data | |
| entradas_mercadoria | nro_nfe | texto | `NFE1`..`NFE20` |
| entradas_mercadoria | item | inteiro | |
| entradas_mercadoria | produto_id | texto | |
| entradas_mercadoria | descricao_produto | texto | |
| entradas_mercadoria | ordem_compra | inteiro | 1..20 |
| entradas_mercadoria | qtde_recebida | decimal | |
| entradas_mercadoria | filial_id | inteiro | |
| entradas_mercadoria | custo_unitario | decimal | |
| venda | venda_id | inteiro | 1..33 |
| venda | data_emissao | data | jan/2025 a mar/2025 |
| venda | horariomov | texto de hora | `08:00:00` |
| venda | produto_id | texto | inclui P21..P28 sem cadastro |
| venda | qtde_vendida | decimal | |
| venda | valor_unitario | decimal | |
| venda | filial_id | inteiro | 1, 2 e 3 |
| venda | item | inteiro | |
| venda | unidade_medida | texto | `UN` |

## Erros encontrados no DDL e como foram corrigidos

Saída real do DDL original no PostgreSQL 16 (banco limpo), antes das correções:

```
ERROR:  column "ordem_compra" named in key does not exist
ERROR:  syntax error at or near "("
LINE 6:  CONSTRAINT produtos_filial_pkey PRIMARY KEY (filial_id, idp...
ERROR:  column "idproduto" named in key does not exist
```

| Tabela | Erro | Correção |
| --- | --- | --- |
| entradas_mercadoria | PK cita `ordem_compra`, mas a coluna não foi declarada | adicionada `ordem_compra bigint NOT NULL` |
| produtos_filial | falta vírgula após `idfonecedor int4 NULL`, antes de `CONSTRAINT` | vírgula incluída |
| produtos_filial | `decricao` (typo) | renomeada para `descricao` |
| produtos_filial | `idfonecedor` (typo) | renomeada para `idfornecedor` |
| produtos_filial | PK cita `idproduto`, coluna inexistente | PK passa a ser `(filial_id, produto_id)` |
| produtos_filial | `filial_id` declarado `NULL`, mas faz parte da PK | definido `NOT NULL` |
| produtos_filial | `produto_id varchar(255)` diverge de `varchar(25)` nas demais tabelas | padronizado em `varchar(25)` |
| fornecedor | `idforncedor` (typo) | renomeada para `idfornecedor` |
| fornecedor | PK `(idforncedor, idproduto)` cita coluna inexistente | PK passa a ser apenas `(idfornecedor)` |
| fornecedor / pedido_compra / produtos_filial | ids de fornecedor com tipos diferentes (`varchar(25)` e `int4`) | padronizado em `integer`; prefixo `F` normalizado na carga |
| pedido_compra | `fornecedor_id int4 DEFAULT 0` apontaria para fornecedor inexistente se houvesse FK | default alterado para `NULL` e FK criada |
| vários | `float8 DEFAULT '0'` usa texto como default numérico | defaults numéricos (`0`) |
| MySQL | `int8`, `float8`, `numeric`, `public.`, `::character varying` e `ON CONFLICT` não existem no MySQL | DDL próprio em `sql/01_ddl_mysql.sql` |

Decisões de modelagem documentadas no próprio DDL:

- `fornecedor.idfornecedor` é numérico e usa identidade/`AUTO_INCREMENT` a partir
  de 21, permitindo a trigger da Parte 3 sem colidir com os ids 1..20.
- FKs reais: `produtos_filial.idfornecedor` e `pedido_compra.fornecedor_id` →
  `fornecedor.idfornecedor`.
- **Não** foram criadas FKs para `venda.produto_id` nem para
  `entradas_mercadoria.ordem_compra`: os dados de teste contêm vendas de produtos
  não cadastrados (P21..P28) e entradas sem pedido (ordens 19 e 20). Criar essas
  FKs impediria a carga; as ocorrências são reportadas em `sql/04_validacao.sql`.

## Erros encontrados no script de importação e como foram corrigidos

| Erro | Efeito | Correção |
| --- | --- | --- |
| INSERT em `descricao` e `idfornecedor` | colunas não existiam no DDL (`decricao`/`idfonecedor`); toda linha falhava | nomes alinhados ao DDL corrigido |
| `ON CONFLICT (filial_id, produto_id)` e `(idfornecedor)` não correspondiam às PKs reais | erro de constraint; linhas rejeitadas | conflito aponta para a PK real de cada tabela |
| INSERT em `fornecedor` sem `idproduto` | PK original exigia coluna inexistente | PK corrigida e INSERT com as colunas reais |
| `excel_para_data` fazia `int(valor)` em datas já lidas como `Timestamp` pelo pandas | exceção silenciosa: retornava `None` e todas as datas viravam NULL | função aceita `datetime`, `date`, serial do Excel e texto |
| `idfornecedor`/`fornecedor_id` com prefixo `F` ou texto gravado em coluna `int4` | `invalid input syntax for type integer` | normalização `F8` → `8` antes do INSERT |
| `conn.rollback()` a cada linha com erro | apagava também as linhas anteriores da mesma transação | `SAVEPOINT` por linha; erro não derruba as demais |
| `len(df)` exibido como “registros inseridos” | contagem falsa: mostrava o total da planilha mesmo com falhas | conta `cur.rowcount` e confere `SELECT COUNT(*)` no banco |
| `df.iloc[:, :12]` + renomeação posicional em `pedido_compra` | podia desalinhar colunas se a planilha mudasse | leitura por nome, descartando colunas vazias `Unnamed` |
| senha `1234` fixa no código | credencial exposta no repositório | conexão por variáveis de ambiente, com exemplos |
| suporte apenas a PostgreSQL | o enunciado pede MySQL e PostgreSQL | `DB_DIALECT` = `postgres` ou `mysql`; SQL de conflito e prefixo de schema adaptados |
| datas de entrega anteriores ao pedido, ordens órfãs etc. | erros de negócio nos dados | **não** foram mascarados na carga; foram catalogados na Parte 4 |

## Tratamentos aplicados aos dados

1. **Leitura:** `pandas.read_excel` por aba, removendo linhas vazias e colunas
   `Unnamed` geradas pelo Excel; colunas mapeadas por nome.
2. **Textos:** `strip()` em ids, descrições, NFE e unidade; vazio/NaN → `NULL`.
3. **Datas:** conversão de `datetime`/`Timestamp` do pandas e de serial do Excel
   para `date`; nenhuma data virou `NULL` após a correção.
4. **Fornecedores:** `F1`..`F20` → `1`..`20`, alinhando planilha, FK e trigger.
5. **Números:** conversão para `float`/`int`, aceitando vírgula decimal quando
   não houver ponto; `NaN` → `NULL` (ou `0` nos defaults do DDL).
6. **`qtde_pendente`:** recalculada como `qtde_pedida - qtde_entregue`.
7. **Duplicidade:** INSERT idempotente (`ON CONFLICT DO NOTHING` no PostgreSQL e
   `ON DUPLICATE KEY UPDATE` no MySQL).
8. **Erros por linha:** cada INSERT roda em `SAVEPOINT`; no fim o script lista as
   linhas rejeitadas e compara as contagens com a planilha, saindo com código 1
   se houver divergência.
9. **Integridade:** após a carga, a sequência de `fornecedor` é ajustada para 21
   (PostgreSQL), preservando a trigger da Parte 3.

## Conferência final

Execução real do script corrigido (as duas bases foram recriadas com os DDLs
corrigidos antes da carga):

| Tabela | Linhas na planilha | Linhas no PostgreSQL | Linhas no MySQL |
| --- | --- | --- | --- |
| fornecedor | 20 | 20 | 20 |
| produtos_filial | 20 | 20 | 20 |
| pedido_compra | 29 | 29 | 29 |
| entradas_mercadoria | 20 | 20 | 20 |
| venda | 33 | 33 | 33 |

Conferências complementares realizadas:

- `venda`: 0 datas nulas; menor `2025-01-03`, maior `2025-03-28`.
- `pedido_compra`: 0 datas de pedido/entrega nulas.
- `fornecedor`: ids de 1 a 20.
- `produtos_filial`: 0 fornecedores órfãos após a normalização.

## Erros de dados preservados para a validação

A importação **não corrige** inconsistências de negócio, pois elas precisam ser
validadas com o cliente. Elas entram como estão e são demonstradas por consulta
em `sql/04_validacao.sql` e resumidas em `docs/parte4_validacao.md`:

- 8 produtos vendidos sem cadastro em `produtos_filial` (P21..P28, 13 linhas de venda);
- 20 pedidos com `data_entrega` anterior a `data_pedido`;
- 2 entradas com `ordem_compra` sem pedido correspondente (ordens 19 e 20);
- 11 pedidos com `ordem_compra = 0` (sem vínculo confiável com entrada);
- 18 divergências entre `pedido_compra.qtde_entregue` e a soma de `entradas_mercadoria`;
- 7 entradas com quantidade recebida maior que a quantidade pedida;
- 9 entradas com `data_entrada` anterior a `data_pedido`;
- 4 vendas nas filiais 2 e 3 sem produto cadastrado na própria filial.
