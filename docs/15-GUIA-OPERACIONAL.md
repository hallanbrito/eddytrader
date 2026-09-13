# 15 — Guia Operacional do EddyTrader

> **Versão:** 1.0.0-rc1 (Release Candidate)  
> **Status:** Homologado com Ressalvas (Pendente Validação `LIVE-01` em Conta Demo com Pregão Aberto)  
> **Público-Alvo:** Operadores, Gestores de Risco e Administradores de Plataforma MetaTrader 5

---

## 1. Visão Geral e Filosofia do Produto

O **EddyTrader** é um gerenciador de risco operacional autônomo desenvolvido nativamente em **MQL5 puro** para a plataforma **MetaTrader 5 (MT5)**.

### Propósito Exclusivo
Sua única atribuição é monitorar continuamente o resultado financeiro consolidado da conta e, caso a perda atinja o limite máximo diário parametrizado pelo operador, executar a liquidação compulsória imediata de todas as posições abertas, cancelar ordens pendentes e manter a conta sob bloqueio operacional contínuo por **4 horas**, reabrindo posteriormente sob uma nova baseline matemática que impede o rebloqueio indevido.

### O que o EddyTrader NÃO É (Limites Rígidos)
* **Não é estratégia de trading:** não abre posições, não analisa tendências, não gera sinais operacionais e não escolhe ativos;
* **Não define stops discricionários:** não posiciona Stop Loss individual ou Take Profit por ordem;
* **Não busca metas de ganho:** não encerra operações por alcance de lucro financeiro (*Take Profit global*);
* **Não utiliza dependências externas:** opera 100% no cliente MT5 sem DLLs, banco de dados externo, Python, servidores intermediários, WebRequests ou robôs de mensageria (Telegram/Discord).

---

## 2. Requisitos de Ambiente e Dependências Operacionais

| Requisito | Especificação Normativa |
| :--- | :--- |
| **Plataforma** | MetaTrader 5 Desktop (64-bit), build 4000 ou superior (testado e homologado no build 6193). |
| **Linguagem** | MQL5 Nativo puro (compilado via MetaEditor 64-bit). |
| **Tipo de Conta** | Suporte total e idêntico a contas **Retail Netting** e **Retail Hedging**. |
| **Ambiente de Conta** | Compatível com contas **Demo** e **Real** (requer homologação em Demo prévia). |
| **Permissões MT5** | **Algo Trading** deve estar ativado no terminal e nas propriedades do EA. |
| **Execução do Processo** | Requer que o terminal `terminal64.exe` esteja em execução na máquina do operador. |

> [!IMPORTANT]
> **Dependência de Execução Local:**  
> Como Expert Advisor nativo, o EddyTrader somente atua enquanto o terminal MetaTrader 5 estiver aberto, conectado e com o EA carregado no gráfico. Se o computador for desligado ou o terminal encerrado, nenhuma ordem poderá ser cancelada ou neutralizada durante o período de inatividade. Ao reabrir o terminal, o sistema recupera automaticamente todo o estado persistido e reconcilia a situação da conta.

---

## 3. Instalação Passo a Passo

1. **Obtenção do Binário ou Código Fonte:**
   * Arquivo executável: `EddyTrader.ex5` (ou código fonte `EddyTrader.mq5`).
