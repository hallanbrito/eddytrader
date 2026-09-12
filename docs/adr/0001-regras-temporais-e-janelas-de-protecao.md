# ADR 0001 — Regras Temporais e Janelas de Proteção

* **Status:** Accepted
* **Data:** 2026-09-12 (Revisado após esclarecimento de requisito do PO)
* **Contexto:** W02 — Resolução de Decisões Críticas e GAPs do EddyTrader
* **Decisões Relacionadas:** D01, D02, D07 (Atualizada), D08 (Atualizada), D09, D10 (Atualizada), D11 (Atualizada)
* **GAPs Afetados:** GAP-001 (Resolvido), GAP-003 (Resolvido / Atualizado)

---

## 1. Contexto e Problema

O EddyTrader é um gerenciador de perda diária que monitora o resultado financeiro intradiário e bloqueia operações por um período determinado quando o limite de perda é violado.

### Esclarecimento de Requisito pelo Product Owner (PO)
Na concepção inicial do projeto, o exemplo ilustrativo de `16:00` presente na especificação preliminar foi equivocadamente interpretado como um horário fixo/absoluto de liberação diária. O Product Owner esclareceu formally a intenção de negócio original:
> Após o limite de perda ser atingido, o EddyTrader deverá bloquear novas operações por um período contínuo de **4 horas** contado a partir do instante em que a proteção foi acionada.

Portanto, o sistema não adota horário absoluto diário nem conceito de "liberação às 16:00 todo dia". A referência é uma **duração temporal de 4 horas** a partir do disparo da proteção.

As questões normativas resolvidas por este ADR compreendem:
1. Qual é a referência temporal oficial do sistema?
2. Qual é a definição exata de dia operacional e como ela se relaciona com o bloqueio?
3. Como calcular o instante de liberação a partir do acionamento da proteção?
4. Qual o comportamento se a virada do dia operacional (`00:00:00`) ocorrer durante a vigência do bloqueio de 4 horas?
5. Como tratar o retorno às operações após o término das 4 horas para evitar rebloqueio imediato no mesmo tick?

---

## 2. Decisões Tomadas

### 2.1. Referência Temporal Oficial: Horário do Servidor de Negociação (D01)
O EddyTrader adota como **referência temporal oficial e exclusiva o horário do servidor de negociação disponibilizado pela corretora no MetaTrader 5**.

* **Racional:** As ordens, cotações, execuções e extrato contábil são carimbados pela corretora no fuso horário do servidor. O uso do horário do servidor elimina divergências causadas por fuso local, horário de verão ou alterações no relógio da máquina do usuário.
* **Norma:** Tanto o instante do bloqueio ($t_{\text{bloqueio}}$) quanto o instante de liberação ($t_{\text{liberacao}}$) utilizam rigorosamente a mesma referência temporal do servidor da conta.

### 2.2. Definição do Dia Operacional e Independência de Ciclos (D02)
O dia operacional compreende rigorosamente o intervalo entre:
$$\text{Início: } 00:00:00 \quad \text{até} \quad \text{Término: } 23:59:59$$
no horário oficial do servidor de negociação.

* **Independência entre Ciclo Contábil e Ciclo de Bloqueio:** O ciclo diário de cálculo de resultado e o ciclo temporal de bloqueio são **conceitos independentes**.
* A virada de dia às `00:00:00` reinicia a apuração diária de operações realizadas, mas **NÃO interfere nem encurta** uma janela de bloqueio de 4 horas em andamento.

### 2.3. Duração Relativa do Bloqueio: 4 Horas Contínuas (D07 — Atualizada)
Ao ser atingido o limite máximo de perda, o sistema aciona a proteção e impõe bloqueio com duração contínua e relativa de **4 horas**:
$$t_{\text{unlock}} = t_{\text{trigger}} + 4\text{h}$$
onde:
* $t_{\text{trigger}}$: instante em que a violação do limite foi confirmada no relógio do servidor.
* $t_{\text{unlock}}$: instante em que o bloqueio expira no relógio do servidor.

**Exemplos:**
* Limite violado às `10:00`: bloqueado até `14:00`.
* Limite violado às `14:25`: bloqueado até `18:25`.
* Limite violado às `23:30`: bloqueado até `03:30` do dia seguinte.

