# 07 — Definição do Produto Mínimo Viável (MVP)

Este documento estabelece o menor conjunto funcional capaz de validar a proposta de valor do **EddyTrader**, incorporando as decisões normativas e regras de proteção formalizadas na **W02** (incluindo o esclarecimento de requisito sobre o bloqueio contínuo de 4 horas a partir do acionamento).

---

## 1. Objetivo do MVP

O objetivo do MVP do EddyTrader é **comprovar em ambiente de simulação (Conta Demo) do MetaTrader 5 a capacidade de estancar perdas financeiras na conta inteira conforme o limite configurado pelo operador, liquidando posições, cancelando ordens, bloqueando a conta por 4 horas contínuas sob as regras de tempo do servidor e liberando-a para novas janelas operacionais sem instabilidade**.

---

## 2. Escopo Obrigatório do MVP

Constituem o escopo obrigatório e inegociável do MVP:

1. **Parâmetros de Entrada e Regras Temporais Básicas:**
   * Limite de perda diária em valor monetário positivo (`InpDailyLossLimit`).
   * Duração de bloqueio aprovada de **4 horas contínuas** contadas a partir do momento em que o limite for atingido no relógio do servidor ($t_{\text{unlock}} = t_{\text{trigger}} + 4\text{h}$), com reabertura efetiva em $t_{\text{reopen}} \ge t_{\text{unlock}}$. *(Corrigido: substitui a interpretação preliminar de horário fixo absoluto diário)*.
2. **Cálculo da Perda Operacional Líquida:**
   * Apuração contínua do resultado realizado do dia (`00:00:00` às `23:59:59` do servidor) somado ao flutuante atual.
   * Inclusão obrigatória de comissões e taxas de swap.
   * Exclusão absoluta de depósitos, saques e créditos administrativos.
   * Posições abertas antigas continuam contribuindo com seu flutuante no novo dia.
3. **Escopo Global da Conta e Instância Única:**
   * Monitoramento e intervenção sobre 100% das posições e ordens pendentes da conta (todos os ativos, manuais ou robôs).
   * Operação sob premissa de instância única por conta.
4. **Liquidação e Cancelamento Compulsórios:**
   * Ordens a mercado para fechamento de 100% das posições abertas na conta.
   * Solicitações de remoção para 100% das ordens pendentes na conta.
   * Continuidade do processamento das demais ordens em caso de falha individual de execução.
