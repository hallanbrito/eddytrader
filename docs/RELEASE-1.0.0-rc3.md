# EddyTrader — 1.0.0-rc3

**Publicação:** 02/11/2026  
**Classificação:** Release Candidate (pré-lançamento)  
**Código:** branch `master`, incluindo as entregas W10.4 do PR #14.

## Novidades desta entrega

- HUD adaptativo e operação de monitoramento de risco para toda a conta.
- Leitura financeira fortalecida: indisponibilidade ou inconsistência do histórico não é confundida com resultado zero.
- Confirmação de liquidação e cancelamento por retcode e inventário, com retentativas controladas.
- Persistência mais segura, recuperação de bloqueio e preservação de eventos, baseline e janela de proteção.
- Callbacks de negociação observacionais: a FSM reconcilia as exposições por timer, evitando solicitações duplicadas durante eventos.
- Melhorias de confiabilidade e redução do excesso de logs.

## Validação

- MetaEditor: **0 erros, 0 avisos**.
- Regressão geral: **81/81 PASS**.
- Testes de integridade financeira em harness/modelo: **18/18 PASS**.
- Smoke no Strategy Tester EURUSD/M1: **22.735 ticks**, **5.738 barras**, **PASS**.
- Inicialização observada no MT5 Demo com painel `MONITORING`, ownership adquirido e zero posições/ordens.

Os testes não comprovam execução de todos os cenários transacionais reais; a Issue #12 registra os testes empíricos Demo complementares. O EA depende do MT5 aberto, conectado e com negociação algorítmica habilitada.

## Recomendação de utilização

**Recomendamos testar primeiro em conta Demo antes de utilizar em conta Real.** Verifique as configurações, as particularidades da corretora e o comportamento da proteção no seu ambiente.

**Encontrou algum erro ou comportamento inesperado?** Relate em https://github.com/hallanbrito/eddytrader/issues para que possamos analisar e, se necessário, disponibilizar uma correção.

Este programa não garante prevenção de perdas em todas as circunstâncias; mercado, latência, slippage, infraestrutura e indisponibilidade da corretora podem afetar a execução.

## Instalação

A página do GitHub fornece automaticamente os arquivos de código-fonte (`.zip` e `.tar.gz`). Abra `src/EddyTrader.mq5` no MetaEditor do MT5 e compile para gerar `EddyTrader.ex5`. **Não confunda o pacote de código-fonte com um binário `.ex5` pronto para instalar.**

**Mudanças relevantes:** https://github.com/hallanbrito/eddytrader/pull/14
