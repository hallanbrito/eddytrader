# Publicar uma Release do EddyTrader

## Gerar os assets

Na raiz do repositório, execute:

    ./scripts/package_release.ps1

O script executa o build oficial e gera:

    dist/EddyTrader-1.0.0-rc1.zip
    dist/CHECKSUMS-1.0.0-rc1.txt

O binário principal compilado fica em:

    src/EddyTrader.ex5

## Publicar no GitHub

Enquanto LIVE-01 estiver pendente:

- tag: v1.0.0-rc1
- título: EddyTrader 1.0.0-rc1
- marcar como Pre-release

Anexar:

- EddyTrader.ex5
- EddyTrader-1.0.0-rc1.zip
- CHECKSUMS-1.0.0-rc1.txt

Após LIVE-01 PASS, promover para a release final v1.0.0.