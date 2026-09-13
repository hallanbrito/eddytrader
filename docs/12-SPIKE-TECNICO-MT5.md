# 12 — Spike Técnico MT5/MQL5: Garantias, Eventos, Liquidação, Bloqueio e Recuperação

Este documento formaliza as conclusões, evidências empíricas, documentais e de compilação levantadas durante a **W05 — Spike Técnico MT5/MQL5** do projeto **EddyTrader**, confrontando as decisões conceituais estabelecidas nas etapas W01 a W04 com o comportamento real e documentado da plataforma MetaTrader 5 (MT5) e da linguagem MQL5.

---

## 1. Contexto do Ambiente de Experimentação e Nível de Evidência

Para garantir rigor metodológico e aderência incondicional ao **Método C.H.**, este relatório diferencia explicitamente quatro níveis de evidência:

1. **Evidência Documental Oficial:** Especificações normativas da MetaQuotes / MQL5 Reference.
2. **Evidência de Compilação:** Validação sintática e de tipos no compilador oficial MetaEditor 64 (build 6193).
3. **Evidência Local sem Sessão Remota:** Execução de rotinas locais no terminal cliente sem tráfego de ordens para corretora.
4. **Evidência Empírica com Conta Demo Ativa:** Execução de ordens reais, recepção de transações comerciais em rede e retorno de retcodes do servidor.

### Dados do Ambiente Local
* **Terminal MT5 Desktop:** MetaTrader 5 x64 build 6193 (MetaQuotes Ltd.).
* **Sistema Operacional do Host:** Windows 11 build 26200, AMD Ryzen 7 5700U, AVX2, 16 GB RAM.
* **Caminho do Terminal:** `C:\Program Files\MetaTrader 5\terminal64.exe`
* **Caminho do Compilador:** `C:\Program Files\MetaTrader 5\metaeditor64.exe`
* **Diretório de Dados da Instância:** `C:\Users\dmnde\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075`
* **Compilação dos Probes:** **100% dos probes MQL5 compilados com 0 erros e 0 warnings**.
* **Estado da Sessão Remota:** A tentativa de autenticação em conta de laboratório `HonorProMU-Demo` retornou `Invalid account`. Nenhuma sessão remota com servidor de negociação estava autenticada.
* **Impacto Metodológico:** Nenhuma hipótese que dependa do envio de ordens ao servidor, preenchimento de mercado, medição de latência em rede ou recebimento de retcodes remotos foi promovida a "confirmada empiricamente". Tais hipóteses permanecem formalmente catalogadas como `CONFIRMADA_DOCUMENTALMENTE` ou `INCONCLUSIVA_SEM_SESSAO_ATIVA`.

---

## 2. Matriz de Hipóteses Técnicas (TECH-01 a TECH-18)

A tabela a seguir discrimina detalhadamente as fontes, os resultados verificados e a classificação estrita para cada hipótese:

