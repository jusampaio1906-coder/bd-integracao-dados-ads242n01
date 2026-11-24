"""Importa dados/base_teste.xlsx para PostgreSQL ou MySQL.

Versão corrigida do script do estagiário. As correções e os erros encontrados
estão documentados em docs/parte1_importacao.md.

Uso (PowerShell, PostgreSQL):
    $env:DB_DIALECT  = "postgres"   # padrão
    $env:DB_PASSWORD = "postgres"
    python scripts/importar.py

Uso (PowerShell, MySQL):
    $env:DB_DIALECT  = "mysql"
    $env:DB_PORT     = "3306"
    $env:DB_NAME     = "base_teste"
    $env:DB_USER     = "root"
    $env:DB_PASSWORD = "root"
    python scripts/importar.py

Variáveis de ambiente aceitas:
    DB_DIALECT    postgres | mysql      (padrão: postgres)
    ARQUIVO_XLSX  caminho da planilha   (padrão: dados/base_teste.xlsx)
    DB_HOST       host do banco         (padrão: localhost)
    DB_PORT       porta                 (padrão: 5432 no PostgreSQL, 3306 no MySQL)
    DB_NAME       nome do banco         (padrão: base_teste)
    DB_USER       usuário               (padrão: postgres no PostgreSQL, root no MySQL)
    DB_PASSWORD   senha                 (padrão de exemplo; use variável de ambiente)
"""

import os
import sys
from datetime import date, datetime, time, timedelta

import pandas as pd

DIALETO = os.getenv("DB_DIALECT", "postgres").strip().lower()
if DIALETO not in ("postgres", "mysql"):
    sys.exit("DB_DIALECT inválido: use 'postgres' ou 'mysql'.")

if DIALETO == "postgres":
    import psycopg2
else:
    import pymysql

PADROES = {
    "postgres": {"port": 5432, "user": "postgres", "password": "postgres"},
    "mysql": {"port": 3306, "user": "root", "password": "root"},
}


def ler_inteiro(nome, padrao):
    bruto = os.getenv(nome, str(padrao))
    try:
        return int(bruto)
    except ValueError:
        sys.exit(f"{nome} deve ser numérico: {bruto!r}")


ARQUIVO = os.getenv("ARQUIVO_XLSX", os.path.join("dados", "base_teste.xlsx"))
DB = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": ler_inteiro("DB_PORT", PADROES[DIALETO]["port"]),
    "database": os.getenv("DB_NAME", "base_teste"),
    "user": os.getenv("DB_USER", PADROES[DIALETO]["user"]),
    "password": os.getenv("DB_PASSWORD", PADROES[DIALETO]["password"]),
}

TABELAS = [
    "fornecedor",
    "produtos_filial",
    "pedido_compra",
    "entradas_mercadoria",
    "venda",
]


def tabela(nome):
    return f"public.{nome}" if DIALETO == "postgres" else nome


def ignorar_duplicidade(colunas_pk):
    if DIALETO == "postgres":
        return f"ON CONFLICT ({', '.join(colunas_pk)}) DO NOTHING"
    coluna = colunas_pk[0]
    return f"ON DUPLICATE KEY UPDATE {coluna} = {coluna}"


def ler_aba(nome):
    """Lê uma aba descartando colunas vazias criadas pelo Excel."""
    df = pd.read_excel(ARQUIVO, sheet_name=nome, dtype=object)
    df = df.dropna(how="all")
    df = df.loc[:, [c for c in df.columns if not str(c).startswith("Unnamed")]]
    df.columns = [str(c).strip() for c in df.columns]
    return df


def texto(valor):
    if valor is None or pd.isna(valor):
        return None
    valor = str(valor).strip()
    return valor or None


def numero(valor):
    if valor is None or pd.isna(valor):
        return None
    if isinstance(valor, str):
        valor = valor.strip()
        if not valor:
            return None
        if "," in valor and "." not in valor:
            valor = valor.replace(",", ".")
    return float(valor)


def inteiro(valor):
    numero_convertido = numero(valor)
    return None if numero_convertido is None else int(numero_convertido)


def normalizar_data(valor):
    """Aceita datetime/Timestamp do pandas, serial do Excel e texto."""
    if valor is None or pd.isna(valor):
        return None
    if isinstance(valor, datetime):
        return valor.date()
    if isinstance(valor, date):
        return valor
    if isinstance(valor, (int, float)):
        return (datetime(1899, 12, 30) + timedelta(days=float(valor))).date()

    convertido = pd.to_datetime(str(valor).strip(), dayfirst=True, errors="coerce")
    return None if pd.isna(convertido) else convertido.date()


def normalizar_hora(valor):
    if valor is None or pd.isna(valor):
        return "00:00:00"
    if isinstance(valor, datetime):
        return valor.time().strftime("%H:%M:%S")
    if isinstance(valor, time):
        return valor.strftime("%H:%M:%S")
    return texto(valor) or "00:00:00"


