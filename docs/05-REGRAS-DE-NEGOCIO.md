# 05 — Regras de Negócio Normativas

Este documento formaliza as Regras de Negócio (RN) que regem o comportamento do **EddyTrader**. Regras cujos detalhes técnicos precisos dependam de definições pendentes preservam o requisito aprovado e apontam diretamente para as respectivas questões abertas.

---

## 1. Regras de Parâmetros e Configuração

### RN-001 — Validação dos Parâmetros de Entrada
* **Enunciado:** O EA deve receber obrigatoriamente:
  1. Um valor monetário positivo para o Limite Máximo de Perda Diária ($L > 0$).
  2. Um horário válido para liberação das operações no formato `HH:MM`.
* **Comportamento:** Valores de limite menores ou iguais a zero ou formatos de horário inválidos devem impedir a transição para o estado de vigilância regular, emitindo alerta explicativo no Diário do terminal.
* **Rastreabilidade:** [RF-001](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-001), [RF-002](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-002).

---

## 2. Regras de Cálculo e Acompanhamento

### RN-002 — Base de Cálculo do Prejuízo Acumulado Relevante
* **Enunciado:** O EA deve acompanhar continuamente o resultado financeiro realizado no período diário somado ao resultado financeiro flutuante de todas as posições abertas.
* **Critério Aprovado:**
  $$\text{Resultado Considerado} = \text{Resultado Realizado do Dia} + \text{Resultado Flutuante das Posições Abertas}$$
  A perda acumulada relevante ocorre quando esse valor consolidado atinge um montante negativo igual ou mais severo que o limite configurado:
  $$\text{Perda Diária} = -(\text{Resultado Considerado})$$
