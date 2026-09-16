# 23 — Spike Técnico W11: Proteção Monotônica de Stop Loss

## 1. Status e limite de escopo

**Status:** em investigação; evidência parcial coletada em conta Demo.

**GAP:** GAP-007.

**Regra de segurança:** nenhum SL Lock foi implementado em `src/EddyTrader.mq5`. O probe desta W é observacional, bloqueia conta Real/Contest e não chama `OrderSend`, `PositionModify`, `OrderModify`, `PositionClose` ou `OrderDelete`.

Esta W existe para reduzir incerteza antes de qualquer proposta de W12. Ela não autoriza implementação produtiva nem altera a promessa atual do Disciplinador Trader.

## 2. Base técnica oficial

- `OnTradeTransaction` recebe operações manuais, solicitações MQL5, ativações de ordens e operações do servidor. A ordem de chegada dos eventos não é garantida, uma solicitação pode gerar vários eventos e a fila possui 1024 elementos. Portanto, a arquitetura deve reconciliar o inventário real em vez de depender de uma sequência rígida: [documentação oficial](https://www.mql5.com/en/docs/event_handlers/ontradetransaction).
- `TRADE_ACTION_SLTP` é a ação nativa para modificar SL/TP de uma posição aberta; `TRADE_ACTION_MODIFY` é usada para modificar uma ordem pendente: [documentação oficial](https://www.mql5.com/en/docs/constants/tradingconstants/enum_trade_request_actions).
- `SYMBOL_TRADE_STOPS_LEVEL` e `SYMBOL_TRADE_FREEZE_LEVEL` são restrições do símbolo que podem impedir uma restauração imediata: [documentação oficial](https://www.mql5.com/en/docs/constants/environment_state/marketinfoconstants).
- `ACCOUNT_MARGIN_MODE` distingue Netting de Hedging; em Netting há apenas uma posição por símbolo, enquanto Hedging permite múltiplas posições: [documentação oficial](https://www.mql5.com/en/docs/constants/environment_state/accountinformation).

## 3. Artefatos

- `research/w11/probe_sl_lock_w11.mq5`: probe Demo-only, observacional e sem escrita comercial;
- `research/w11/test_sl_monotonic_w11.mq5`: sete casos puros da classificação monotônica BUY/SELL, remoção, primeira definição e ruído inferior a meio tick;
- evidência operacional preexistente no Journal do MT5 em 2026-09-16, conta Demo ActivTrades, modo Netting.

## 4. Evidência empírica já observada

Durante uma sessão Demo Netting em `GBPUSD`, o Journal registrou:

1. abertura BUY sem SL e posterior definição manual de SL;
2. modificação de posição reportada por `TRADE_TRANSACTION_POSITION` com `price_sl` e confirmação pelo inventário da posição;
3. evento `TRADE_TRANSACTION_REQUEST` separado da alteração de posição;
4. segundo deal BUY agregado à mesma posição/ticket, elevando o volume de `0.01` para `0.02`;
5. aperto posterior do SL classificado como melhoria monotônica;
6. múltiplos eventos (`ORDER_ADD`, `POSITION`, `ORDER_DELETE`, `HISTORY_ADD`, `DEAL_ADD`) associados ao fechamento, confirmando que não se deve assumir ordem transacional rígida.

Esses registros comprovam somente observação/eventos no ambiente testado. Eles não medem restauração automática, throttling, rejeição, Hedging ou carga multiativo.

## 5. Matriz das 12 questões do GAP-007

| # | Questão | Estado | Evidência / conclusão atual |
|---:|---|---|---|
| 1 | Notificação transacional | **Parcialmente respondida** | Alteração manual de SL foi observada como `TRADE_TRANSACTION_POSITION`, acompanhada de `REQUEST`; o inventário do servidor deve ser a fonte final. Ordens pendentes ainda precisam de ensaio dedicado. |
| 2 | Latência de reversão | **Aberta** | O probe não restaura SL e, por desenho, não mede round-trip corretivo. |
| 3 | Throttling da corretora | **Aberta** | Nenhuma rajada de correções foi enviada. |
| 4 | Rejeição / freeze / mercado | **Política decidida; validação técnica aberta** | O PO determinou: tentar restaurar o último SL protegido; se a restauração falhar, fechar imediatamente a posição para preservar o capital. Stops/freeze são registrados, mas o fluxo ainda não foi validado. |
| 5 | Matemática BUY/SELL | **Respondida no modelo** | BUY: SL menor aumenta risco; SELL: SL maior aumenta risco. Melhoria avança a referência monotônica. Sete casos puros cobrem direções, remoção, primeira definição e ruído. |
| 6 | Posição sem SL inicial | **Ambiguidade de produto** | Abertura sem SL foi observada. Exigir SL imediato ou começar a proteção no primeiro SL são políticas distintas e exigem decisão do PO. |
| 7 | Remoção de SL | **Política decidida; validação técnica aberta** | Remoção é violação imediata. O fluxo desejado é restaurar o último SL protegido; se a restauração falhar, fechar imediatamente a posição. |
| 8 | Ordens pendentes | **Aberta** | O probe registra `ORDER_ADD/UPDATE/DELETE`, mas falta matriz Buy/Sell Limit/Stop antes da execução. |
| 9 | Netting vs. Hedging | **Parcialmente respondida** | Netting agregou volume preservando o ticket no caso observado. Hedging e mudança/recriação de tickets ainda não foram validados. |
| 10 | Trailing / EA externo | **Aberta** | O modelo aceita aperto e rejeita afrouxamento, mas loop/race com escritor concorrente não foi ensaiado. |
| 11 | Persistência pós-restart | **Aberta** | O probe não persiste baseline de SL. Não há base para escolher GV/arquivo ou reconstrução histórica. |
| 12 | Carga multiativo | **Aberta** | Sem ensaio simultâneo e sem métricas de fila/latência. |

## 6. Regras do probe

1. reconciliar sempre `PositionSelectByTicket` / `PositionGet*`; nunca confiar apenas no payload do evento;
2. não assumir ordem ou cardinalidade fixa de eventos;
3. manter como referência o SL mais protetivo observado;
4. avançar a referência apenas em primeira definição ou aperto;
5. em afrouxamento/remoção, registrar a violação e conservar a referência, sem agir;
6. remover cache somente quando o ticket não existir mais no inventário;
7. operar exclusivamente em Demo com confirmação explícita;
8. manter logs de varredura sem mudança desativados por padrão para evitar ruído e pressão na fila.

## 7. Decisão do Product Owner

### W11-DEC-01 — Falha ao restaurar SL protegido

**Decisão:** diante de afrouxamento ou remoção, o sistema deverá tentar restaurar o último SL monotônico válido. Se a corretora rejeitar a restauração, o nível estiver tecnicamente inválido ou a posição continuar desprotegida após a tentativa, o Disciplinador deverá **fechar imediatamente a posição por ticket**, priorizando a preservação do capital.

**Limite atual:** esta é uma decisão de produto, não uma afirmação de viabilidade já comprovada. O probe corretivo, os retcodes aceitos, a confirmação pós-request e a prevenção de loops precisam ser definidos e testados em Demo antes de qualquer alteração em produção.

## 8. Próximo gate técnico

A W11 não pode ser declarada concluída ainda. Antes de qualquer W12, faltam:

- decisão do PO para posições sem SL inicial;
- ensaios Demo controlados de widening/removal em BUY e SELL;
- matriz de ordens pendentes;
- conta Hedging;
- ensaio de escritor concorrente/trailing;
- experimento de persistência/restart;
- teste multiativo e, somente se autorizado, probe corretivo isolado para latência/rejeição/throttling.

Até esses gates, a conclusão correta é: **viabilidade de detecção parcialmente demonstrada; viabilidade segura de restauração automática ainda não demonstrada**.