5. **Regras Temporais de Bloqueio e Janelas:**
   * Duração contínua de 4 horas: ao ser acionada a proteção, o bloqueio vigora ininterruptamente pelo período $[t_{\text{trigger}}, t_{\text{unlock}})$, onde $t_{\text{unlock}} = t_{\text{trigger}} + 4\text{h}$.
   * Independência de virada de dia: se a virada de `00:00:00` ocorrer durante o bloqueio, o bloqueio permanece soberano e ativo no novo dia operacional até completar as 4 horas.
   * Desbloqueio e nova janela: transcorrido o período mínimo de 4 horas ($t \ge t_{\text{unlock}}$) e satisfeitas as condições operacionais de segurança, a liberação efetiva ocorre em $t_{\text{reopen}} \ge t_{\text{unlock}}$, encerrando o evento e estabelecendo a baseline $B_n = D(t_{\text{reopen}, n})$ para a nova janela operacional ($W_n = D - B_n$), evitando falso rebloqueio imediato conforme [10-ESPECIFICACAO-MATEMATICA.md](file:///C:/Projetos/eddytrader/docs/10-ESPECIFICACAO-MATEMATICA.md) e [ADR 0003](file:///C:/Projetos/eddytrader/docs/adr/0003-modelo-matematico-de-janelas-e-baseline.md).
6. **Reconstrução Determinística após Reinicialização:**
   * O EA prioriza a inferência de seu estado a partir do histórico nativo de transações e posições do MT5 ao reiniciar.
7. **Feedback Visual Simples e Log Nativo:**
   * Exibição das mensagens oficiais no gráfico informando relógio do servidor, limite, perdas, instante do bloqueio e previsão de liberação ($t_{\text{bloqueio}} + 4\text{h}$).
   * Auditoria de todos os eventos no Diário (`Print`).
8. **Homologação Estrita em Conta Demo:**
   * Validação mandatória em Conta Demo antes de qualquer liberação para Conta Real.

---

## 3. Escopo Desejável Posteriormente (Pós-MVP)

* Duração customizável de bloqueio configurável pelo usuário (caso formalmente aprovada no futuro).
* Painel visual gráfico avançado desenhado em Canvas.
* Alertas sonoros nativos customizáveis.
* Filtros opcionais por Magic Number ou símbolo específico (caso expressamente solicitado).
* Armazenamento redundante em arquivo local (`MQL5/Files`) caso a inferência pura de baseline após restart apresente limitações na W04.

---

## 4. Explicitamente Fora do MVP (Vetado)

Permanece categoricamente vetado:
* Estratégias de entrada, abertura de operações ou geração de sinais;
* Gestão de metas de lucro diário (*Take Profit* global);
* Trailing stop, Stop Loss automático por ordem, Martingale ou Grid;
* DLLs, banco de dados, APIs Web, Python, Docker, servidores locais ou externos;
* Mensageiros externos (Telegram, Discord, WhatsApp, e-mail);
* Mecanismos de DRM ou cobrança comercial.

---

## 5. Critérios Objetivos de Aceite do MVP

O MVP só será considerado concluído e aceito após 100% de aprovação nos testes em **Conta Demo**:

| ID | Cenário de Teste | Condição Inicial | Evento / Ação | Resultado Esperado |
| :--- | :--- | :--- | :--- | :--- |
| **TC-MVP-01** | Disparo com Limite Violado | Limite: $ 500. Realizado: -$ 300. Flutuante: -$ 210. | Próximo tick / timer. | Perda apurada (-$ 510) $\le$ -$ 500. Disparo da proteção, fechamento das posições a mercado, cancelamento de pendentes e transição para `BLOCKED`. |
| **TC-MVP-02** | Exclusão de Saques e Depósitos | Limite: $ 500. Realizado: -$ 200. Saque de $ 1.000 realizado na conta. | Processamento do histórico. | O resultado operacional permanece em -$ 200 (não vira -$ 1.200); o sistema não dispara indevidamente. |
| **TC-MVP-03A** | Bloqueio Matutino (Cenário 1) | Limite violado às 10:00 do servidor. Duração: 4 horas. | Disparo da proteção às 10:00. | Sistema entra em `BLOCKED` e permanece bloqueado até as **14:00** do mesmo dia ($10:00 + 4\text{h}$). |
| **TC-MVP-03B** | Bloqueio Vespertino (Cenário 2) | Limite violado às 14:25 do servidor. Duração: 4 horas. | Disparo da proteção às 14:25. | Sistema entra em `BLOCKED` e permanece bloqueado até as **18:25** do mesmo dia ($14:25 + 4\text{h}$). |
| **TC-MVP-04** | Bloqueio Noturno e Virada de Dia (Cenários 3 e 4) | Limite violado às 23:30 do servidor. Duração: 4 horas. | Passagem das `00:00:00` (início do novo dia operacional). | O bloqueio **permanece ativo** ininterruptamente durante e após a meia-noite até completar 4 horas, com liberação prevista e executada às **03:30** do dia seguinte. |
| **TC-MVP-05** | Desbloqueio e Nova Janela Operacional | Bloqueado com perda de -$ 510. Transcorridas as 4 horas de bloqueio ($t \ge t_{\text{unlock}}$). | Relógio do servidor alcança $t_{\text{unlock}}$ e condições de segurança satisfeitas ($t_{\text{reopen}} \ge t_{\text{unlock}}$). | Bloqueio removido; mensagens informam liberação; baseline $B_n = D(t_{\text{reopen}, n})$ estabelecida; sistema não rebloqueia imediatamente no mesmo tick. |
| **TC-MVP-06** | Flutuante de Posição Antiga na Virada do Dia | Início do dia (`00:00:00`). Posição antiga aberta com flutuante de -$ 600. Limite: $ 500. | Primeiro tick do novo dia. | O flutuante negativo viola o limite do novo dia; a proteção é acionada imediatamente. |
| **TC-MVP-07** | Resiliência a Falha de Fechamento Individual | 2 posições abertas; uma em ativo com mercado fechado. | Disparo da proteção. | Erro registrado em log; posição viável encerrada; sistema permanece estritamente em `LIQUIDATING` persistindo nas retentativas de encerramento; avança para `BLOCKED` somente após neutralização de 100% da exposição residual; veta retorno a `MONITORING`. |
| **TC-MVP-08** | Reconstrução de Estado após Reinicialização | Sistema em `BLOCKED` acionado às 14:25 (liberação para 18:25). Terminal fechado e reaberto às 15:30. | Execução do `OnInit()`. | O EA lê o histórico, detecta bloqueio ativo vigente ($15:30 < 18:25$) e restaura o estado `BLOCKED` até as 18:25 sem intervenção manual. |

---

## 6. Rastreabilidade Documental

* Implementação do MVP (W06): [13 — Implementação do MVP (W06)](file:///C:/Projetos/eddytrader/docs/13-IMPLEMENTACAO-MVP-W06.md)
* Código do Expert Advisor: [`src/EddyTrader.mq5`](file:///C:/Projetos/eddytrader/src/EddyTrader.mq5)
* Requisitos Base: [03 — Requisitos](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md)
* Regras Normativas: [05 — Regras de Negócio](file:///C:/Projetos/eddytrader/docs/05-REGRAS-DE-NEGOCIO.md)
* Especificação Matemática: [10 — Especificação Matemática](file:///C:/Projetos/eddytrader/docs/10-ESPECIFICACAO-MATEMATICA.md)
* Máquina de Estados Finita: [11 — Máquina de Estados](file:///C:/Projetos/eddytrader/docs/11-MAQUINA-DE-ESTADOS.md)
* Spike Técnico MT5: [12 — Spike Técnico MT5](file:///C:/Projetos/eddytrader/docs/12-SPIKE-TECNICO-MT5.md)
* Decisões Arquiteturais: [ADR 0001](file:///C:/Projetos/eddytrader/docs/adr/0001-regras-temporais-e-janelas-de-protecao.md), [ADR 0002](file:///C:/Projetos/eddytrader/docs/adr/0002-composicao-da-perda-operacional.md), [ADR 0003](file:///C:/Projetos/eddytrader/docs/adr/0003-modelo-matematico-de-janelas-e-baseline.md), [ADR 0004](file:///C:/Projetos/eddytrader/docs/adr/0004-maquina-de-estados-e-recuperacao.md) e [ADR 0005](file:///C:/Projetos/eddytrader/docs/adr/0005-garantias-tecnicas-mt5-e-estrategia-de-recuperacao.md)
* Próximos Passos: [09 — Roadmap](file:///C:/Projetos/eddytrader/docs/09-ROADMAP.md)