* **Decisão Pendente / Questão Aberta:** A definição exata da janela temporal que constitui o "dia" (fuso horário local vs. fuso horário do servidor da corretora) e o impacto contábil exato de depósitos, saques, comissões de corretagem e taxas de custódia (*swap*) estão formalmente registrados como pendentes de especificação em [GAP-001](file:///C:/Projetos/eddytrader/docs/08-RISCOS-E-QUESTOES-ABERTAS.md#gap-001--definicao-do-fuso-horario-e-marco-inicial-do-dia) e [GAP-002](file:///C:/Projetos/eddytrader/docs/08-RISCOS-E-QUESTOES-ABERTAS.md#gap-002--composicao-financeira-do-resultado-relevante). Não é permitida a criação de fórmulas matemáticas alternativas não homologadas.
* **Rastreabilidade:** [RF-003](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-003), [RF-004](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-004).

---

## 3. Regras de Detecção do Limite

### RN-003 — Condição de Disparo da Proteção
* **Enunciado:** A proteção de emergência deve ser acionada no exato momento em que a perda acumulada relevante for igual ou superior ao limite configurado pelo operador.
* **Critério Aprovado:**
  $$\text{Se } (\text{Perda Diária} \ge \text{Limite Configurado}) \implies \text{Disparar Proteção}$$
  *Exemplo:* Com limite de `500.00`, caso o resultado apurado atinja `-500.00` ou `-503.00` (perda de 503), o disparo é imediato e mandatório.
* **Rastreabilidade:** [RF-005](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-005).

---

## 4. Regras de Fechamento Compulsório

### RN-004 — Liquidação Total de Posições Abertas
* **Enunciado:** Uma vez disparada a proteção, o sistema deve emitir ordens de fechamento a mercado para a totalidade das posições abertas na conta, independentemente do símbolo, do Magic Number ou do tempo de abertura.
* **Comportamento:** O fechamento deve ser processado sem distinção de ativo ou lucratividade individual de cada posição.
* **Rastreabilidade:** [RF-006](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-006).

---

## 5. Regras de Cancelamento de Ordens

### RN-005 — Cancelamento Total de Ordens Pendentes
* **Enunciado:** No mesmo ciclo de acionamento da proteção, o sistema deve requisitar o cancelamento de todas as ordens pendentes (*limits*, *stops*, *stop-limits*) existentes na conta.
* **Comportamento:** Nenhuma ordem pendente deve permanecer ativa após a execução da proteção, impedindo reentradas involuntárias provocadas pelo mercado.
* **Rastreabilidade:** [RF-007](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-007).

---

## 6. Regras de Bloqueio Operacional

### RN-006 — Imposição do Estado de Bloqueio
* **Enunciado:** Após o fechamento das posições e cancelamento das ordens, o sistema deve entrar obrigatoriamente no estado `BLOCKED`.
* **Comportamento:**
  1. Novas operações devem ser bloqueadas ou neutralizadas durante a vigência do estado.
  2. O sistema deve emitir visualmente no gráfico o alerta de que o limite foi atingido e indicar o horário previsto de liberação.
* **Decisão Pendente / Questão Arquitetural:** O mecanismo exato suportado pela plataforma MetaTrader 5 para impedir ordens manuais e de outros robôs (interceptação prévia versus liquidação reativa instantânea) constitui questão aberta registrada em [DQ-001](file:///C:/Projetos/eddytrader/docs/08-RISCOS-E-QUESTOES-ABERTAS.md#dq-001--mecanismo-de-bloqueio-operacional-no-mt5).
* **Rastreabilidade:** [RF-008](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-008), [RF-009](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-009).

---

## 7. Regras de Desbloqueio e Liberação

### RN-007 — Condição de Liberação Temporal
* **Enunciado:** O desbloqueio operacional ocorre estritamente quando o relógio da plataforma atingir ou ultrapassar o horário de desbloqueio configurado pelo operador.
* **Decisão Pendente / Questão Aberta:** A sincronização e o comportamento caso o horário configurado seja anterior ao horário de ocorrência do bloqueio ou cruze a virada de dia civil (00:00) estão registrados em [GAP-003](file:///C:/Projetos/eddytrader/docs/08-RISCOS-E-QUESTOES-ABERTAS.md#gap-003--consistencia-temporal-do-horario-de-desbloqueio).
* **Rastreabilidade:** [RF-010](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-010).

### RN-008 — Restauração do Monitoramento
* **Enunciado:** Ao atingir o horário de desbloqueio, o sistema deve:
  1. Remover as restrições de bloqueio.
  2. Atualizar a informação visual informando que as operações foram liberadas.
  3. Retomar o estado nominal de monitoramento (`MONITORING`).
* **Rastreabilidade:** [RF-011](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-011), [RF-012](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-012).

---

## 8. Regras de Tratamento de Falhas

### RN-009 — Resiliência Operacional e Não Interrupção por Falha Isolada
* **Enunciado:** A recusa ou falha no encerramento de uma posição específica (por exemplo, por mercado fechado, falta momentânea de cotação ou rejeição da corretora) não autoriza a interrupção da execução do EA nem a omissão no processamento das demais posições.
* **Comportamento:**
  1. A falha é registrada com detalhes (ticket, símbolo, código do erro) no Diário do terminal.
  2. As posições restantes continuam sendo processadas.
  3. O EA mantém sua rotina ativa para tentar garantir a segurança da conta.
* **Rastreabilidade:** [RF-013](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-013), [RNF-004](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rnf-004), [RNF-005](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rnf-005).

---

## 9. Regras de Visibilidade e Auditoria

### RN-010 — Transparência Visual e Registro Contábil
* **Enunciado:** O operador deve ser mantido informado sobre o estado da proteção diretamente na tela do gráfico e todo evento crítico deve ser auditável via log nativo (`Print`).
* **Mensagens Padrão Aprovadas:**
  * No bloqueio:
    > *"Limite diário atingido.*  
    > *Todas as operações foram encerradas.*  
    > *Novas operações bloqueadas.*  
    > *Liberação às [HH:MM]."*
  * No desbloqueio:
    > *"Bloqueio removido.*  
    > *Operações liberadas."*
* **Rastreabilidade:** [RF-009](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-009), [RF-011](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rf-011), [RNF-005](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md#rnf-005).
