# ADR 0004 — Máquina de Estados Finita Normativa e Protocolo de Recuperação

* **Status:** Accepted
* **Data:** 2026-09-12
* **Contexto:** W04 — Especificação Normativa da Máquina de Estados (FSM) do EddyTrader
* **Decisões Relacionadas:** D01, D07, D08, D09, D10, D11, D12, D13, D16, D18
* **GAPs Afetados:** GAP-005 (Definido conceitualmente na FSM; validação de implementação adiada para W05)

---

## 1. Contexto e Problema

As etapas W01, W02 e W03 formalizaram as regras de negócio e o modelo matemático determinístico do EddyTrader:
* Monitoramento contínuo da perda relevante $W_n(t) = D(t) - B_n$ contra o limite positivo $L$;
* Bloqueio contínuo obrigatório de 4 horas ($t_{\text{unlock}} = t_{\text{trigger}} + 14.400\text{s}$);
* Independência da meia-noite (`00:00:00`), mantendo o bloqueio soberano até completar 4 horas;
* Eliminação de rebloqueio imediato mediante baseline $B_n = D(t_{\text{reopen}, n})$ na abertura de nova janela operacional.

Entretanto, para que o sistema se comporte de forma previsível e auditável em qualquer circunstância operacional do MetaTrader 5, fazia-se mandatório responder com precisão conceitual:
1. Quais são os estados formais do ciclo de vida da proteção?
2. Quais eventos conceituais provocam mudanças de estado e sob quais condições lógicas (*guards*)?
3. Quais transições devem ser expressamente bloqueadas para garantir que falhas transitórias não exponham o capital da conta?
4. Como o sistema se recupera deterministicamente após uma reinicialização física do terminal (queda de energia, fechamento do MT5, reconexão de rede) sem reiniciar o contador de 4 horas e sem liberar operações indevidamente?

---

## 2. Decisão