2. **Cópia para a Pasta de Experts:**
   * No MetaTrader 5, acesse o menu superior: **Arquivo -> Abrir Pasta de Dados**.
   * Navegue até o diretório: `MQL5\Experts\`.
   * Cole o arquivo `EddyTrader.ex5` (ou `EddyTrader.mq5`) nesta pasta.
3. **Compilação (se utilizando o código fonte):**
   * Abra o MetaEditor (tecla `F4`), localize `EddyTrader.mq5` e pressione `F7` para compilar.
   * Certifique-se de que a compilação concluiu com **0 errors, 0 warnings**.
4. **Atualização no Navegador:**
   * Na janela **Navegador** do MT5 (`Ctrl+N`), clique com o botão direito sobre **Expert Advisors** e selecione **Atualizar**.
5. **Anexação ao Gráfico:**
   * Abra qualquer gráfico de qualquer ativo e qualquer período gráfico (sugestão: `EURUSD` ou `WIN`, M1).
   * Arraste o `EddyTrader` para o gráfico.
   * **ATENÇÃO:** Anexe o EddyTrader a **apenas um único gráfico da conta**. A proteção atua sobre 100% dos ativos da conta independentemente do gráfico onde estiver anexado.
6. **Habilitação de Negociação Algorítmica:**
   * Na aba **Comum** da janela de propriedades, marque a caixa **"Permitir Algo Trading"**.
   * No botão superior da barra de ferramentas do MT5, certifique-se de que o botão **Algo Trading** esteja com o ícone verde (ativado).

---

## 4. Guarda de Instância Única por Conta

Para evitar split-brain, conflitos concorrentes ou duplicação de ordens de fechamento caso o operador anexe inadvertidamente o robô em múltiplos gráficos:

1. **Exclusão Mútua por Login:** O EddyTrader implementa uma guarda atômica por conta baseada no protocolo **OWNER + HEARTBEAT** via primitivas Compare-And-Swap (CAS) em Global Variables (`EDDY_<LOGIN>_OWNER`).
2. **Rejeição Automática:** Apenas a primeira instância obtém a titularidade da conta. Qualquer segunda instância anexada em outro gráfico detecta o proprietário ativo e é sumariamente rejeitada durante o `OnInit()`, emitindo `INIT_FAILED` e descarregando sem interferir no monitoramento.
3. **Assunção Pós-Queda (*Takeover* após 15s):** Caso a instância titular trave ou o gráfico seja fechado sem liberação limpa, após 15 segundos (`INSTANCE_LEASE_TIMEOUT_SECONDS = 15`) de ausência de batimento (*heartbeat*), uma nova instância carregada assume a propriedade da conta de forma limpa e atômica.
4. **Contenção Fail-Closed para Zumbis:** Se uma instância anterior acordar de um travamento temporário após ter sido substituída, ela detecta a perda de posse, desarma o timer e entra imediatamente em postura `FAIL-CLOSED`, sem liquidar ativos e sem corromper as variáveis da nova instância ativa.

---

## 5. Configuração dos Parâmetros de Entrada (`Inputs`)

Ao anexar o EA ou pressionar `F7` no gráfico, configure os parâmetros conforme o plano de gerenciamento de risco:

```mql5
input group "=== Configurações de Risco ==="
input double InpMaxLoss            = 500.0; // Perda Máxima Permitida por Janela (Moeda da Conta, > 0.0)
input int    InpBlockDurationHours = 4;     // Duração Contínua do Bloqueio (Horas, 1 a 168h)

input group "=== Configurações Operacionais ==="
input int    InpTimerIntervalMs    = 500;   // Intervalo de Varredura do Timer (Milissegundos, 50 a 5000)
input ulong  InpDeviationPoints    = 10;    // Desvio Máximo / Slippage Tolerado (Pontos, 0 a 500)
```

### Detalhamento dos Campos
* **`InpMaxLoss` (Default: `500.0`):**
  * Limite monetário de perda para disparo compulsório da proteção na janela corrente.
  * Expressa obrigatoriamente na **moeda base da conta** (ex: BRL em contas brasileiras, USD em contas internacionais).
  * Exemplo: configurado como `500.0`, a proteção será disparada compulsoriamente quando o resultado da janela $W_n(t) \le -500.00$.
* **`InpBlockDurationHours` (Default: `4`):**
  * Duração contínua e ininterrupta do bloqueio operacional a contar do instante do disparo ($t_{\text{unlock}} = t_{\text{trigger}} + \text{Horas} \times 3600$).
  * Valor normativo de homologação: **4 horas**.
* **`InpTimerIntervalMs` (Default: `500`):**
  * Frequência do pulso de alta precisão via `EventSetMillisecondTimer`.
  * Permite que o EA inspecione o avanço do relógio e o resultado da conta 2 vezes por segundo mesmo em momentos de calmaria sem ticks de cotação. Faixa operacional: 50 a 5000 ms.
* **`InpDeviationPoints` (Default: `10`):**
  * Tolerância de slippage/desvio em pontos enviada nas requisições compulsórias de `PositionClose`.

---

## 6. Estados Operacionais da FSM e Interface Visual (HUD)

O EddyTrader projeta um painel informativo textual diretamente no canto superior esquerdo do gráfico via função `Comment()`:

```text
====================================================
 EddyTrader v1.0.0-rc1 - Release Candidate 1
 Gerenciador de Risco Operacional e Limite de Perda Diária (MQL5 Nativo)