Para o MVP, a duração aprovada é fixada em **4 horas**, sem introduzir sistemas genéricos de duração arbitrária (princípio YAGNI).

### 2.4. Comportamento na Virada do Dia Operacional (D08 / D10 — Atualizadas)
A passagem da meia-noite (`00:00:00` do servidor) **não cancela nem antecipa** o bloqueio ativo.
* Se um novo dia operacional começar enquanto o bloqueio de 4 horas estiver em curso, o bloqueio continua ativo e soberano até completar integralmente as 4 horas.
* **Exemplo de travessia de dia:**
  * Dia A — `23:30`: limite de perda atingido; posições fechadas, ordens canceladas, sistema entra em `BLOCKED`.
  * Dia B — `00:00`: início do novo dia operacional; cálculo do dia anterior é reiniciado, mas o bloqueio permanece ativo.
  * Dia B — `03:30`: transcorridas as 4 horas completas contínuas; o bloqueio é finalizado.

### 2.5. Liberação ao Término da Janela Temporal (D11 — Atualizada)
Ao completar exatamente a janela temporal definida ($t_{\text{servidor}} \ge t_{\text{unlock}}$):
1. O evento de bloqueio é formalmente encerrado.
2. O sistema remove as restrições operacionais e torna-se elegível a permitir novas negociações.
3. Inicia-se uma nova janela operacional intradiária.

### 2.6. Nova Janela de Proteção após Desbloqueio: Baseline de Reabertura (D09 — Preservada)
O histórico contábil de perdas que causou o bloqueio anterior permanece registrado no terminal e **não é apagado**.

Para evitar um falso rebloqueio instantâneo (*desbloqueio $\to$ leitura da perda histórica do dia $\to$ rebloqueio imediato no mesmo tick*):
* A liberação encerra o evento anterior e **estabelece uma `baseline_de_reabertura`**.
* O sistema passa a monitorar o capital protegendo contra **novas perdas marginais** ocorridas na nova janela a partir do instante da liberação.
* A formulação matemática e equações exatas da baseline pertencem ao escopo da **W03**.

---

## 3. Alternativas Consideradas

* **Horário fixo absoluto diário de desbloqueio (ex: desbloquear diariamente às 16:00):** Descartado e formalmente corrigido após esclarecimento do Product Owner. A regra correta do produto é uma duração contínua de 4 horas contada a partir do momento do bloqueio.
* **Duração customizável configurável pelo operador:** Descartada para o escopo atual (YAGNI). O requisito normativo aprovado para o MVP é a duração fixa de 4 horas.
* **Uso do relógio local da máquina do usuário:** Descartado devido a riscos de divergência de fuso horário, manipulação de relógio e inconsistência com os registros do MT5.
* **Reset ou expiração do bloqueio às 00:00:00:** Descartado. Permitiria que um operador que violou o limite às 23:55 ficasse bloqueado por apenas 5 minutos, anulando a finalidade disciplinar e protetiva da ferramenta.
* **Apagar o histórico contábil após a liberação:** Descartado por violar a integridade financeira e relatórios nativos do MT5.

---

## 4. Consequências

### Positivas
* **Proteção Isonômica e Determinística:** Qualquer violação gera exatamente 4 horas contínuas de bloqueio, independentemente do horário em que aconteça (manhã, tarde ou noite).
* **Imunidade à Virada do Dia:** A transição da meia-noite não afeta a duração do bloqueio.
* **Independência de Relógio Local:** Todo o controle temporal baseia-se exclusivamente no relógio do servidor de negociação.
* **Eliminação de Rebloqueio Falso:** O conceito de nova janela com baseline assegura retomada segura após as 4 horas.

### Pontos de Atenção
* Violações que ocorram no final da noite estenderão o bloqueio pela madrugada adentro no dia seguinte.
* A formalização matemática da baseline pós-liberação requer modelagem rigorosa na etapa W03.

---

## 5. Questões Técnicas Subsequentes (W03 / W04)

1. Formulação matemática e equações da `baseline_de_reabertura` (W03).
2. Mecanismo de persistência/reconstrução determinística do instante do bloqueio ($t_{\text{trigger}}$) e da baseline caso o MT5 seja reiniciado durante as 4 horas de bloqueio (W03/W04).
