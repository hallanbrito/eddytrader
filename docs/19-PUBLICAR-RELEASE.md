# Publicar uma Release do EddyTrader

O repositório **não versiona binários `.ex5` no Git**. O binário é compilado localmente e anexado como asset da GitHub Release.

## Caminho recomendado — um comando

Depois de atualizar a `master`:

```powershell
git pull
.\scripts\publish_release.ps1
```

O script:

1. verifica se o GitHub CLI (`gh`) está instalado e autenticado;
2. executa o build oficial;
3. exige build limpo;
4. gera ZIP e SHA-256;
5. cria a tag/release `v1.0.0-rc1`;
6. publica como **Pre-release**;
7. anexa os três assets.

Assets publicados:

```text
EddyTrader.ex5
EddyTrader-1.0.0-rc1.zip
CHECKSUMS-1.0.0-rc1.txt
```

## Pré-requisito: GitHub CLI

Se `gh` não estiver instalado:

```powershell
winget install --id GitHub.cli
```

Depois autentique uma vez:

```powershell
gh auth login
```

Escolha GitHub.com, HTTPS e autenticação via navegador.

## Somente gerar os arquivos, sem publicar

```powershell
.\scripts\package_release.ps1
```

Saída:

```text
src\EddyTrader.ex5
dist\EddyTrader-1.0.0-rc1.zip
dist\CHECKSUMS-1.0.0-rc1.txt
```

## Verificar a Release

Após publicação:

```powershell
gh release view v1.0.0-rc1
```

Ou abra:

https://github.com/hallanbrito/eddytrader/releases

## Regra do RC

Enquanto `LIVE-01` estiver pendente:

- versão: `1.0.0-rc1`;
- release: **Pre-release**;
- teste final: **DEMO ONLY**.

Somente após `LIVE-01 PASS` a versão poderá ser promovida para `v1.0.0`.