| ID | Hipótese Técnica Investigada | Documentação Oficial | Compilação MetaEditor 64 | Execução Local | Sessão Demo Ativa | Classificação Final |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **TECH-01** | `OnTradeTransaction` fornece dados atômicos e rastreáveis para ordens, negócios e posições, enquanto `OnTrade` é genérico e sem parâmetros. | Documentada a estrutura `MqlTradeTransaction` e múltiplos disparos por ação. Não há garantia de ordem estrita de chegada. | [`event_probe.mq5`](file:///C:/Projetos/eddytrader/research/w05/event_probe.mq5): 0 erros, 0 warnings. | Handlers carregáveis e sintaxe de eventos válida. | Ausente (`Invalid account`). Sequência real de rede não capturada. | **CONFIRMADA_DOCUMENTALMENTE** / **CONFIRMADA_POR_COMPILACAO** |
| **TECH-02** | O EA não intercepta ordens manuais antes do envio ao servidor; a garantia técnica é **neutralização reativa**. | Arquitetura MT5 não expõe hooks pré-envio para UI. Ordens manuais vão direto ao servidor. | [`event_probe.mq5`](file:///C:/Projetos/eddytrader/research/w05/event_probe.mq5): 0 erros, 0 warnings. | Ausência de APIs de interceptação prévia no SDK nativo. | Ausente. Latência de rede e confirmação de encerramento não medidas. | **CONFIRMADA_DOCUMENTALMENTE** (prevenção impossível); **INCONCLUSIVA_SEM_SESSAO_ATIVA** (latência real de neutralização). |
| **TECH-03** | Enumeração de 100% das posições abertas na conta (escopo global sem filtro de ativo ou Magic). | Funções `PositionsTotal()` e `PositionGetTicket(i)` atuam sobre a totalidade da conta. | [`account_probe.mq5`](file:///C:/Projetos/eddytrader/research/w05/account_probe.mq5): 0 erros, 0 warnings. | Chamadas executadas sem erro retornando 0 posições. | Ausente. Não testada com múltiplas posições reais concorrentes. | **CONFIRMADA_DOCUMENTALMENTE** / **CONFIRMADA_POR_COMPILACAO** |
| **TECH-04** | Enumeração de 100% das ordens pendentes ativas na conta de forma global. | Funções `OrdersTotal()` e `OrderGetTicket(j)` leem todas as ordens ativas da conta. | [`account_probe.mq5`](file:///C:/Projetos/eddytrader/research/w05/account_probe.mq5): 0 erros, 0 warnings. | Chamadas executadas sem erro retornando 0 ordens. | Ausente. Não testada com ordens pendentes reais. | **CONFIRMADA_DOCUMENTALMENTE** / **CONFIRMADA_POR_COMPILACAO** |
| **TECH-05** | Liquidação global e cancelamento desacoplados por ticket com isolamento de falha individual. | `CTrade::PositionClose(ulong ticket)` e `CTrade::OrderDelete(ulong ticket)`. | [`liquidation_probe.mq5`](file:///C:/Projetos/eddytrader/research/w05/liquidation_probe.mq5): 0 erros, 0 warnings. | Algoritmo de coleta em array e loop desacoplado compilado. | Ausente. Nenhuma ordem real emitida para fechamento a mercado. | **CONFIRMADA_DOCUMENTALMENTE** / **CONFIRMADA_POR_COMPILACAO** |
| **TECH-06** | Retail Netting: no máximo uma posição agregada por símbolo. | Especificação oficial de contas Netting / Exchange. | [`account_probe.mq5`](file:///C:/Projetos/eddytrader/research/w05/account_probe.mq5): 0 erros, 0 warnings. | Constante `ACCOUNT_MARGIN_MODE_RETAIL_NETTING` reconhecida. | Ausente. Não validada em conta Netting conectada. | **CONFIRMADA_DOCUMENTALMENTE** |
| **TECH-07** | Retail Hedging: posições concorrentes no mesmo símbolo exigem fechamento estrito por ticket. | Especificação oficial de contas Hedging (`POSITION_IDENTIFIER`). | [`liquidation_probe.mq5`](file:///C:/Projetos/eddytrader/research/w05/liquidation_probe.mq5): 0 erros, 0 warnings. | Chamada por ticket individual compilada sem ambiguidade. | Ausente. Não testada em conta Hedging conectada. | **CONFIRMADA_DOCUMENTALMENTE** / **CONFIRMADA_POR_COMPILACAO** |
| **TECH-08** | Mercado fechado e falhas comerciais retornam retcodes; sistema retém em `LIQUIDATING`. | Códigos `TRADE_RETCODE_MARKET_CLOSED` (10018), `TRADE_RETCODE_OFF_QUOTES` (10016). | [`liquidation_probe.mq5`](file:///C:/Projetos/eddytrader/research/w05/liquidation_probe.mq5): 0 erros, 0 warnings. | Mapeamento de retcodes e guarda de resíduo verificados. | Ausente. Não foi recebido retcode 10018 real de servidor. | **PARCIALMENTE_CONFIRMADA** (tratamento arquitetural definido; teste em servidor pendente). |
| **TECH-09** | Referência temporal: `TimeTradeServer()` vs `TimeCurrent()`. | Docs: `TimeCurrent()` é o último tick; `TimeTradeServer()` é a hora calculada do servidor estimada no cliente. | [`env_probe.mq5`](file:///C:/Projetos/eddytrader/research/w05/env_probe.mq5), [`account_probe.mq5`](file:///C:/Projetos/eddytrader/research/w05/account_probe.mq5): 0 erros. | Ambas as funções invocadas e comparadas localmente. | Ausente. Ticks contínuos de servidor não recebidos. | **CONFIRMADA_DOCUMENTALMENTE** (diferença conceitual); **INCONCLUSIVA_SEM_SESSAO_ATIVA** (precisão da estimativa local). |
| **TECH-10** | Derivação contábil de $R_{\text{day}}(t)$ excluindo movimentações de capital. | `HistorySelect`, `DEAL_TYPE_BALANCE` (capital), `DEAL_PROFIT`, `DEAL_COMMISSION`, `DEAL_SWAP`, `DEAL_FEE`. | [`history_probe.mq5`](file:///C:/Projetos/eddytrader/research/w05/history_probe.mq5): 0 erros, 0 warnings. | Algoritmo de filtragem e soma de custos compilado. | Ausente. Histórico contábil real de corretora não consultado. | **CONFIRMADA_DOCUMENTALMENTE** / **CONFIRMADA_POR_COMPILACAO** |
| **TECH-11** | Flutuante líquido $F(t)$ consolidado da conta sem sobreposição. | `AccountInfoDouble(ACCOUNT_PROFIT)` e soma de posições abertas. | [`account_probe.mq5`](file:///C:/Projetos/eddytrader/research/w05/account_probe.mq5): 0 erros, 0 warnings. | Chamadas de API compiladas e estruturadas. | Ausente. Flutuante de posições abertas reais não observado. | **CONFIRMADA_DOCUMENTALMENTE** / **CONFIRMADA_POR_COMPILACAO** |
| **TECH-12** | Histórico nativo MT5 é estável e consultável deterministicamente. | `HistorySelect(t_start, t_end)` e `bases\<server>\history`. | [`history_probe.mq5`](file:///C:/Projetos/eddytrader/research/w05/history_probe.mq5): 0 erros, 0 warnings. | Invocação local de `HistorySelect` executada. | Ausente. Sem negócios históricos no servidor de teste. | **CONFIRMADA_DOCUMENTALMENTE** / **CONFIRMADA_POR_COMPILACAO** |
| **TECH-13** | Variáveis em memória RAM do EA são destruídas no unload / restart do terminal. | Ciclo de vida MQL5: variáveis globais do programa residem em memória volátil de processo. | [`persistence_probe.mq5`](file:///C:/Projetos/eddytrader/research/w05/persistence_probe.mq5): 0 erros, 0 warnings. | Confirmado pelo modelo de execução e documentação do MQL5. | Independe de corretora. | **CONFIRMADA_DOCUMENTALMENTE** / **CONFIRMADA_LOCALMENTE** |
| **TECH-14** | Global Variables do Terminal sobrevivem a restart e armazenam valores numéricos. | Documentação `GlobalVariableSet`, `GlobalVariableGet`, `GlobalVariablesFlush`, arquivo `gvars.dat`. | [`persistence_probe.mq5`](file:///C:/Projetos/eddytrader/research/w05/persistence_probe.mq5): 0 erros, 0 warnings. | Gravação e leitura validadas no terminal local. | Independe de corretora. | **CONFIRMADA_DOCUMENTALMENTE** / **CONFIRMADA_LOCALMENTE** |
| **TECH-15** | Arquivo binário em `MQL5/Files` permite armazenar structs fortemente tipadas. | Funções `FileOpen`, `FileWriteStruct`, `FileReadStruct`, `FileFlush`. | [`persistence_probe.mq5`](file:///C:/Projetos/eddytrader/research/w05/persistence_probe.mq5): 0 erros, 0 warnings. | Escrita e leitura de struct na sandbox local validadas. | Independe de corretora. | **CONFIRMADA_DOCUMENTALMENTE** / **CONFIRMADA_LOCALMENTE** |
| **TECH-16** | Baseline $B_n$ ($n \ge 1$) NÃO pode ser inferida apenas do histórico nativo após restart. | MT5 não cataloga eventos nem timestamps de desbloqueio intradiário de risco. | [`history_probe.mq5`](file:///C:/Projetos/eddytrader/research/w05/history_probe.mq5), [`persistence_probe.mq5`](file:///C:/Projetos/eddytrader/research/w05/persistence_probe.mq5): 0 erros. | Prova lógica: sem persistência de $B_n$, o EA reassume $B=0$ e causa falso rebloqueio. | Independe de corretora. | Hipótese de reconstrução puramente nativa: **REFUTADA**. Persistência necessária: **CONFIRMADA_DOCUMENTALMENTE**. |
| **TECH-17** | `protection_event_id` é estado próprio do EddyTrader sem equivalente nativo. | Estruturas de deals, orders e positions não contêm identificadores de travas de risco. | [`persistence_probe.mq5`](file:///C:/Projetos/eddytrader/research/w05/persistence_probe.mq5): 0 erros, 0 warnings. | Ausência de campo nativo constatada na API. | Independe de corretora. | **CONFIRMADA_DOCUMENTALMENTE** / **CONFIRMADA_LOCALMENTE** |
| **TECH-18** | `window_id` ($J_n$) precisa ser mantido pelo robô para controle das baselines. | MT5 não segmenta o histórico diário em janelas intradiárias operacionais. | [`persistence_probe.mq5`](file:///C:/Projetos/eddytrader/research/w05/persistence_probe.mq5): 0 erros, 0 warnings. | Ausência de segmentação nativa constatada. | Independe de corretora. | **CONFIRMADA_DOCUMENTALMENTE** / **CONFIRMADA_LOCALMENTE** |

---

## 3. Análise Detalhada das Conclusões e Correções Críticas

### 3.1. Garantia Oficial de `OnTradeTransaction`: Ausência de Ordem Rígida (TECH-01)
A documentação oficial da MetaQuotes estabelece expressamente:
1. Uma única solicitação comercial pode produzir **múltiplas chamadas consecutivas** a `OnTradeTransaction` (`TRADE_TRANSACTION_REQUEST`, `TRADE_TRANSACTION_ORDER_ADD`, `TRADE_TRANSACTION_DEAL_ADD`, `TRADE_TRANSACTION_ORDER_DELETE`, etc.).
2. **A ordem de chegada dessas transações ao terminal cliente NÃO é estritamente garantida pela rede**, devido ao processamento assíncrono e eventuais retransmissões de pacotes TCP.
3. **Consequência Arquitetural para a W06:** O EddyTrader **não pode depender de uma máquina de estados rígida acoplada à sequência presumida de eventos** de `OnTradeTransaction`. O robô deve usar a transação comercial apenas como gatilho de notificação de alta prioridade, reconciliando o estado real através do **inventário efetivo da conta** (`PositionsTotal` e `OrdersTotal`).

---

### 3.2. Correção sobre a Latência de Bloqueio (TECH-02)
Na execução anterior afirmou-se que a neutralização ocorreria "no mesmo milissegundo". **Essa afirmação foi corrigida**:
* Não houve teste empírico com conta conectada e tráfego de rede para medir os tempos reais de execução.
* **Conclusão Técnica Real:**
  > A arquitetura da plataforma suporta **neutralização reativa** após o recebimento do evento correspondente. A latência real entre a execução manual externa, a notificação ao EA, o envio da requisição de neutralização e a confirmação de encerramento pelo servidor **permanece NÃO MEDIDA** no ambiente atual.

A medição quantitativa precisa dessa latência foi formalmente catalogada como teste pendente em Conta Demo ([DEMO-03](#5-validação-empírica-em-conta-demo-testes-preparados)).

---

### 3.3. Relógio do Servidor: `TimeTradeServer()` vs `TimeCurrent()` (TECH-09)
A documentação oficial define com exatidão a semântica das duas funções:
* **`TimeCurrent()`:** Retorna o último horário conhecido do servidor, correspondente ao timestamp do último tick registrado no Market Watch. Se o mercado estiver fechado ou sem liquidez, o valor congela.
* **`TimeTradeServer()`:** Retorna o horário atual calculado do servidor de negociação. O terminal calcula esse horário adicionando o tempo transcorrido no relógio local do computador desde a última sincronização com o servidor.
* **Risco Operacional Identificado:** Se o relógio do computador local do operador estiver dessincronizado, descalibrado ou sofrer alterações manuais enquanto a conexão estiver suspensa, `TimeTradeServer()` pode apresentar desvio em relação ao tempo real do servidor da corretora.
* **Recomendação para a W06:** Preservar normativamente o horário do servidor como referência de negócio, mas prever na arquitetura mecanismos defensivos para controle da duração das 4 horas (ex: combinação de carimbo do servidor com controle monotônico de tempo decorrido via contador local `GetTickCount64()`), protegendo o operador contra eventuais anomalias de relógio local.

---

### 3.4. Periodicidade de Timer Sub-Segundo na W06
A recomendação técnica para a W06 sugere um timer periódico de alta frequência (500 ms) para avançar o relógio soberano, persistir retentativas de liquidação e conferir desbloqueio de janelas.
* Em MQL5, `EventSetTimer(seconds)` aceita apenas granularidade em **segundos inteiros**.
* **Correção Técnica:** Para obter periodicidade sub-segundo de 500 ms, a W06 deverá obrigatoriamente invocar **`EventSetMillisecondTimer(500)`** e tratar a liberação correspondente via `EventKillTimer()` no `OnDeinit`.

---

### 3.5. Resolução do GAP-005 e Persistência Técnica
O GAP-005 foi reavaliado quanto ao nível de certeza:
1. **Capacidade do Mecanismo Técnico (Validada):** Ficou comprovado que o histórico nativo do MT5 não registra baselines intradiárias anteriores ($B_n$), inviabilizando a reconstrução pura sem persistência própria. As **Global Variables do Terminal MT5** foram validadas no ambiente local (`persistence_probe.mq5`) como mecanismo nativo capaz de armazenar valores numéricos com persistência em `gvars.dat`.
2. **Integração no Produto Real (Pendente para W06):** A definição do esquema definitivo das chaves, o tratamento de atomicidade lógica durante o ciclo de vida completo do EddyTrader e a validação ponta a ponta com restart em mercado ativo serão demonstrados durante a implementação da W06.

---

## 4. Status das Decisões de Projeto (DQs) e GAPs

* **GAP-005 (Persistência e Reconstrução pós-Restart):** **RESOLVIDO QUANTO AO MECANISMO TÉCNICO** (adoção formal de Global Variables do Terminal com `GlobalVariablesFlush()`; validação integrada do ciclo de vida transferida para a W06).
* **DQ-001 (Mecanismo de Bloqueio no MT5):** **RESOLVIDA DOCUMENTALMENTE** (prevenção prévia impossível; neutralização reativa adotada normativamente; latência prática pendente de medição em Demo).
* **DQ-002 (Netting vs Hedging):** **RESOLVIDA DOCUMENTALMENTE** (fechamento universal estritamente por `POSITION_TICKET`).
* **DQ-004 (Tratamento de Mercado Fechado):** **PARCIALMENTE RESOLVIDA** (tratamento arquitetural e retcodes mapeados no código do probe; comportamento com servidor remoto pendente de validação empírica em Demo).
* **DQ-005 (Instância Única por Conta):** **RESOLVIDA DOCUMENTALMENTE / LOCALMENTE** (guarda via flag em Global Variable com prefixo por login).
* **DQ-003 (Slippage / Deviation em Fechamento):** **ADIADA PARA W06** (parametrização do desvio máximo em pontos nas chamadas comerciais).

---

## 5. Validação Empírica em Conta Demo (Testes Preparados)

Para quando uma conta Demo estiver devidamente autenticada no terminal MT5, ficam formalmente preparados os seguintes procedimentos de teste empírico:

* **`DEMO-01` — Ordem manual durante estado `BLOCKED`:** Abrir ordem a mercado manualmente via terminal e verificar se o probe detecta e fecha a operação.
* **`DEMO-02` — Medição da sequência de `OnTradeTransaction`:** Registrar no log a ordem exata de chegada das microtransações geradas por uma operação comercial.
* **`DEMO-03` — Medição de latência real de neutralização:** Calcular em microssegundos o intervalo entre o timestamp de notificação do deal e a confirmação do fechamento pelo servidor.
* **`DEMO-04` — Fechamento de múltiplas posições reais:** Abrir 3 ou mais posições simultâneas (em ativos distintos) e validar o encerramento completo pelo laço desacoplado por ticket.
* **`DEMO-05` — Cancelamento de ordens pendentes reais:** Criar ordens Buy Limit / Sell Stop e validar a remoção total por `OrderDelete`.
* **`DEMO-06` — Produção de falha real e retcode do servidor:** Tentar fechar posição em ativo com mercado fechado ou volume irregular e confirmar captura de `TRADE_RETCODE_MARKET_CLOSED` (10018) ou `TRADE_RETCODE_INVALID_VOLUME` (10014).
* **`DEMO-07` — Restart do terminal com estado persistido:** Forçar o encerramento do processo `terminal64.exe` durante simulação de `BLOCKED` e verificar restauração correta de $\mathbf{D}_{\text{min\_recovery}}$ no `OnInit`.
* **`DEMO-08` — Validação do modo de margem disponível:** Confirmar o comportamento contábil no modo específico da conta conectada (Netting ou Hedging).

---

## 6. O que Está Seguro para Iniciar a W06 vs o que Permanece Protegido por Guards

### O que já é Suficientemente Seguro para Iniciar a W06
1. **Estrutura da Máquina de Estados:** Estados `INIT`, `MONITORING`, `PROTECTION_TRIGGERED`, `LIQUIDATING`, `BLOCKED` e `REOPENING`.
2. **Modelo Matemático:** Fórmulas $D(t) = R_{\text{day}}(t) + F(t)$ e $W_n(t) = D(t) - B_n$, com exclusão de `DEAL_TYPE_BALANCE`.
3. **Estratégia de Liquidação por Ticket:** Varredura global via `PositionsTotal()` e fechamento exclusivo por `PositionClose(ulong ticket)`.
4. **Desacoplamento de Índices:** Coleta prévia de tickets em array estático antes de iniciar requisições de fechamento.
5. **Mecanismo de Persistência Base:** Utilização de Global Variables com prefixo por login (`EDDY_<LOGIN>_`) e `GlobalVariablesFlush()`.
6. **Compilabilidade Estrita:** Código 100% aderente aos padrões MQL5 do compilador MetaEditor 64 (build 6193).

### O que NÃO pode ser tratado como garantia absoluta (Exige Guards Defensivos)
1. **Sequência de Eventos:** O EA não pode assumir que as transações chegam ordenadas; o estado real deve ser conferido pelo inventário da conta.
2. **Imediatismo de Fechamento:** O EA deve assumir que o fechamento a mercado pode sofrer slippage, rejeição ou requote; transição para `BLOCKED` exige conferência de resíduo zero.
3. **Disponibilidade Contínua de Mercado:** Se um ativo estiver fechado, o robô deve permanecer em `LIQUIDATING` e retentar nos ciclos subsequentes via `OnTimer`.
4. **Sincronia Estrita de Relógio:** O cálculo das 4 horas deve proteger-se contra anomalias de fuso ou relógio local do computador.
