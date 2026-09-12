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
  $$\text{RESULTADO\_RELEVANTE} = \text{RESULTADO\_REALIZADO\_DO\_DIA} + \text{RESULTADO\_FLUTUANTE\_ATUAL}$$
  $$\text{PERDA\_DIÁRIA} = -(\text{RESULTADO\_RELEVANTE})$$
* **Regras de Composição:**
  1. **Custos Operacionais Inclusos:** Comissões de corretagem, emolumentos e taxas de rolagem (*swaps*) são obrigatoriamente somados ao resultado das operações fechadas e posições abertas para refletir a variação patrimonial líquida real do trading.
  2. **Movimentações de Capital Excluídas:** Depósitos, saques e ajustes de créditos administrativos são estritamente excluídos do cálculo da perda operacional. Um saque não aumenta a perda de trading e um depósito não mascara prejuízos operacionais.
  3. **Virada do Dia Operacional:** Às `00:00:00` do servidor, perdas realizadas em dias anteriores deixam de compor a métrica diária. Posições que permaneçam abertas continuam contribuindo com seu resultado flutuante atual no novo dia.
* **Rastreabilidade:** [RF-003](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-003), [RF-004](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-004), [ADR 0002](file:///C:/Projetos/eddytrader/docs/adr/0002-composicao-da-perda-operacional.md).

---

## 3. Regras de Detecção do Limite

### RN-003 — Condição de Disparo da Proteção
* **Enunciado:** A proteção de emergência deve ser acionada no exato momento em que o resultado relevante for menor ou igual ao negativo do limite configurado:
  $$\text{RESULTADO\_RELEVANTE} \le - \text{LIMITE\_CONFIGURADO} \iff \text{PERDA\_DIÁRIA} \ge \text{LIMITE\_CONFIGURADO}$$
* **Comportamento:** O disparo é incondicional e imediato no primeiro tick ou evento que atestar a violação.
* **Rastreabilidade:** [RF-005](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-005), [ADR 0002](file:///C:/Projetos/eddytrader/docs/adr/0002-composicao-da-perda-operacional.md).

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
  2. O sistema mantém exibição visual contínua no gráfico informando o bloqueio ativo, o instante do acionamento e a previsão exata de liberação ($t_{\text{bloqueio}} + 4\text{h}$) no relógio oficial do servidor.
* **Rastreabilidade:** [RF-008](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-008), [RF-009](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-009).

---

## 7. Regras de Desbloqueio, Horários e Novas Janelas

### RN-007 — Duração do Bloqueio e Condição Temporal de Liberação
* **Enunciado:** O bloqueio vigora por um período contínuo de **4 horas** contado a partir do instante em que a proteção foi acionada:
  $$\text{INSTANTE\_DE\_LIBERAÇÃO} = \text{INSTANTE\_DO\_BLOQUEIO} + 4\text{ HORAS}$$
  $$T_{\text{unlock}} = T_0 + 4\text{h}$$
* **Regras Normativas de Tempo:**
  1. **Duração Relativa:** A duração é sempre de 4 horas a partir do evento de bloqueio.
     * Exemplo A: limite violado às `10:00` $\implies$ liberação às `14:00`.
     * Exemplo B: limite violado às `14:25` $\implies$ liberação às `18:25`.
  2. **Independência entre Ciclo Contábil e Ciclo de Bloqueio:** A virada de dia às `00:00:00` do servidor NÃO afeta a duração do bloqueio.
     * Exemplo C: limite violado às `23:30` $\implies$ liberação às `03:30` do dia seguinte.
  3. **Novo Dia sob Bloqueio Ativo:** Mesmo que um novo dia operacional comece enquanto o bloqueio estiver ativo, a proteção continua soberana até completar integralmente as 4 horas.
  4. **Critério de Liberação:** O sistema permanece em `BLOCKED` no intervalo $[T_0, T_{\text{unlock}})$ e torna-se elegível à liberação quando o relógio do servidor satisfizer $T \ge T_{\text{unlock}}$.
* **Rastreabilidade:** [RF-002](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-002), [RF-010](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-010), [ADR 0001](file:///C:/Projetos/eddytrader/docs/adr/0001-regras-temporais-e-janelas-de-protecao.md).

### RN-008 — Nova Janela Operacional e Baseline de Reabertura
* **Enunciado:** Ao completar exatamente as 4 horas ($T \ge T_{\text{unlock}}$), o evento de bloqueio é encerrado, o sistema remove a trava e **inicia uma nova janela operacional de proteção intradiária**.
* **Comportamento Normativo:**
  1. O histórico de perdas anteriores do dia não é apagado (integridade contábil).
  2. Para evitar o rebloqueio instantâneo (*desbloquear $\to$ detectar perda do dia já violada $\to$ bloquear imediatamente*), o sistema estabelece uma **`baseline_de_reabertura`**.
  3. A proteção na nova janela observará novas perdas incorridas a partir do momento da liberação.
  4. A formulação matemática exata da baseline pertence ao escopo da W03.
* **Rastreabilidade:** [RF-011](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-011), [RF-012](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-012), [ADR 0001](file:///C:/Projetos/eddytrader/docs/adr/0001-regras-temporais-e-janelas-de-protecao.md).

---

## 8. Regras de Tratamento de Falhas

### RN-009 — Resiliência Operacional e Manutenção do Estado de Proteção
* **Enunciado:** A falha no fechamento de uma posição individual (por mercado fechado, rejeição ou falta de liquidez) não autoriza a interrupção do EA nem o retorno da conta ao estado nominal.
* **Comportamento:**
  1. A falha é registrada detalhadamente no Diário do MT5 (`ticket`, código de retorno, motivo).
  2. As demais posições e ordens pendentes continuam sendo processadas normalmente.
  3. **Enquanto houver posições que deveriam ter sido liquidadas ativas na conta, o sistema permanece em estado de proteção/bloqueio ativo**, sem transitar para monitoramento normal.
* **Rastreabilidade:** [RF-013](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-013), [RNF-004](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rnf-004), Decisão D16.

---

## 9. Regras de Integridade Operacional e Homologação

### RN-010 — Transparência Visual e Registro Contábil
* **Enunciado:** O operador deve ser mantido informado diretamente na tela do gráfico sobre o estado da proteção, o horário do servidor corrente e as mensagens de liberação ou bloqueio.
* **Rastreabilidade:** [RF-009](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-009), [RF-011](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-011), [RNF-005](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rnf-005).

### RN-011 — Instância Única por Conta
* **Enunciado:** O EddyTrader opera conceitualmente como um único gerenciador de risco por conta de negociação.
* **Comportamento:** É expressamente vetada a execução de múltiplas instâncias concorrentes do EddyTrader na mesma conta disputando ordens de liquidação e controle de estados.
* **Rastreabilidade:** Decisão D14, [RISK-006](file:///C:/Projetos/eddytrader/docs/08-RISCOS-E-QUESTOES-ABERTAS.md#4-riscos-tecnicos-e-operacionais-risks).

### RN-012 — Homologação Prévia Obrigatória em Conta Demo
* **Enunciado:** O EddyTrader somente será liberado para uso em Conta Real após aprovação documental e empírica com 100% de sucesso em Conta Demo.
* **Rastreabilidade:** Decisão D20, [07 — MVP](file:///C:/Projetos/eddytrader/docs/07-MVP.md).
