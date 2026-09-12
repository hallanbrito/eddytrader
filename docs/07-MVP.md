# 07 — Definição do Produto Mínimo Viável (MVP)

Este documento estabelece o menor conjunto funcional capaz de validar a proposta de valor do **EddyTrader** com máxima segurança operacional, menor esforço de desenvolvimento e estrita conformidade com os princípios do Método C.H.

---

## 1. Objetivo do MVP

O objetivo do MVP do EddyTrader é **comprovar, em ambiente de simulação (Conta Demo) do MetaTrader 5, a capacidade de estancar perdas financeiras no valor exato estipulado pelo operador, encerrando posições, cancelando ordens, bloqueando a conta e liberando-a no horário configurado**.

---

## 2. Escopo Obrigatório do MVP

Os seguintes itens constituem a entrega mínima e inegociável do MVP:

1. **Parâmetros de Entrada Básicos:**
   * Configuração de limite diário de perda em valor monetário (`InpDailyLossLimit`).
   * Configuração de horário de liberação (`InpUnlockTime`).
2. **Cálculo da Perda Intradiária:**
   * Apuração contínua do resultado fechado do dia corrente e do resultado flutuante da conta.
3. **Disparo da Proteção de Risco:**
   * Reconhecimento automático do momento em que a perda acumulada igualar ou superar o limite definido.
4. **Liquidação e Cancelamento de Emergência:**
   * Envio de ordens de fechamento a mercado para 100% das posições abertas na conta.
   * Envio de solicitações de cancelamento para 100% das ordens pendentes na conta.
5. **Mecanismo Básico de Bloqueio:**
   * Ativação do estado de bloqueio e imposição de neutralização para tentativas de operação até o horário agendado (conforme solução validada no Spike Técnico [DQ-001](file:///C:/Projetos/eddytrader/docs/08-RISCOS-E-QUESTOES-ABERTAS.md#dq-001--mecanismo-de-bloqueio-operacional-no-mt5)).
6. **Desbloqueio Automático:**
   * Transição automática para liberado quando o horário do terminal alcançar o horário configurado.
7. **Feedback Visual e Auditoria Local:**
   * Exibição das mensagens oficiais de bloqueio e liberação no gráfico via comentário/HUD nativo (`Comment` / `ChartSetString`).
   * Registro detalhado de cada ação defensiva e evento no log do Diário (`Print`).
8. **Isolamento de Falhas:**
   * Continuidade do fechamento das demais posições caso uma ordem individual seja rejeitada pela corretora.

---

## 3. Escopo Desejável Posteriormente (Pós-MVP)

Funcionalidades que agregam valor, mas que **não são indispensáveis** para a comprovação inicial da proteção:

* **Painel Gráfico Customizado (Dashboard Visual):** Interface gráfica visual elaborada desenhada com objetos gráficos nativos ou Canvas em substituição ao `Comment()`.
* **Alertas Sonoros Nativos:** Execução de sons nativos do MT5 (`PlaySound`) ao atingir o limite ou ao desbloquear.
* **Filtros Opcionais de Escopo:** Parâmetro para restringir o encerramento apenas a determinados Magic Numbers ou símbolos específicos (caso expressamente solicitado pelo operador).
* **Persistência Avançada de Estado em Arquivo:** Salvamento do estado `BLOCKED` em arquivo local seguro (`FileOpen` / `Files`) para tolerar reinicializações inesperadas da máquina durante o bloqueio.

---

## 4. Explicitamente Fora do MVP (Vetado)

Permanece rigorosamente vetado para o MVP tudo o que está fora do escopo do projeto ([02 — Escopo e Limites](file:///C:/Projetos/eddytrader/docs/02-ESCOPO-E-LIMITES.md)), com ênfase em:

* Qualquer lógica de abertura de operações ou geração de sinais;
* Gestão de alvos de lucro diário (*Take Profit* global);
* Trailing stop, Stop Loss de ordens individuais, Martingale ou Grid;
* Uso de bibliotecas externas, DLLs, APIs HTTP ou bancos de dados;
* Integração com Telegram, WhatsApp, Discord ou e-mail;
* Mecanismos de licenciamento comercial, IA ou telemetria.

---

## 5. Critérios Objetivos de Aceite do MVP

O MVP só será considerado concluído e aceito quando os seguintes testes práticos em **Conta Demo** forem executados e validados com 100% de sucesso:

| ID | Cenário de Teste | Condição Inicial | Ação / Evento | Resultado Esperado |
| :--- | :--- | :--- | :--- | :--- |
| **TC-MVP-01** | Disparo de Proteção com Limite Alcançado | Limite configurado: $ 500. Saldo: $ 100.000. Três posições abertas totalizando -$ 510 de flutuante. | Próximo tick de mercado. | O EA detecta perda >= $ 500, fecha as 3 posições imediatamente a mercado, cancela ordens pendentes e entra em `BLOCKED`. |
| **TC-MVP-02** | Cancelamento de Ordens Pendentes | Limite atingido. Existência de 2 ordens *Buy Limit* e 1 ordem *Sell Stop*. | Disparo da proteção. | Todas as 3 ordens pendentes são removidas com sucesso do livro de ordens. |
| **TC-MVP-03** | Resiliência diante de Falha Parcial | 2 posições abertas em símbolos distintos; um dos símbolos está com mercado fechado. | Disparo da proteção. | O EA registra falha no símbolo fechado, encerra com sucesso a posição do símbolo aberto, e não trava nem aborta. |
| **TC-MVP-04** | Manutenção do Bloqueio | Sistema no estado `BLOCKED`. Horário atual: 14:30. Horário de liberação: 16:00. | Tentativa de submissão de nova ordem. | A operação não permanece ativa na conta; aviso visual de bloqueio permanece ativo no gráfico. |
| **TC-MVP-05** | Desbloqueio no Horário Configurado | Sistema no estado `BLOCKED`. Horário de liberação: 16:00. | Relógio atinge 16:00. | O EA atualiza mensagem visual para *"Bloqueio removido. Operações liberadas."*, remove a restrição e retoma `MONITORING`. |
| **TC-MVP-06** | Estabilidade de Recursos | Execução contínua por 4 horas em ambiente de alta frequência de ticks. | Monitoramento nominal e transições de estado. | Consumo estável de CPU (< 1%) e vazamento nulo de memória no MT5. |

---

## 6. Rastreabilidade Documental

* Requisitos Base: [03 — Requisitos](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md)
* Fronteiras de Escopo: [02 — Escopo e Limites](file:///C:/Projetos/eddytrader/docs/02-ESCOPO-E-LIMITES.md)
* Sequência de Construção: [09 — Roadmap](file:///C:/Projetos/eddytrader/docs/09-ROADMAP.md)
