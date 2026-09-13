# EddyTrader — Gerenciador de Perda Diária para MetaTrader 5

O **EddyTrader** é uma ferramenta de controle de risco operacional projetada exclusivamente para a plataforma **MetaTrader 5 (MT5)**, desenvolvida nativamente em **MQL5**.

Sua única responsabilidade é monitorar continuamente o resultado da conta do operador, fechar todas as posições abertas e cancelar ordens pendentes quando um limite monetário diário de perda for atingido, bloqueando novas operações por um período de 4 horas a partir do acionamento no horário oficial do servidor de negociação.

O EddyTrader **não é** uma estratégia de trading: não abre operações, não gera sinais, não define stops individuais e não busca gerenciar metas de lucro.

---

## Estágio Atual do Projeto

* **Fase:** `W05 — Spike Técnico MT5/MQL5: Garantias, Eventos, Liquidação, Bloqueio e Recuperação`
* **Status:** Concluída. Evidências documentais, de compilação e locais consolidadas em [12-SPIKE-TECNICO-MT5.md](file:///C:/Projetos/eddytrader/docs/12-SPIKE-TECNICO-MT5.md) e [ADR 0005](file:///C:/Projetos/eddytrader/docs/adr/0005-garantias-tecnicas-mt5-e-estrategia-de-recuperacao.md) (Status: *Proposed*). Resolução do GAP-005 quanto ao mecanismo técnico (persistência de $\mathbf{D}_{\text{min\_recovery}}$ via Global Variables do Terminal), comprovação documental do fechamento universal por ticket para Netting e Hedging, formalização da neutralização reativa (com latência pendente de medição em Demo) e compilação com 100% de sucesso (0 erros, 0 warnings) de todos os probes em `research/w05/` com o compilador oficial MetaEditor 64 (build 6193).
* **Próxima Fase:** `W06 — Primeiro Expert Advisor Mínimo do EddyTrader`.
* **Aviso Importante:** Os códigos criados na W05 residem estritamente em `research/w05/` e são artefatos experimentais de laboratório (`NOT PRODUCTION CODE`). O Expert Advisor de produção (`src/EddyTrader.mq5`) será implementado apenas na W06 após aprovação formal.

---

## Tecnologia Alvo

* **Linguagem:** MQL5 (MetaQuotes Language 5) puro.
* **Plataforma:** MetaTrader 5 (versão desktop, 64-bit).
* **Ambiente de Execução:** Local e nativo no terminal, sem DLLs, sem banco de dados e sem dependências externas.
* **Compatibilidade:** Contas Demo e Real (modos Netting e Hedging).

---

## Navegação na Documentação Normativa

Toda a base conceitual e contratual do projeto está catalogada na pasta [`docs/`](file:///C:/Projetos/eddytrader/docs):

1. [00 — Manifesto](file:///C:/Projetos/eddytrader/docs/00-MANIFESTO.md): Filosofia, problema fundamental e princípios de proteção.
2. [01 — Visão Geral](file:///C:/Projetos/eddytrader/docs/01-VISAO-GERAL.md): Descrição funcional, público-alvo e fluxo conceitual.
3. [02 — Escopo e Limites](file:///C:/Projetos/eddytrader/docs/02-ESCOPO-E-LIMITES.md): O que está dentro, fora e o que é terminantemente proibido.
4. [03 — Requisitos](file:///C:/Projetos/eddytrader/docs/03-REQUISITOS.md): Requisitos Funcionais (RF) e Não-Funcionais (RNF) rastreáveis.
5. [04 — Casos de Uso](file:///C:/Projetos/eddytrader/docs/04-CASOS-DE-USO.md): Especificação dos fluxos operacionais e exceções.
6. [05 — Regras de Negócio](file:///C:/Projetos/eddytrader/docs/05-REGRAS-DE-NEGOCIO.md): Regras de cálculo, disparo, liquidação e bloqueio.
7. [06 — Arquitetura Conceitual](file:///C:/Projetos/eddytrader/docs/06-ARQUITETURA-CONCEITUAL.md): Módulos conceituais, máquina de estados e questão do bloqueio no MT5.
8. [07 — MVP](file:///C:/Projetos/eddytrader/docs/07-MVP.md): Menor produto viável e critérios objetivos de teste e aceite.
9. [08 — Riscos e Questões Abertas](file:///C:/Projetos/eddytrader/docs/08-RISCOS-E-QUESTOES-ABERTAS.md): Catálogo de ambiguidades (GAPs), decisões (DQs) e riscos (RISKs).
10. [09 — Roadmap](file:///C:/Projetos/eddytrader/docs/09-ROADMAP.md): Planejamento incremental dos Work Packages (W).
11. [10 — Especificação Matemática](file:///C:/Projetos/eddytrader/docs/10-ESPECIFICACAO-MATEMATICA.md): Modelagem determinística da perda, janelas operacionais, baseline e invariantes.
12. [11 — Máquina de Estados](file:///C:/Projetos/eddytrader/docs/11-MAQUINA-DE-ESTADOS.md): Modelagem determinística da FSM, catálogo de estados, guards, transições proibidas e recuperação pós-restart.
13. [12 — Spike Técnico MT5/MQL5](file:///C:/Projetos/eddytrader/docs/12-SPIKE-TECNICO-MT5.md): Relatório exaustivo de garantias técnicas, eventos, liquidação, bloqueio e persistência no MT5.

### Registros de Decisões Arquiteturais (ADRs)
* [ADR 0001 — Regras Temporais e Janelas de Proteção](file:///C:/Projetos/eddytrader/docs/adr/0001-regras-temporais-e-janelas-de-protecao.md)
* [ADR 0002 — Composição da Perda Operacional](file:///C:/Projetos/eddytrader/docs/adr/0002-composicao-da-perda-operacional.md)
* [ADR 0003 — Modelo Matemático de Janelas e Baseline](file:///C:/Projetos/eddytrader/docs/adr/0003-modelo-matematico-de-janelas-e-baseline.md)
* [ADR 0004 — Máquina de Estados e Recuperação](file:///C:/Projetos/eddytrader/docs/adr/0004-maquina-de-estados-e-recuperacao.md)
* [ADR 0005 — Garantias Técnicas do MT5 e Estratégia de Recuperação](file:///C:/Projetos/eddytrader/docs/adr/0005-garantias-tecnicas-mt5-e-estrategia-de-recuperacao.md)

---

## Instruções para Agentes Autônomos

Consulte obrigatoriamente o arquivo [AGENTS.md](file:///C:/Projetos/eddytrader/AGENTS.md) antes de propor qualquer modificação ou atuar neste repositório.
