# 05 — Regras de Negócio Normativas

Este documento formaliza as Regras de Negócio (RN) que regem o comportamento do **EddyTrader**, atualizadas conforme as deliberações da **W02** registradas nos [ADR 0001](file:///C:/Projetos/eddytrader/docs/adr/0001-regras-temporais-e-janelas-de-protecao.md) e [ADR 0002](file:///C:/Projetos/eddytrader/docs/adr/0002-composicao-da-perda-operacional.md) (incluindo o esclarecimento do PO que fixou o bloqueio por duração de 4 horas a partir do acionamento).

---

## 1. Regras de Parâmetros e Configuração

### RN-001 — Validação dos Parâmetros de Entrada
* **Enunciado:** O EA deve receber obrigatoriamente:
  1. Um valor monetário positivo para o Limite Máximo de Perda Diária ($L > 0$).
  2. A regra temporal de bloqueio adota normativamente a duração aprovada de **4 horas contínuas** a partir do disparo ($t_{\text{unlock}} = t_{\text{bloqueio}} + 4\text{h}$). *(Corrigido: substitui a especificação preliminar de parâmetro com horário absoluto diário)*.
* **Comportamento:** Valores de limite menores ou iguais a zero impedem a inicialização regular da proteção, emitindo alerta explicativo no Diário do terminal.
* **Rastreabilidade:** [RF-001](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-001), [RF-002](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-002), [ADR 0001](file:///C:/Projetos/eddytrader/docs/adr/0001-regras-temporais-e-janelas-de-protecao.md).

---

## 2. Regras de Cálculo e Acompanhamento Financeiro

### RN-002 — Base de Cálculo do Prejuízo Acumulado Relevante
* **Enunciado:** O cálculo da perda relevante da conta segue rigorosamente o horário do servidor (`00:00:00` a `23:59:59`):
  $$D(t) = R_{\text{day}}(t) + F(t)$$
  $$W_n(t) = D(t) - B_n$$
  onde $B_0 = 0$ na primeira janela e $B_n = D(t_{\text{reopen}, n})$ para janelas subsequentes pós-desbloqueio.
* **Regras de Composição:**
  1. **Resultado Realizado Abrangente:** $R_{\text{day}}(t)$ representa o resultado econômico líquido realizado de trading ocorrido no dia operacional até o instante $t$ (lucros, prejuízos, comissões, swaps e taxas operacionais), sem dupla contagem (INV-009) e sem vinculação restrita ao fechamento de posições.
  2. **Movimentações de Capital Excluídas:** Depósitos, saques e ajustes de créditos administrativos são estritamente excluídos do cálculo da perda operacional (INV-008). Um saque não aumenta a perda de trading e um depósito não mascara prejuízos operacionais.
  3. **Virada do Dia Operacional:** Às `00:00:00` do servidor, perdas realizadas em dias anteriores deixam de compor a métrica diária. Posições que permaneçam abertas continuam contribuindo com seu resultado flutuante atual no novo dia.
* **Rastreabilidade:** [RF-003](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-003), [RF-004](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-004), [10-ESPECIFICACAO-MATEMATICA.md](file:///C:/Projetos/eddytrader/docs/10-ESPECIFICACAO-MATEMATICA.md), [ADR 0002](file:///C:/Projetos/eddytrader/docs/adr/0002-composicao-da-perda-operacional.md), [ADR 0003](file:///C:/Projetos/eddytrader/docs/adr/0003-modelo-matematico-de-janelas-e-baseline.md).

---

## 3. Regras de Detecção do Limite

### RN-003 — Condição de Disparo da Proteção
* **Enunciado:** A proteção de emergência deve ser acionada no exato momento em que o resultado da janela ativa for menor ou igual ao negativo do limite configurado:
  $$W_n(t) \le -L \iff P_n(t) \ge L$$
* **Comportamento:** O disparo é incondicional e imediato no primeiro tick ou evento que atestar a violação.
* **Rastreabilidade:** [RF-005](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-005), [10-ESPECIFICACAO-MATEMATICA.md](file:///C:/Projetos/eddytrader/docs/10-ESPECIFICACAO-MATEMATICA.md), [ADR 0002](file:///C:/Projetos/eddytrader/docs/adr/0002-composicao-da-perda-operacional.md), [ADR 0003](file:///C:/Projetos/eddytrader/docs/adr/0003-modelo-matematico-de-janelas-e-baseline.md).

---

## 4. Regras de Fechamento Compulsório

### RN-004 — Liquidação Global de Posições Abertas
* **Enunciado:** Uma vez disparada a proteção, o sistema deve emitir requisições de fechamento a mercado para **100% das posições abertas na conta**.
* **Escopo Irrestrito da Conta:** A liquidação atinge todos os ativos, todos os símbolos da conta, todas as ordens (manuais ou geradas por outros robôs) e todos os Magic Numbers, sem qualquer exceção ou filtro.
* **Rastreabilidade:** [RF-006](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-006), Decisão D13 e D14.

---

## 5. Regras de Cancelamento de Ordens

### RN-005 — Cancelamento Global de Ordens Pendentes
* **Enunciado:** No mesmo ciclo de contenção da proteção, o sistema deve emitir requisições de remoção para **100% das ordens pendentes** existentes na conta.
* **Comportamento:** Nenhuma ordem pendente (*Buy/Sell Limit*, *Buy/Sell Stop*, *Stop Limit*) pode permanecer ativa na conta, prevenindo reentradas automáticas indesejadas pelo mercado.
* **Rastreabilidade:** [RF-007](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-007), Decisão D17.

---

## 6. Regras de Bloqueio Operacional

### RN-006 — Imposição e Manutenção do Estado de Bloqueio
* **Enunciado:** Após a execução das ordens de fechamento e cancelamento, o sistema deve ingressar obrigatoriamente no estado `BLOCKED`.
* **Comportamento:**
  1. Novas operações abertas ou enviadas durante o período de bloqueio não devem permanecer ativas na conta.
  2. O sistema mantém exibição visual contínua no gráfico informando o bloqueio ativo, o instante do acionamento ($t_{\text{trigger}}$) e a previsão temporal mínima de liberação ($t_{\text{unlock}} = t_{\text{trigger}} + 4\text{h}$) no relógio oficial do servidor.
* **Rastreabilidade:** [RF-008](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-008), [RF-009](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-009).

---

## 7. Regras de Desbloqueio, Horários e Novas Janelas

### RN-007 — Duração do Bloqueio e Condição Temporal de Liberação
* **Enunciado:** O bloqueio temporal vigora por um período mínimo contínuo de **4 horas** contado a partir do instante em que a proteção foi acionada:
  $$t_{\text{unlock}} = t_{\text{trigger}} + 4\text{h} = t_{\text{trigger}} + 14.400\text{s}$$
* **Regras Normativas de Tempo:**
  1. **Duração Relativa:** A restrição temporal é sempre de 4 horas a partir do evento de bloqueio ($t_{\text{unlock}}$).
  2. **Independência entre Ciclo Contábil e Ciclo de Bloqueio:** A virada de dia às `00:00:00` do servidor NÃO afeta $t_{\text{unlock}}$. Bloqueio acionado às `23:30` tem $t_{\text{unlock}} = \text{03:30}$ do dia seguinte.
  3. **Condição Necessária vs. Suficiente:** O cumprimento da janela temporal mínima $[t_{\text{trigger}}, t_{\text{unlock}})$ é condição necessária para liberação, mas a reabertura efetiva ($t_{\text{reopen}} \ge t_{\text{unlock}}$) requer a ausência de condições de proteção ativas.
* **Rastreabilidade:** [RF-002](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-002), [RF-010](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-010), [10-ESPECIFICACAO-MATEMATICA.md](file:///C:/Projetos/eddytrader/docs/10-ESPECIFICACAO-MATEMATICA.md), [11-MAQUINA-DE-ESTADOS.md](file:///C:/Projetos/eddytrader/docs/11-MAQUINA-DE-ESTADOS.md), [ADR 0001](file:///C:/Projetos/eddytrader/docs/adr/0001-regras-temporais-e-janelas-de-protecao.md), [ADR 0004](file:///C:/Projetos/eddytrader/docs/adr/0004-maquina-de-estados-e-recuperacao.md).

### RN-008 — Nova Janela Operacional e Baseline de Reabertura
* **Enunciado:** Ao atingir as condições de liberação em $t_{\text{reopen}}$ (com $t_{\text{reopen}} \ge t_{\text{unlock}}$), o evento de bloqueio é encerrado, o sistema remove a trava e **inicia uma nova janela operacional de proteção intradiária** $J_n$ ($n \ge 1$).
* **Comportamento Normativo:**
  1. O histórico contábil de perdas anteriores do dia não é apagado (integridade dos dados).
  2. Para evitar o rebloqueio instantâneo, o sistema estabelece a baseline no instante real da reabertura:
     $$B_n = D(t_{\text{reopen}, n})$$
  3. O resultado da nova janela inicia em zero:
     $$W_n(t_{\text{reopen}, n}) = D(t_{\text{reopen}, n}) - B_n = 0$$
  4. A proteção na nova janela observará novas perdas incorridas a partir do momento da liberação:
     $$W_n(t) \le -L$$
  5. Se o bloqueio tiver cruzado a meia-noite, a baseline da reabertura é calculada sobre a contabilidade do novo dia operacional no instante efetivo da reabertura ($B_{\text{new}} = D_{\text{novo\_dia}}(t_{\text{reopen}})$).
* **Rastreabilidade:** [RF-011](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-011), [RF-012](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-012), [10-ESPECIFICACAO-MATEMATICA.md](file:///C:/Projetos/eddytrader/docs/10-ESPECIFICACAO-MATEMATICA.md), [11-MAQUINA-DE-ESTADOS.md](file:///C:/Projetos/eddytrader/docs/11-MAQUINA-DE-ESTADOS.md), [ADR 0001](file:///C:/Projetos/eddytrader/docs/adr/0001-regras-temporais-e-janelas-de-protecao.md), [ADR 0003](file:///C:/Projetos/eddytrader/docs/adr/0003-modelo-matematico-de-janelas-e-baseline.md), [ADR 0004](file:///C:/Projetos/eddytrader/docs/adr/0004-maquina-de-estados-e-recuperacao.md).

---

## 8. Regras de Tratamento de Falhas

### RN-009 — Resiliência Operacional e Manutenção do Estado de Liquidação/Proteção
* **Enunciado:** A falha no fechamento de uma posição individual (por mercado fechado, rejeição ou falta de liquidez) não autoriza a interrupção do EA, o avanço indevido para bloqueio passivo nem o retorno da conta ao estado nominal.
* **Comportamento:**
  1. A falha é registrada detalhadamente no Diário do MT5 (`ticket`, código de retorno, motivo).
  2. As demais posições e ordens pendentes continuam sendo processadas normalmente.
  3. **Enquanto houver posições ou ordens que deveriam ter sido neutralizadas ativas na conta, o sistema permanece estritamente em `LIQUIDATING`**, persistindo nas retentativas de encerramento. A transição para `BLOCKED` exige neutralização de 100% da exposição (resíduo zero). Em hipótese alguma o sistema transita para monitoramento nominal com pendências residuais.
  4. O relógio de 4 horas contínuas ($t_{\text{unlock}} = t_{\text{trigger}} + 14.400\text{s}$) corre soberanamente durante a retenção em `LIQUIDATING`.
* **Rastreabilidade:** [RF-013](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-013), [RNF-004](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rnf-004), Decisão D16, [11 — Máquina de Estados](file:///C:/Projetos/eddytrader/docs/11-MAQUINA-DE-ESTADOS.md), [ADR 0004](file:///C:/Projetos/eddytrader/docs/adr/0004-maquina-de-estados-e-recuperacao.md).

---

## 9. Regras de Integridade Operacional e Homologação

### RN-010 — Transparência Visual, Painel HUD Adaptativo e Desacoplamento
* **Enunciado:** O operador deve ser mantido informado diretamente na tela do gráfico sobre o estado da proteção, o horário do servidor corrente e as métricas financeiras da conta, com controle adaptativo da densidade visual:
  1. **Estados de Apresentação:** O HUD suporta os modos `PANEL_EXPANDED` (com submodos Compacto e Detalhado) e `PANEL_COLLAPSED` (pill minimizada discreta de $370 \times 26$ px no canto superior esquerdo).
  2. **Preservação de Modo:** Ao alternar de expandido para minimizado e vice-versa, o sistema preserva e restaura deterministicamente o modo expandido preferido pelo operador (`COMPACT` ou `DETAILED`).
  3. **Visibilidade Crítica em Bloqueio:** Se o sistema estiver minimizado e ingressar em `LIQUIDATING` ou `BLOCKED`, a pill minimizada altera imediatamente suas cores e texto para alertar em destaque (`🔒 BLOQUEADO hh:mm:ss`) com contagem regressiva em tempo real.
  4. **Persistência Visual Não-Fatal:** O estado colapsado é salvo na Global Variable `EDDY_<LOGIN>_CONFIG_PANEL_COLLAPSED`. Esta persistência é puramente cosmética e estritamente desacoplada do conjunto conceitual crítico $\mathbf{D}_{\text{min\_recovery}}$. Qualquer falha na leitura ou escrita das preferências de HUD é silenciosamente ignorada e nunca causará transição para *Fail-Closed*.
* **Rastreabilidade:** [RF-009](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-009), [RF-011](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-011), [RF-014](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-014), [RNF-005](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rnf-005).

### RN-011 — Instância Única por Conta
* **Enunciado:** O Disciplinador Trader opera conceitualmente como um único gerenciador de risco por conta de negociação.
* **Comportamento:** É expressamente vetada a execução de múltiplas instâncias concorrentes do Disciplinador Trader na mesma conta disputando ordens de liquidação e controle de estados.
* **Rastreabilidade:** Decisão D14, [RISK-006](file:///C:/Projetos/eddytrader/docs/08-RISCOS-E-QUESTOES-ABERTAS.md#4-riscos-tecnicos-e-operacionais-risks).

### RN-012 — Homologação Prévia Obrigatória em Conta Demo
* **Enunciado:** O Disciplinador Trader somente será liberado para uso em Conta Real após aprovação documental e empírica com 100% de sucesso em Conta Demo.
* **Rastreabilidade:** Decisão D20, [07 — MVP](file:///C:/Projetos/eddytrader/docs/07-MVP.md).

### RN-013 — Operação Account-Global e Independência de Símbolo/Gráfico
* **Enunciado:** O Disciplinador Trader opera com soberania irrestrita e abrangência de conta inteira (*Account-Global*):
  1. **Independência de Ativo:** A integridade dos cálculos de resultado realizado ($R_{\text{day}}$), flutuante ($F$) e resultado da janela ($W_n$) é calculada em nível de conta, consolidando todos os ativos operados pelo trader ou por robôs terceiros.
  2. **Isolamento de Gráficos:** O Disciplinador Trader deve operar perfeitamente quando anexado a um gráfico isolado (Gráfico B), enquanto o operador realiza trades manuais via Chart Trade ou executa outros EAs em gráficos separados (Gráfico A).
  3. **Universalidade na Liquidação:** O fechamento compulsório atinge 100% das ordens e posições abertas na conta, independentemente do símbolo onde foram emitidas ou do seu Magic Number.
* **Rastreabilidade:** [RF-015](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-015), [RN-004](file:///C:/Projetos/eddytrader/docs/05-REGRAS-DE-NEGOCIO.md#rn-004), [RN-005](file:///C:/Projetos/eddytrader/docs/05-REGRAS-DE-NEGOCIO.md#rn-005).