====================================================
 Conta: 6272676 | Modo: DEMO | Servidor: ActivTradesCorp-Server
 Instância: #1788220800502530 (Owner: SIM)
 Horário Servidor: 2026.09.13 14:35:10
----------------------------------------------------
 Estado FSM: MONITORING
 Janela Ativa: J0 | Baseline (Bn): 0.00
 Perda Máxima Permitida (L): -500.00
----------------------------------------------------
 R_day (Realizado Hoje):    -120.00 USD
 F(t)  (Flutuante Líquido):  -85.50 USD
 D(t)  (Consolidado Hoje):  -205.50 USD
 W_n(t)(Resultado Janela):  -205.50 USD
----------------------------------------------------
 Status de Proteção: NOMINAL / VIGILANTE
 ID do Evento: 0
 Informação de Bloqueio: Nenhum bloqueio ativo
 Posições Abertas: 2 | Ordens Pendentes: 0
 Negociação Autorizada: SIM (NOMINAL)
====================================================
```

### Significado dos Estados da Máquina de Estados (FSM)
1. **`INIT` (Inicialização / Estado Transitório):**
   * Estado transitório de partida. Inspeciona a persistência, valida a baseline da janela e confere as condições da conta. Se os dados forem inconsistentes, retém a operação bloqueada (`safe_to_operate = false`).
2. **`MONITORING` (Vigilância Ativa de Risco):**
   * Estado nominal. O operador possui autorização para negociar. O EA calcula continuamente $W_n(t) = D(t) - B_n$ e compara com $-L$.
3. **`PROTECTION_TRIGGERED` (Formalização do Gatilho):**
   * A perda violou o limite ($W_n \le -L$). O sistema congela o timestamp $t_{\text{trigger}}$, calcula $t_{\text{unlock}} = t_{\text{trigger}} + 4\text{h}$, gera o ID idempotente do evento, grava em disco e transita para liquidação.
4. **`LIQUIDATING` (Contenção e Liquidação Compulsória Global):**
   * Emite ordens a mercado para fechar 100% das posições abertas e cancela todas as ordens pendentes. Se restar qualquer resíduo (ex: mercado fechado), permanece retido retentando a cada 500 ms.
5. **`BLOCKED` (Bloqueio Temporal Contínuo):**
   * Todas as posições e ordens foram zeradas. O sistema proíbe qualquer operação até $t \ge t_{\text{unlock}}$. Se novas ordens forem abertas manualmente pelo usuário no terminal, o EA as neutraliza reativamente em tempo real.
6. **`REOPENING` (Reabertura Controlada e Nova Baseline):**
   * Transcorridas as 4 horas ($t \ge t_{\text{unlock}}$) e satisfeitas as condições de segurança (`PositionsTotal == 0`, ordens zeradas e conexão ativa), captura a nova baseline $B_{n+1} = D(t_{\text{reopen}})$ e zera o resultado da nova janela ($W_{n+1} = 0$), conduzindo o sistema de volta a `MONITORING`.

### Distinção Normativa entre Estado FSM e Postura Fail-Closed
A FSM do EddyTrader possui exclusivamente os **6 estados normativos** descritos acima. **Não existe um 7º estado `FAILED`.**  
A **postura *fail-closed*** é uma condição operacional de segurança expressa pela flag `g_safe_to_operate = false`. Diante de qualquer anomalia crítica (ex: falha de escrita em `PersistState()`, ausência de baseline $B_n$ nas Global Variables em janelas intradiárias $J_{n \ge 1}$ ou indisponibilidade de timer):
* O EA **não** cria estados espúrios nem transições não autorizadas;
* O EA retém ou coloca o estado em `INIT` (ou preserva a contenção em `LIQUIDATING`/`BLOCKED`);
* A autorização de negociação é sumariamente negada (`safe_to_operate = false`);
* O painel HUD exibe o aviso visual `>>> ATENCAO: OPERACAO BLOQUEADA / FAIL-CLOSED <<<`;
* Logs estruturados com prefixo `[CRITICAL]` são emitidos no Diário do terminal.

---

## 7. Comportamento Operacional Detalhado

### 7.1. Vigilância Nominal (`MONITORING`)
* O resultado econômico consolidado do dia é apurado em tempo real:
  $$D(t) = R_{\text{day}}(t) + F(t)$$
  * $R_{\text{day}}(t)$: soma de lucros/prejuízos, swaps, comissões e taxas de todos os negócios de trading fechados no dia contábil atual (`00:00:00` às `23:59:59` do servidor). **Movimentações de capital (depósitos, saques e bônus) são estritamente excluídas.**
  * $F(t)$: lucro/prejuízo flutuante instantâneo de todas as posições abertas na conta obtido via `AccountInfoDouble(ACCOUNT_PROFIT)`.
* O resultado da janela operacional ativa $J_n$ é avaliado contra o limite:
  $$W_n(t) = D(t) - B_n \quad \text{com} \quad B_0 = 0.00$$

### 7.2. Acionamento da Proteção e Liquidação Compulsória
* No momento em que $W_n(t) \le -\text{InpMaxLoss}$:
  1. O estado transiciona imediatamente para `PROTECTION_TRIGGERED`.
  2. O carimbo oficial do relógio do servidor $t_{\text{trigger}}$ é congelado e o instante mínimo de liberação é fixado: $t_{\text{unlock}} = t_{\text{trigger}} + 4\text{h}$.
  3. O estado avança para `LIQUIDATING`.
  4. Todos os tickets de posições são coletados previamente em array e fechados individualmente por ticket via `PositionClose(ticket, InpDeviationPoints)`.
  5. Todas as ordens pendentes são canceladas via `OrderDelete(ticket)`.
  6. Se `PositionsTotal() == 0 && OrdersTotal() == 0`, transiciona para `BLOCKED`. Caso reste qualquer resíduo, o sistema permanece retido em `LIQUIDATING` persistindo nas retentativas a cada 500 ms.

### 7.3. Bloqueio de 4 Horas e Neutralização Reativa
* Durante o estado `BLOCKED`:
  * O EddyTrader exibe a contagem regressiva oficial até $t_{\text{unlock}}$.
  * **Neutralização de Intervenções Manuais:** A plataforma MetaTrader 5 nativa despacha ordens emitidas pelo operador diretamente ao servidor da corretora sem solicitar autorização prévia ao Expert Advisor. Para neutralizar qualquer tentativa de burla ou indisciplina do operador durante o bloqueio, o EddyTrader utiliza o manipulador `OnTradeTransaction`:
    * Ao detectar a execução de nova posição (`TRADE_TRANSACTION_DEAL_ADD`), emite imediatamente ordem de fechamento a mercado.
    * Ao detectar nova ordem pendente (`TRADE_TRANSACTION_ORDER_ADD`), emite cancelamento imediato.
  * **Invariante Temporal:** A detecção de intervenções manuais fecha a operação intrusa imediatamente, mas **não altera nem prorroga** o timestamp de liberação $t_{\text{unlock}}$ original.

### 7.4. Reabertura Formal pós-$t_{\text{unlock}}$ e Renovação da Baseline
* Quando o relógio do servidor alcançar $t \ge t_{\text{unlock}}$:
  * O sistema avalia `CheckSafetyConditions()`: confirma que não há posições abertas, não há ordens pendentes e o terminal está conectado.
  * Transiciona obrigatoriamente para `REOPENING`.
  * Incrementa o identificador da janela ($J_n \to J_{n+1}$).
  * Captura a baseline da nova janela fixando-a rigorosamente no resultado consolidado presente no instante do desbloqueio:
    $$B_{n+1} = D(t_{\text{reopen}})$$
  * Valida o invariante matemático:
    $$W_{n+1}(t_{\text{reopen}}) = D(t_{\text{reopen}}) - B_{n+1} \equiv 0.00$$
  * O sistema retorna para `MONITORING`. Como o resultado da nova janela inicia perfeitamente em $0.00$ (acima do limite $-L$), **o operador pode voltar a operar sem risco de falso rebloqueio imediato por perdas pretéritas**.

---

## 8. Tratamento da Virada de Dia (Meia-Noite `00:00:00`)

A rotina `CheckMidnightRollover()` monitora a virada do relógio do servidor de negociação:

1. **Virada de Dia em `MONITORING`:**
   * Se o sistema estiver em vigilância nominal, às `00:00:00` do servidor inicia-se um novo dia contábil.
   * O ciclo reinicia na janela diária inicial $J_0$ com baseline nominal:
     $$B_0 = 0.00$$
   * A baseline **nunca é substituída pela Equity da conta**. O resultado do novo dia parte estritamente do flutuante das posições que atravessaram a meia-noite somado aos novos negócios realizados.
2. **Virada de Dia Durante `BLOCKED` (ou `LIQUIDATING`):**
   * Se a proteção tiver sido disparada, por exemplo, às `22:30:00` (com liberação prevista para as `02:30:00` do dia seguinte):
   * A passagem das `00:00:00` atualiza o calendário contábil, mas **o bloqueio de 4 horas é preservado integralmente**.
   * O relógio de 4 horas **não é zerado nem reiniciado**. O desbloqueio ocorrerá pontualmente às `02:30:00` do novo dia.

---

## 9. Reinicialização do Terminal e Recuperação de Desastres

O EddyTrader persiste seu conjunto mínimo de recuperação $\mathbf{D}_{\text{min\_recovery}}$ nas **Global Variables do Terminal MT5**, que são salvas em disco de forma síncrona (`gvars.dat`):

* Chaves persistidas por login: `STATE`, `WINDOW_ID`, `BASELINE`, `T_TRIGGER`, `T_UNLOCK`, `EVENT_ID`, `DAY`, `INSTANCE_OWNER` e `HEARTBEAT`.

### Cenários de Recuperação pós-Restart
1. **Reinício durante `BLOCKED` com $t < t_{\text{unlock}}$:**
   * O EA recarrega o estado persistido, verifica que o tempo restante ainda não transcorreu e restabelece imediatamente `BLOCKED`, mantendo $t_{\text{trigger}}$ e $t_{\text{unlock}}$ intactos.
2. **Reinício durante `BLOCKED` com $t \ge t_{\text{unlock}}$:**
   * O EA detecta que o prazo expirou com o terminal fechado. Avalia a segurança da conta e executa formalmente o caminho `INIT -> REOPENING -> MONITORING`, capturando a baseline atual $B_n = D(t_{\text{reopen}})$ sem pular etapas.
3. **Reinício com Resíduo Aberto Durante Bloqueio:**
   * Se houver posições abertas (ex: mercado fechado durante a queda do terminal), o sistema força precedência para `LIQUIDATING`, priorizando o fechamento antes de qualquer outra ação.
4. **Reinício em `MONITORING` com Baseline Ausente ($J_n$ com $n \ge 1$):**
   * Se a baseline $B_n$ foi corrompida ou excluída das Global Variables, o sistema recusa-se terminantemente a assumir $B_n = 0$ (o que causaria falso disparo) e entra em **`FAIL-CLOSED`**, retendo a conta bloqueada em `INIT` e emitindo alertas críticos no Journal.

---

## 10. Mercado Fechado e Recusas da Corretora

Caso a proteção seja acionada no fechamento do pregão ou para ativos com negociação suspensa:
* A API MQL5 retornará retcodes de erro como `10018` (`TRADE_RETCODE_MARKET_CLOSED`).
* O EddyTrader não desiste e não avança precipitadamente para `BLOCKED`: ele permanece retido no estado `LIQUIDATING`.
* As retentativas ocorrem a cada pulso do timer (500 ms).
* **Prevenção de Log Flood:** Durante períodos prolongados de mercado fechado, o sistema suprime mensagens repetitivas no Journal, emitindo logs de diagnóstico em intervalos espaçados (a cada 5 segundos) para não inflar desnecessariamente os arquivos de log do MT5.
* O cronômetro de 4 horas corre a partir do $t_{\text{trigger}}$ original, assegurando que o tempo não seja penalizado indevidamente.

---

## 11. Efeitos da Remoção do Expert Advisor

> [!WARNING]
> **Atenção:** Se o operador descarregar o EddyTrader do gráfico (clicando com botão direito no gráfico -> *Expert Advisors* -> *Remover*):
> * O monitoramento e a neutralização física de ordens **cessam imediatamente**.
> * O estado persistido da conta permanece gravado em disco no terminal.
> * Ao reinserir o EddyTrader em qualquer gráfico da mesma conta, o robô carrega o estado persistido e restabelece a fiscalização no ponto exato em que estava.
> * Não remova o EA durante a vigência do bloqueio de 4 horas caso deseje preservar a disciplina operacional.

---

## 12. Avisos Operacionais Críticos e Isenção de Responsabilidade

1. **MaxLoss é Gatilho de Disparo, Não Garantia de Perda Exata:**
   * O valor configurado em `InpMaxLoss` define o ponto em que o sistema toma a decisão irrevogável de fechar as operações da conta.
   * A perda financeira final realizada pode ser ligeiramente superior ao limite devido a:
     * *Slippage* (derrapagem de preço na execução a mercado);
     * Abertura de *spread* da corretora;
     * Custos de comissão e liquidação da bolsa;
     * Gaps de mercado na abertura de pregão ou notícias de altíssimo impacto;
     * Latência física de rede entre o terminal MT5 e os servidores da corretora.
2. **Natureza Reativa da Neutralização em Bloqueio:**
   * O MT5 desktop não permite impedir o clique físico do usuário no botão de compra/venda antes que a ordem seja enviada.
   * Ordens manuais abertas durante o bloqueio chegam a ser registradas e são neutralizadas pelo EA milissegundos após a confirmação transacional (`OnTradeTransaction`), podendo incorrer no spread do momento.
3. **Recomendação Mandatória:**
   * **Sempre valide o EddyTrader em Conta Demo** antes de utilizá-lo em Conta Real, familiarizando-se com o comportamento visual do HUD e a disciplina temporal das 4 horas.
4. **Isenção de Responsabilidade:**
   * O EddyTrader é uma ferramenta auxiliar de mitigação de risco e disciplina comportamental. O desenvolvedor e o software não assumem responsabilidade por perdas financeiras resultantes de falhas de hardware, oscilações severas de liquidez, indisponibilidade de internet, encerramento forçado do MT5 ou condutas operacionais do usuário.

---

## 13. Guia Rápido de Troubleshooting (Diagnóstico de Falhas)

| Sintoma Observado | Causa Provável | Ação Corretiva Recomendada |
| :--- | :--- | :--- |
| **EA descarrega imediatamente com `INIT_FAILED`** | Segunda instância anexada na mesma conta. | Remova o EA de todos os gráficos e anexe-o em apenas um gráfico. Se o EA anterior travou, aguarde 15 segundos para a expiração do lease. |
| **EA descarrega com `INIT_PARAMETERS_INCORRECT`** | Parâmetro inválido (`InpMaxLoss <= 0`, horas < 1, etc.). | Abra as propriedades (`F7`) e insira valores válidos (`MaxLoss > 0`, `Duration >= 1`). |
| **HUD exibe `NEGOCIAÇÃO AUTORIZADA: NÃO (FAIL-CLOSED)`** | Baseline ausente nas Global Variables ou perda de ownership. | Verifique as mensagens no Journal. Se a baseline foi apagada indevidamente, reinicie o dia contábil ou recarregue as variáveis administrativas. |
| **EA não fecha posições ao atingir perda** | Botão "Algo Trading" do MT5 está desativado. | Clique no botão verde "Algo Trading" no topo do terminal para permitir o envio de ordens. |
| **Log exibe `retcode=10018 (market closed)`** | Ativo da posição está em horário de mercado fechado. | O EA manterá retentativas a cada 500 ms até a abertura do pregão. Nenhuma ação manual é necessária. |
| **Gráfico não atualiza valores de flutuante** | Mercado sem ticks e sem cotações novas. | O timer interno atualiza o HUD periodicamente (a cada 500 ms) independentemente da chegada de cotações. |

---

## 14. Procedimento Administrativo de Reset de Estado

O EddyTrader **nunca reseta ou apaga seu estado persistido automaticamente** em recargas de gráfico ou encerramentos normais.

Caso um administrador precise realizar a limpeza manual das variáveis da conta (por exemplo, após testes de laboratório em Conta Demo):
1. Pressione a tecla `F3` no MetaTrader 5 para abrir a janela de **Variáveis Globais do Terminal**.
2. Filtre ou selecione as chaves iniciadas por `EDDY_<SEU_LOGIN>_*`.
3. Selecione as chaves e clique no botão **Excluir**.
4. Recarregue o Expert Advisor no gráfico para iniciar um ciclo limpo em $J_0$ com baseline $B_0 = 0.00$.
