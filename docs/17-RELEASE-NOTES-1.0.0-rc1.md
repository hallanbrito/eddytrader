# 17 — Release Notes: EddyTrader 1.0.0-rc1 (Release Candidate 1)

> **Data de Publicação:** 2026-09-13  
> **Versão:** `1.0.0-rc1`  
> **Classificação:** Candidato a Liberação (Release Candidate)  
> **Estado de Homologação:** Homologado com Ressalvas (Gate Aberto: `LIVE-01`)

---

## 1. O que é o EddyTrader

O **EddyTrader** é um Expert Advisor utilitário e autônomo para **MetaTrader 5 (MT5)**, escrito em **MQL5 nativo puro**, cujo foco exclusivo é o **gerenciamento de perda diária e proteção de capital da conta**.

O software atua como uma salvaguarda comportamental e operacional: ele não é uma estratégia de trading, não emite sinais de compra ou venda, não posiciona Stop Loss discricionário e não gerencia metas de ganho financeiro.

---

## 2. Principais Garantias e Capacidades Entregues

1. **Monitoramento Financeiro Consolidado em Tempo Real:**
   * Apura o resultado líquido diário $D(t) = R_{\text{day}}(t) + F(t)$, somando o realizado contábil do dia ao flutuante das posições abertas.
   * Exclui integralmente movimentações de capital (depósitos, saques e créditos).
2. **Liquidação Compulsória Global Desacoplada:**
   * Atua sobre 100% dos ativos e ordens da conta sem filtros por símbolo ou Magic Number.
   * Fechamento compulsório a mercado executado estritamente por ticket individual (`PositionClose(ticket)`), assegurando compatibilidade idêntica em contas Netting e Hedging.
   * Cancelamento determinístico de todas as ordens pendentes (`OrderDelete(ticket)`).
3. **Bloqueio Temporal Ininterrupto de 4 Horas:**
   * Duração contínua de 4 horas ($t_{\text{unlock}} = t_{\text{trigger}} + 14.400$ s) contadas no relógio oficial do servidor de negociação.
   * Soberania sobre a virada de dia: atravessar a meia-noite (`00:00:00`) não zera nem reduz a duração do bloqueio.
4. **Neutralização Reativa de Intervenções Manuais em Bloqueio:**
   * Interceptação em tempo real via `OnTradeTransaction`: qualquer posição ou ordem aberta pelo operador durante o bloqueio é imediatamente encerrada a mercado, preservando o prazo original de liberação.
5. **Reabertura Matemática Controlada sem Rebloqueio:**
   * Desbloqueio formal condicionado ao término das 4 horas e à ausência de resíduos abertos (`PositionsTotal == 0 && OrdersTotal == 0`).
   * Captura da nova baseline no momento exato do desbloqueio ($B_{n+1} = D(t_{\text{reopen}})$), garantindo algebricamente que a nova janela operacional inicie com $W_{n+1} = 0.00$, impedindo o falso rebloqueio imediato.
6. **Guarda de Instância Única Puramente Atômica via CAS:**
   * Protocolo atômico `OWNER + HEARTBEAT` com exclusão mútua baseada em Compare-And-Swap (`GlobalVariableSetOnCondition`).
   * Rejeição imediata de segundas instâncias concorrentes.
   * Preservação de heartbeat no encerramento para evitar corridas destrutivas.
   * Assunção limpa (*takeover*) após 15 segundos de inatividade do titular anterior.
   * Contenção *fail-closed* absoluta para instâncias zumbis.
7. **Resiliência a Reinicializações (Queda de Energia / Crash):**
   * Persistência em disco de $\mathbf{D}_{\text{min\_recovery}}$ via Global Variables do Terminal MT5 com chave prefixada por login.
   * Reconstituição determinística da FSM no `OnInit()`, com prioridade de liquidação caso haja posições residuais.

---

## 3. Limitações Conhecidas e Avisos Operacionais Críticos

* **MaxLoss é um Limiar de Disparo:**  
  O parâmetro `InpMaxLoss` estabelece o instante em que o robô emite o comando irrevogável de liquidação. Ele **não é uma garantia de perda final exata**. A perda final pode exceder o limiar devido a *slippage*, abertura de *spread*, taxas da bolsa, *gaps* de abertura de mercado ou latência de rede.
* **Neutralização Reativa vs. Bloqueio Preventivo Físico:**  
  No MetaTrader 5 nativo (sem injeção invasiva de DLLs no processo do sistema operacional), o terminal despacha cliques manuais diretamente para a corretora. O EddyTrader neutraliza a ordem milissegundos após sua confirmação pela corretora.
* **Dependência do Terminal Ativo:**  
  O EddyTrader somente atua enquanto o terminal MT5 estiver ligado, em execução e conectado à internet. Se o terminal for desligado, a neutralização física não ocorre até o terminal ser reaberto.
* **Ambiente de Mercado Fechado:**  
  Ordens em ativos cujo mercado esteja fechado no momento do disparo receberão retcode `10018` e serão retidas em `LIQUIDATING` com retentativas contínuas a 500 ms até a reabertura do ativo.

---

## 4. Evidências de Validação e Testes

* **Compilação:** 100% aprovada (0 errors, 0 warnings) em MetaEditor 64-bit build 6193.
* **Suíte de Regressão Formal Automatizada:** **28/28 PASS (100%)** executados no Strategy Tester do MT5 (`tests/test_fsm_w06.mq5`), cobrindo os cenários `W06-01..20`, `W07R-01..06` e `W08R-01..02`.
* **Homologação em Conta Demo Conectada:** 15 cenários operacionais auditados (`DEMO-01` a `DEMO-15`) no servidor `ActivTradesCorp-Server` (login `6272676`).

---

## 5. Gate Externo para a Versão Final 1.0.0

A promoção formal deste Release Candidate para a versão de produção **1.0.0 final** requer exclusivamente a realização do teste:

* **`LIVE-01`:** Teste ponta a ponta de emissão de ordem manual e medição de latência de neutralização reativa exclusivamente em **conta Demo com sessão de mercado ao vivo aberta** (DEMO ONLY, `SymbolInfoInteger(SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_FULL`). A homologação jamais exige conta Real.

Enquanto o teste `LIVE-01` permanecer em aberto (aguardando a abertura do calendário financeiro), o produto é formal e estritamente mantido como **Release Candidate (`1.0.0-rc1`)**, e o registro arquitetural [ADR 0005](file:///C:/Projetos/eddytrader/docs/adr/0005-garantias-tecnicas-mt5-e-estrategia-de-recuperacao.md) permanece no status **`Proposed`**.