Adotar a **Máquina de Estados Finita Normativa** estruturada em seis estados conceituais, formalizada integralmente em [11 — Máquina de Estados](file:///C:/Projetos/eddytrader/docs/11-MAQUINA-DE-ESTADOS.md):

```text
INIT -> MONITORING -> PROTECTION_TRIGGERED -> LIQUIDATING -> BLOCKED -> REOPENING -> MONITORING
```

### 2.1. Decomposição em Seis Estados Conceituais
1. **`INIT`:** Ponto de entrada obrigatório na carga ou reinicialização. Avalia o contexto preexistente e decide o destino seguro antes de liberar qualquer negociação. Caso haja indeterminação de dados (incluindo baseline desconhecida em janelas intradiárias subsequentes), retém o sistema sem autorizar operações (postura *fail-closed*).
2. **`MONITORING`:** Único estado com permissão para negociação nominal. Avalia $W_n(t) \le -L$.
3. **`PROTECTION_TRIGGERED`:** Estado atômico transitório posicionado no momento da detecção. Congela o contexto da violação, registra $t_{\text{trigger}}$, calcula $t_{\text{unlock}} = t_{\text{trigger}} + 4\text{h}$, gera `protection_event_id` e despacha ordens de liquidação.
4. **`LIQUIDATING`:** Estado ativo de execução compulsória. Encerra posições a mercado e cancela ordens pendentes em escopo global da conta. Enquanto existir qualquer exposição residual a neutralizar (ex.: por mercado fechado ou recusa da corretora), o sistema **permanece estritamente em `LIQUIDATING`**. A transição para `BLOCKED` ocorre única e exclusivamente após a neutralização de 100% da exposição (resíduo zero).
5. **`BLOCKED`:** Estado de bloqueio operacional por 4 horas contínuas, ativo estritamente após a eliminação de 100% da exposição residual inicial. Qualquer tentativa de negociação manual é neutralizada. A saída exige simultaneamente o decurso do tempo ($t \ge t_{\text{unlock}}$) e a ausência de pendências (`safe_to_reopen == true`).
6. **`REOPENING`:** Procedimento formal de transição. Registra o instante real $t_{\text{reopen}} \ge t_{\text{unlock}}$, fixa a baseline $B_{n+1} = D(t_{\text{reopen}})$, valida $W_{n+1}(t_{\text{reopen}}) = 0$ e autoriza o retorno a `MONITORING`.

### 2.2. O Relógio das 4 Horas Inicia em $t_{\text{trigger}}$
Fica decidido normativamente que o instante de liberação temporal mínima é:
$$t_{\text{unlock}} = t_{\text{trigger}} + 14.400\text{s}$$
O tempo decorrido durante a liquidação em `LIQUIDATING` consome o período interno das 4 horas. A conclusão da liquidação não prorroga e não reinicia a contagem temporal.

### 2.3. Separação Estrita entre Tempo e Segurança
* **$t \ge t_{\text{unlock}}$** é condição estritamente temporal (necessária, mas não suficiente).
* **`safe_to_reopen`** é a condição de segurança contábil e operacional (inexistência de posições e ordens pendentes residuais).
* A transição para `REOPENING` exige a conjunção lógica:
  $$\text{Condição de Desbloqueio} \iff (t \ge t_{\text{unlock}}) \land (\text{safe\_to\_reopen} == \text{true})$$
  Se $t \ge t_{\text{unlock}}$ mas restarem pendências, o sistema permanece retido em `BLOCKED` com $t_{\text{reopen}} > t_{\text{unlock}}$.

### 2.4. Protocolo Determinístico de Reinicialização (`Restart -> INIT`)
Qualquer interrupção e reinício do terminal MT5 ou do Expert Advisor ingressa compulsoriamente em `INIT`, avaliando o estado segundo uma ordem de precedência hierárquica estrita:
1. **Dados Insuficientes ou Indeterminação:** Se registros forem omissos ou se $B_n$ intradiário ($n \ge 1$) for irrecuperável $\implies$ permanece retido em `INIT` com `safe_to_operate = false` (postura *fail-closed*, sem fallback silencioso para zero);
2. **Exposição Residual Pendente:** Se houver ordens ou posições abertas que deveriam ter sido eliminadas pela proteção $\implies$ **transita para `LIQUIDATING`** (precedência absoluta sobre qualquer bloqueio ou reabertura, independentemente de $t < t_{\text{unlock}}$ ou $t \ge t_{\text{unlock}}$);
3. **Evento de Proteção Ativo com $t < t_{\text{unlock}}$ (Resíduo Zero):** Transita para `BLOCKED`, preservando o par $(t_{\text{trigger}}, t_{\text{unlock}})$ original sem reiniciar contadores de tempo;
4. **Evento de Proteção Pendente com $t \ge t_{\text{unlock}}$ (Resíduo Zero):**
   - Se `safe_to_reopen == false` $\implies$ **transita para `BLOCKED`** (modo de retenção passiva até saneamento das condições de segurança);
   - Se `safe_to_reopen == true` $\implies$ **transita deterministicamente para `REOPENING`** (é terminantemente proibido saltar diretamente para `MONITORING`), formalizando o desbloqueio no instante real $t_{\text{reopen}} \ge t_{\text{unlock}}$, fotografando $B_{n+1} = D(t_{\text{reopen}})$ e validando $W_{n+1}(t_{\text{reopen}}) = 0$;
5. **Estado Nominal sem Proteção Pendente:** Se não houver proteção pendente e $W_n(t) > -L \implies$ transita para `MONITORING` (estabelecendo $B_0 \gets 0$ se $J_0$ ou restaurando $B_n$ se $J_n$).

### 2.5. Identificação dos Dados Mínimos de Recuperação ($\mathbf{D}_{\text{min\_recovery}}$)
Fica formalmente identificado que a reconstituição unívoca da FSM pós-restart exige conceitualmente:
$$\mathbf{D}_{\text{min\_recovery}} = \{ \text{current\_state}, \text{protection\_event\_id}, J_n, B_n, t_{\text{trigger}}, t_{\text{unlock}} \}$$

---

## 3. Alternativas Rejeitadas

1. **Retornar a `MONITORING` por padrão na inicialização do EA:**
   * *Rejeitada:* Criaria uma brecha grave em que reiniciar o terminal cancelaria um bloqueio ativo de 4 horas imposto anteriormente.
2. **Reiniciar a contagem de 4 horas apenas após a conclusão total da liquidação:**
   * *Rejeitada:* Violaria o requisito normativo de que o operador sofre o bloqueio pelo evento da perda em si. Em casos de retentativas demoradas por latência de rede, puniria desproporcionalmente o operador além das 4 horas acordadas.
3. **Transitar para `BLOCKED` com exposição residual pendente de liquidação:**
   * *Rejeitada:* Diluiria a responsabilidade do motor de contenção. O estado `BLOCKED` é passivo e tem por propósito impedir novas operações após a conta estar estancada. Confinar o tratamento de falhas e retentativas em `LIQUIDATING` preserva a separação estrita de responsabilidades da máquina de estados.
4. **Liberar a conta imediatamente ao atingir $t_{\text{unlock}}$ sem checar pendências residuais:**
   * *Rejeitada:* Permitiria reabertura de novas ordens enquanto ainda houvesse pendências decorrentes de falhas operacionais na liquidação anterior.
5. **Aplicar fallback tácito para $B=0$ em reinicialização durante janela intradiária com baseline irrecuperável:**
   * *Rejeitada:* Aplicar $B=0$ arbitrariamente no meio do dia após um evento de perda anterior apagaria o histórico ou provocaria falsos disparos imediatos. O sistema deve operar sempre em regime *fail-closed*.
6. **Criar um estado extra `RECOVERY_REQUIRED` nesta etapa:**
   * *Rejeitada (YAGNI):* A retenção fail-closed dentro do próprio estado `INIT` atende integralmente ao objetivo de proteção sem inflar a máquina de estados prematuramente.
7. **Saltar diretamente de `INIT` para `MONITORING` após $t_{\text{unlock}}$ sob proteção pendente:**
   * *Rejeitada:* Ignoraria a necessidade mandatória de registrar formalmente a baseline da nova janela no momento da reabertura efetiva ($B_{n+1} = D(t_{\text{reopen}})$). A passagem por `REOPENING` é indispensável para zerar a métrica da nova janela ($W_{n+1}(t_{\text{reopen}}) = 0$) e evitar falsos rebloqueios imediatos.
8. **Calcular baseline retroativa em $t_{\text{unlock}}$ em vez do instante real $t_{\text{reopen}}$:**
   * *Rejeitada:* Se o terminal reiniciou e retornou operacional em momento posterior a $t_{\text{unlock}}$, a baseline deve espelhar a métrica contábil no instante exato da liberação efetiva, e não retroativamente no horário nominal original.

---

## 4. Consequências

### Positivas
* **Previsibilidade Total:** Não há transições espúrias ou ambíguas; todo o ciclo de vida da proteção é determinístico.
* **Segurança Reforçada (Fail-Closed):** O sistema nunca assume autorização de negociação em caso de dúvida de dados.
* **Independência Tecnológica:** A FSM modela o comportamento de produto e risco sem depender da taxonomia ou funções concretas do MQL5.

### Encaminhamentos para a W05 (Spike Técnico MT5/MQL5)
Ficam explicitamente adiadas para avaliação empírica laboratorial na W05:
1. **Mapeamento de Callbacks:** Avaliar os eventos nativos do MT5 (`OnTick`, `OnTimer`, `OnTradeTransaction`, `OnInit`) que acionarão as avaliações de guarda da FSM;
2. **Mecanismo de Intervenção Manual:** Testar como neutralizar ordens manuais inseridas pelo operador durante `BLOCKED` (rejeição reativa imediata vs interceptação de eventos);
3. **Suficiência do Histórico Nativo vs. Persistência de $\mathbf{D}_{\text{min\_recovery}}$:** Investigar se as ordens/deals do histórico nativo do terminal contêm registros suficientes para derivar $\mathbf{D}_{\text{min\_recovery}}$ de forma pura, ou se o produto exigirá armazenamento auxiliar leve (*GlobalVariables* vs arquivo em `MQL5/Files`).

---

## 5. Rastreabilidade

* Documento Normativo Primário: [11 — Especificação Normativa da Máquina de Estados](file:///C:/Projetos/eddytrader/docs/11-MAQUINA-DE-ESTADOS.md)
* Requisitos Atendidos: [RF-002, RF-005, RF-006, RF-007, RF-008, RF-010, RF-012, RF-013, RNF-004](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md)
* Fundamentação Matemática: [10 — Especificação Matemática](file:///C:/Projetos/eddytrader/docs/10-ESPECIFICACAO-MATEMATICA.md)
* Decisões Anteriores: [ADR 0001](file:///C:/Projetos/eddytrader/docs/adr/0001-regras-temporais-e-janelas-de-protecao.md), [ADR 0002](file:///C:/Projetos/eddytrader/docs/adr/0002-composicao-da-perda-operacional.md) e [ADR 0003](file:///C:/Projetos/eddytrader/docs/adr/0003-modelo-matematico-de-janelas-e-baseline.md)
* Próxima Etapa: W05 — Spike Técnico MT5/MQL5 (Bloqueio, Eventos e Garantias)
