# Disciplinador Trader — Notas de versão 1.0.0-rc4

**Data:** 02/11/2026  
**Tipo:** Release Candidate 4 (pré-lançamento)  
**Plataforma:** MetaTrader 5, MQL5  
**Repositório:** https://github.com/hallanbrito/eddytrader

## O que mudou

- Corrigida a leitura de histórico financeiro para evitar confundir dados indisponíveis com resultado zero.
- Fortalecida a confirmação de liquidação e cancelamento: retcode do servidor e conferência de posições e ordens remanescentes.
- Melhorada a persistência e a recuperação do bloqueio, com gravação consistente do estado.
- O painel consulta o snapshot financeiro do motor, sem alterar o estado de risco.
- Callbacks de negociação apenas observam os eventos; a reconciliação ocorre pelo timer, reduzindo operações duplicadas e corridas.
- Mensagens repetitivas de contenção têm limitação de frequência.

## Verificações realizadas

- MetaEditor: 0 erros e 0 avisos.
- Regressão geral: 81/81 testes aprovados.
- Integridade financeira W10.4: 18/18 cenários modelados aprovados.
- Strategy Tester (EURUSD/M1, 26 a 30/10/2026): 22.735 ticks, 5.738 barras; smoke aprovado.
- Instalação inicial verificada visualmente em MT5 Demo, com painel MONITORING, ownership ativo, nenhuma posição e nenhuma ordem.

Os testes automatizados não substituem testes com execução efetiva de ordens. O EA depende de terminal ativo, conexão e resposta da corretora.

## Recomendação de uso

**Recomendamos testar a RC4 em uma conta Demo antes de utilizá-la em uma conta Real.** Confirme a configuração, o comportamento com sua corretora e o funcionamento do bloqueio antes de assumir riscos financeiros.

Se encontrar algum erro ou comportamento inesperado, **relate na área de Issues do GitHub**: https://github.com/hallanbrito/eddytrader/issues. A equipe analisará o relato e, quando necessário, preparará uma correção.

## Instalação

Abra o MetaEditor do MetaTrader 5 e compile `src/EddyTrader.mq5` para gerar o `EddyTrader.ex5` desta versão. O binário de versões anteriores não incorpora automaticamente o versionamento e as correções da RC4. Se houver um `.ex5` publicado como anexo oficial, confira a versão antes de instalar.

A RC4 é um **candidato a lançamento**; não é garantia de eliminação de perdas, execução imediata ou proteção com o terminal desligado.