def normalizar_fornecedor(valor):
    """Converte 'F8' -> 8 e mantém ids numéricos, casando com a FK."""
    if valor is None or pd.isna(valor):
        return None
    if isinstance(valor, str):
        limpo = valor.strip().upper()
        if limpo.startswith("F"):
            limpo = limpo[1:]
        if not limpo:
            return None
        return int(float(limpo))
    return int(float(valor))


def executar(cur, sql, parametros, rotulo, erros):
    """Executa uma linha isolada em savepoint; falha não derruba as demais."""
    cur.execute("SAVEPOINT sp_linha")
    try:
        cur.execute(sql, parametros)
        inseridas = max(cur.rowcount, 0)
        cur.execute("RELEASE SAVEPOINT sp_linha")
        return inseridas
    except Exception as exc:  # noqa: BLE001 - queremos registrar qualquer erro de linha
        cur.execute("ROLLBACK TO SAVEPOINT sp_linha")
        cur.execute("RELEASE SAVEPOINT sp_linha")
        erros.append((rotulo, str(exc).strip()))
        return 0


def importar_fornecedor(cur, erros):
    df = ler_aba("fornecedor")
    sql = f"""
        INSERT INTO {tabela('fornecedor')} (idfornecedor, razao_social)
        VALUES (%s, %s)
        {ignorar_duplicidade(['idfornecedor'])}
    """
    inseridas = 0
    for indice, linha in df.iterrows():
        inseridas += executar(
            cur,
            sql,
            (
                normalizar_fornecedor(linha["idfornecedor"]),
                texto(linha["razao_social"]),
            ),
            f"fornecedor linha {indice + 2}",
            erros,
        )
    return len(df), inseridas


def importar_produtos_filial(cur, erros):
    df = ler_aba("produtos_filial")
    sql = f"""
        INSERT INTO {tabela('produtos_filial')}
            (filial_id, produto_id, descricao, estoque,
             preco_unitario, preco_compra, preco_venda, idfornecedor)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
        {ignorar_duplicidade(['filial_id', 'produto_id'])}
    """
    inseridas = 0
    for indice, linha in df.iterrows():
        inseridas += executar(
            cur,
            sql,
            (
                inteiro(linha["filial_id"]),
                texto(linha["idproduto"]),
                texto(linha["descricao"]),
                numero(linha["estoque"]) or 0,
                numero(linha["preco_unitario"]) or 0,
                numero(linha["preco_compra"]) or 0,
                numero(linha["preco_venda"]) or 0,
                normalizar_fornecedor(linha["idfornecedor"]),
            ),
            f"produtos_filial linha {indice + 2}",
            erros,
        )
    return len(df), inseridas


def importar_pedido_compra(cur, erros):
    df = ler_aba("pedido_compra")
    sql = f"""
        INSERT INTO {tabela('pedido_compra')}
            (pedido_id, data_pedido, item, produto_id, descricao_produto,
             ordem_compra, qtde_pedida, filial_id, data_entrega,
             qtde_entregue, qtde_pendente, preco_compra, fornecedor_id)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
        {ignorar_duplicidade(['pedido_id', 'produto_id', 'item'])}
    """
    inseridas = 0
    for indice, linha in df.iterrows():
        qtde_pedida = numero(linha["qtde_pedida"])
        qtde_entregue = numero(linha["qtde_entregue"]) or 0
        qtde_pendente = (qtde_pedida or 0) - qtde_entregue
        inseridas += executar(
            cur,
            sql,
            (
                inteiro(linha["pedido_id"]),
                normalizar_data(linha["data_pedido"]),
                inteiro(linha["item"]),
                texto(linha["produto_id"]),
                texto(linha["descricao_produto"]),
                inteiro(linha["ordem_compra"]) or 0,
                qtde_pedida,
                inteiro(linha["filial_id"]),
                normalizar_data(linha["data_entrega"]),
                qtde_entregue,
                qtde_pendente,
                numero(linha["preco_compra"]) or 0,
                normalizar_fornecedor(linha["fornecedor_id"]),
            ),
            f"pedido_compra linha {indice + 2}",
            erros,
        )
    return len(df), inseridas


def importar_entradas_mercadoria(cur, erros):
    df = ler_aba("entradas_mercadoria")
    sql = f"""
        INSERT INTO {tabela('entradas_mercadoria')}
            (data_entrada, nro_nfe, item, produto_id, descricao_produto,
             ordem_compra, qtde_recebida, filial_id, custo_unitario)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
        {ignorar_duplicidade(['ordem_compra', 'item', 'produto_id', 'nro_nfe'])}
    """
    inseridas = 0
    for indice, linha in df.iterrows():
        inseridas += executar(
            cur,
            sql,
            (
                normalizar_data(linha["data_entrada"]),
                texto(linha["nro_nfe"]),
                inteiro(linha["item"]),
                texto(linha["produto_id"]),
                texto(linha["descricao_produto"]),
                inteiro(linha["ordem_compra"]) or 0,
                numero(linha["qtde_recebida"]),
                inteiro(linha["filial_id"]),
                numero(linha["custo_unitario"]) or 0,
            ),
            f"entradas_mercadoria linha {indice + 2}",
            erros,
        )
    return len(df), inseridas


