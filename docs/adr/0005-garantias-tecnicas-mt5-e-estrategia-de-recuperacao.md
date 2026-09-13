# ADR 0005 — Garantias Técnicas do MT5, Neutralização de Bloqueio e Estratégia de Recuperação

* **Status:** Proposta (*Proposed*)
* **Data:** 2026-09-13
* **Autor:** Agente Autônomo (Método C.H.)
* **Contexto:** [W05 — Spike Técnico MT5/MQL5: Garantias, Eventos, Liquidação, Bloqueio e Recuperação](file:///C:/Projetos/eddytrader/docs/12-SPIKE-TECNICO-MT5.md)
* **Decisões Relacionadas:** [ADR 0001](file:///C:/Projetos/eddytrader/docs/adr/0001-regras-temporais-e-janelas-de-protecao.md), [ADR 0002](file:///C:/Projetos/eddytrader/docs/adr/0002-composicao-da-perda-operacional.md), [ADR 0003](file:///C:/Projetos/eddytrader/docs/adr/0003-modelo-matematico-de-janelas-e-baseline.md) e [ADR 0004](file:///C:/Projetos/eddytrader/docs/adr/0004-maquina-de-estados-e-recuperacao.md)

---

## 1. Contexto

A W01 definiu a fundação do produto; a W02 estabeleceu as regras temporais e de risco; a W03 formalizou a matemática das janelas operacionais; e a W04 normatizou a Máquina de Estados Finita (FSM). 

Essas definições conceituais continham hipóteses técnicas que foram confrontadas na W05 contra a documentação oficial da MetaQuotes, a compilação com o compilador oficial MetaEditor 64 (build 6193) e testes em ambiente local:
1. Como o sistema percebe alterações comerciais em tempo real (`OnTrade` vs `OnTradeTransaction`)?
2. Um Expert Advisor consegue impedir fisicamente ordens manuais disparadas no terminal antes de chegarem ao servidor da corretora?
3. Como garantir que a liquidação e o inventário funcionem igualmente em contas Netting e Hedging sem ambiguidades?
4. Qual função de tempo do MT5 reflete o avanço real do relógio do servidor sem congelar na ausência de cotações?
5. O conjunto mínimo de recuperação $\mathbf{D}_{\text{min\_recovery}}$ pode ser reconstruído unicamente a partir do histórico nativo de deals ou requer persistência própria ([GAP-005](file:///C:/Projetos/eddytrader/docs/08-RISCOS-E-QUESTOES-ABERTAS.md#gap-005--persistência-e-reconstrução-de-estado-após-reinicialização))?

Como o ambiente laboratorial da W05 operou sem sessão remota ativa com a corretora (`Invalid account`), o status deste ADR é mantido como **Proposed**, assegurando que decisões que dependem de preenchimento real de mercado e medição de latência em rede não sejam tratadas prematuramente como certezas definitivas.

---

## 2. Decisões Técnicas Propostas

### 2.1. Sensor Primário de Eventos Transacionais
* **Decisão Proposta:** O EddyTrader adota **`OnTradeTransaction`** como seu canal primário de notificação comercial, mantendo **`OnTrade`** como salvaguarda periódica de consistência e varredura de integridade.
* **Ressalva Oficial:** Uma única solicitação comercial produz múltiplas transações (`REQUEST`, `ORDER_ADD`, `DEAL_ADD`, `ORDER_DELETE`), e **a ordem de chegada dessas transações ao terminal cliente não é garantida pelo MT5**.
* **Diretriz de Implementação:** A W06 não pode depender de uma máquina de parsing rígida sobre a sequência de eventos; o robô deve reconciliar seu estado diretamente com o **inventário real da conta** (`PositionsTotal` e `OrdersTotal`).

### 2.2. Garantia de Bloqueio: Neutralização Reativa Imediata
* **Decisão Proposta:** A garantia técnica para operações detectadas durante o estado `BLOCKED` é formalmente definida como **Neutralização Reativa**.
* **Fundamentação:** Em MQL5 nativo puro (sem DLLs invasivas no sistema operacional), o terminal despacha ordens manuais diretamente ao servidor sem consultar o EA. Quando a notificação da transação chega via `OnTradeTransaction`, o EddyTrader reage emitindo requisição a mercado de encerramento (`PositionClose`) ou cancelamento (`OrderDelete`).
* **Correção de Evidência:** A arquitetura suporta a neutralização reativa, mas a **latência real** entre a execução externa, a entrega do evento ao EA e a confirmação pelo servidor **permanece não medida** até a realização de testes com conta Demo ativa.

### 2.3. Fechamento Universal por Ticket de Posição
* **Decisão Proposta:** A liquidação compulsória opera **estritamente por ticket individual da posição** (`CTrade::PositionClose(ulong ticket)`), precedida pela coleta estável dos tickets em array estático.
* **Fundamentação:** Em contas *Retail Hedging*, fechar por símbolo gera ambiguidade ou fecha a posição errada. O fechamento por ticket funciona de forma 100% idêntica e determinística tanto em *Netting* quanto em *Hedging*. A coleta prévia em array isola o laço do deslocamento dinâmico de índices de `PositionsTotal()`.

### 2.4. Referência do Relógio Oficial do Servidor de Negociação
* **Decisão Proposta:** A referência temporal do sistema é obtida através de **`TimeTradeServer()`**.
* **Fundamentação e Riscos:** `TimeCurrent()` congela no horário do último tick e para completamente quando o mercado fecha. `TimeTradeServer()` calcula a hora estimada do servidor no cliente adicionando o tempo transcorrido no relógio local da máquina. Como depende das configurações de relógio do host, a W06 deve prever mecanismos defensivos para controle da duração das 4 horas (ex: combinação com contador monotônico local).

### 2.5. Periodicidade Sub-Segundo via Timer
* **Decisão Proposta:** A avaliação periódica de alta frequência (500 ms) para avanço do relógio e retentativas de liquidação adotará **`EventSetMillisecondTimer(500)`**, uma vez que `EventSetTimer()` opera exclusivamente com granularidade de segundos inteiros.

### 2.6. Persistência Mínima via Global Variables (GAP-005)
* **Decisão Proposta:** O conjunto conceitual mínimo $\mathbf{D}_{\text{min\_recovery}} = \{ \text{current\_state}, \text{protection\_event\_id}, J_n, B_n, t_{\text{trigger}}, t_{\text{unlock}} \}$ será armazenado através das **Global Variables do Terminal MT5** (`GlobalVariableSet`, `GlobalVariablesFlush`) com chave prefixada por login (`EDDY_<LOGIN>_<VAR>`).
* **Fundamentação:** A reconstrução puramente nativa a partir do histórico de deals é tecnicamente inviável, pois o MT5 não registra quando ocorreu uma reabertura de risco ($t_{\text{reopen}}$), impossibilitando derivar a baseline $B_n$ ($n \ge 1$) pós-restart. A capacidade técnica do mecanismo de Global Variables foi comprovada localmente em `persistence_probe.mq5`, permanecendo a validação do ciclo de vida integrado para a W06.

---

## 3. Consequências e Medidas de Proteção para a W06

* **O que avança com segurança:**
  * Arquitetura da FSM em 6 estados conceituais;
  * Modelo matemático de janelas $W_n(t) = D(t) - B_n$;
  * Inventário global desacoplado por tickets;
  * Mecanismo de persistência leve via Global Variables.
* **O que deve ser protegido por guards defensivos:**
  * O EA não deve assumir ordem estrita em `OnTradeTransaction`;
  * O EA não deve assumir liquidação instantânea sem tolerância a slippage;
  * O EA deve permanecer estritamente em `LIQUIDATING` enquanto `PositionsTotal() > 0`, agendando retentativas via `OnTimer`;
  * Testes empíricos em Conta Demo (`DEMO-01` a `DEMO-08`) devem ser executados no início da W06 assim que houver credencial funcional disponível.

---

## 4. Rastreabilidade Documental

* Spike Técnico: [12 — Spike Técnico MT5](file:///C:/Projetos/eddytrader/docs/12-SPIKE-TECNICO-MT5.md)
* FSM Normativa: [11 — Máquina de Estados](file:///C:/Projetos/eddytrader/docs/11-MAQUINA-DE-ESTADOS.md)
* Modelo Matemático: [10 — Especificação Matemática](file:///C:/Projetos/eddytrader/docs/10-ESPECIFICACAO-MATEMATICA.md)
* Catálogo de Riscos: [08 — Riscos e Questões Abertas](file:///C:/Projetos/eddytrader/docs/08-RISCOS-E-QUESTOES-ABERTAS.md)
* Roadmap do Projeto: [09 — Roadmap](file:///C:/Projetos/eddytrader/docs/09-ROADMAP.md)