def importar_venda(cur, erros):
    df = ler_aba("venda")
    sql = f"""
        INSERT INTO {tabela('venda')}
            (venda_id, data_emissao, horariomov, produto_id,
             qtde_vendida, valor_unitario, filial_id, item, unidade_medida)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
        {ignorar_duplicidade(
            ['filial_id', 'venda_id', 'data_emissao', 'produto_id', 'item', 'horariomov']
        )}
    """
    inseridas = 0
    for indice, linha in df.iterrows():
        inseridas += executar(
            cur,
            sql,
            (
                inteiro(linha["venda_id"]),
                normalizar_data(linha["data_emissao"]),
                normalizar_hora(linha["horariomov"]),
                texto(linha["produto_id"]),
                numero(linha["qtde_vendida"]),
                numero(linha["valor_unitario"]) or 0,
                inteiro(linha["filial_id"]),
                inteiro(linha["item"]),
                texto(linha["unidade_medida"]),
            ),
            f"venda linha {indice + 2}",
            erros,
        )
    return len(df), inseridas


def conectar():
    if DIALETO == "postgres":
        return psycopg2.connect(
            host=DB["host"],
            port=DB["port"],
            dbname=DB["database"],
            user=DB["user"],
            password=DB["password"],
            connect_timeout=10,
        )
    return pymysql.connect(
        host=DB["host"],
        port=DB["port"],
        database=DB["database"],
        user=DB["user"],
        password=DB["password"],
        charset="utf8mb4",
        connect_timeout=10,
        autocommit=False,
    )


def main():
    if not os.path.exists(ARQUIVO):
        sys.exit(f"Arquivo não encontrado: {ARQUIVO}")

    rotulo_banco = "PostgreSQL" if DIALETO == "postgres" else "MySQL"
    print(f"Planilha: {ARQUIVO}")
    print(f"Banco: {rotulo_banco} {DB['user']}@{DB['host']}:{DB['port']}/{DB['database']}\n")

    try:
        conn = conectar()
    except Exception as exc:  # noqa: BLE001
        sys.exit(f"Falha ao conectar no {rotulo_banco}: {exc}")

    erros = []
    resultado = {}
    contagens = {}
    try:
        with conn.cursor() as cur:
            etapas = [
                ("fornecedor", importar_fornecedor),
                ("produtos_filial", importar_produtos_filial),
                ("pedido_compra", importar_pedido_compra),
                ("entradas_mercadoria", importar_entradas_mercadoria),
                ("venda", importar_venda),
            ]
            for nome, funcao in etapas:
                print(f"Importando {nome}...")
                previstas, inseridas = funcao(cur, erros)
                resultado[nome] = (previstas, inseridas)
                print(f"  planilha: {previstas} | inseridas agora: {inseridas}")

            if DIALETO == "postgres":
                cur.execute(
                    """
                    SELECT setval(
                        pg_get_serial_sequence('public.fornecedor', 'idfornecedor'),
                        GREATEST(
                            (SELECT COALESCE(MAX(idfornecedor), 0) FROM public.fornecedor),
                            20
                        ),
                        true
                    )
                    """
                )

            print("\nConferência no banco:")
            for tabela_nome in TABELAS:
                cur.execute(f"SELECT COUNT(*) FROM {tabela(tabela_nome)}")
                contagens[tabela_nome] = cur.fetchone()[0]
                previstas, _ = resultado[tabela_nome]
                marca = "OK" if contagens[tabela_nome] == previstas else "DIVERGENTE"
                print(
                    f"  {tabela_nome:<22} planilha={previstas:<3} "
                    f"banco={contagens[tabela_nome]:<3} {marca}"
                )
        conn.commit()
    except Exception as exc:  # noqa: BLE001
        conn.rollback()
        sys.exit(f"Erro durante a importação: {exc}")
    finally:
        try:
            conn.close()
        except Exception:  # noqa: BLE001 - pymysql pode já ter fechado
            pass

    if erros:
        print(f"\nLinhas rejeitadas: {len(erros)}")
        for rotulo, mensagem in erros:
            print(f"  - {rotulo}: {mensagem}")

    divergentes = [
        nome
        for nome, (previstas, _) in resultado.items()
        if contagens.get(nome) != previstas
    ]
    if erros or divergentes:
        print("\nImportação concluída com pendências. Veja os detalhes acima.")
        sys.exit(1)

    print("\nImportação concluída: todas as tabelas conferem com a planilha.")


if __name__ == "__main__":
    main()
