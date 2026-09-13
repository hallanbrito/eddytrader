# EddyTrader — Gerenciador de Perda Diária para MetaTrader 5

O **EddyTrader** é uma ferramenta de controle de risco operacional projetada exclusivamente para a plataforma **MetaTrader 5 (MT5)**, desenvolvida nativamente em **MQL5**.

Sua única responsabilidade é monitorar continuamente o resultado da conta do operador, fechar todas as posições abertas e cancelar ordens pendentes quando um limite monetário diário de perda for atingido, bloqueando novas operações por um período de 4 horas a partir do acionamento no horário oficial do servidor de negociação.

O EddyTrader **não é** uma estratégia de trading: não abre operações, não gera sinais, não define stops individuais e não busca gerenciar metas de lucro.

---

## Estágio Atual do Projeto

* **Fase:** `W08 — Hardening, Operação e Release Candidate do EddyTrader`
* **Status:** Release Candidate 1 Aprovado com Ressalva Externa (`1.0.0-rc1`). Código endurecido, defensivo e determinístico (MQL5 puro, 0 dependências externas). Build oficial automatizado via PowerShell (`scripts/build.ps1`) com 0 erros e 0 warnings em todos os 6 artefatos compiláveis sob MetaEditor build 6193. Suíte de regressão formal (`test_fsm_w06.mq5`) 100% verde (28/28 asserções aprovadas). Homologação em conta Demo concluída em W07 (36/36 asserções aprovadas em 15 cenários DEMO-01 a 15). O gate final externo para liberação da versão de produção v1.0.0 permanece formalmente condicionado à execução do teste de neutralização reativa ponta a ponta `LIVE-01` exclusivamente em conta Demo com pregão aberto (DEMO ONLY) e correspondente aceitação da `ADR 0005`.
* **Versão:** `1.0.0-rc1` (Release Candidate 1)
* **Documentação Operacional e de Release:**
  * [15 — Guia Operacional do EddyTrader](docs/15-GUIA-OPERACIONAL.md)
  * [16 — Checklist de Release Candidate](docs/16-RELEASE-CHECKLIST.md)
  * [17 — Release Notes 1.0.0-rc1](docs/17-RELEASE-NOTES-1.0.0-rc1.md)
  * [14 — Homologação Operacional em Conta Demo (W07)](docs/14-HOMOLOGACAO-W07.md)
  * [13 — Implementação do MVP (W06)](docs/13-IMPLEMENTACAO-MVP-W06.md)

---

## Tecnologia Alvo

* **Linguagem:** MQL5 (MetaQuotes Language 5) puro.
* **Plataforma:** MetaTrader 5 (versão desktop, 64-bit).
* **Ambiente de Execução:** Local e nativo no terminal, sem DLLs, sem banco de dados e sem dependências externas.
* **Compatibilidade:** Contas Demo e Real (modos Netting e Hedging).

---

## Navegação na Documentação Normativa

Toda a base conceitual e contratual do projeto está catalogada na pasta [`docs/`](docs):

1. [00 — Manifesto](docs/00-MANIFESTO.md): Filosofia, problema fundamental e princípios de proteção.
2. [01 — Visão Geral](docs/01-VISAO-GERAL.md): Descrição funcional, público-alvo e fluxo conceitual.
3. [02 — Escopo e Limites](docs/02-ESCOPO-E-LIMITES.md): O que está dentro, fora e o que é terminantemente proibido.
4. [03 — Requisitos](docs/03-REQUISITOS.md): Requisitos Funcionais (RF) e Não-Funcionais (RNF) rastreáveis.
5. [04 — Casos de Uso](docs/04-CASOS-DE-USO.md): Especificação dos fluxos operacionais e exceções.
6. [05 — Regras de Negócio](docs/05-REGRAS-DE-NEGOCIO.md): Regras de cálculo, disparo, liquidação e bloqueio.
7. [06 — Arquitetura Conceitual](docs/06-ARQUITETURA-CONCEITUAL.md): Módulos conceituais, máquina de estados e questão do bloqueio no MT5.
8. [07 — MVP](docs/07-MVP.md): Menor produto viável e critérios objetivos de teste e aceite.
9. [08 — Riscos e Questões Abertas](docs/08-RISCOS-E-QUESTOES-ABERTAS.md): Catálogo de ambiguidades (GAPs), decisões (DQs) e riscos (RISKs).
10. [09 — Roadmap](docs/09-ROADMAP.md): Planejamento incremental dos Work Packages (W).
11. [10 — Especificação Matemática](docs/10-ESPECIFICACAO-MATEMATICA.md): Modelagem determinística da perda, janelas operacionais, baseline e invariantes.
12. [11 — Máquina de Estados](docs/11-MAQUINA-DE-ESTADOS.md): Modelagem determinística da FSM, catálogo de estados, guards, transições proibidas e recuperação pós-restart.
13. [12 — Spike Técnico MT5/MQL5](docs/12-SPIKE-TECNICO-MT5.md): Relatório exaustivo de garantias técnicas, eventos, liquidação, bloqueio e persistência no MT5.
14. [13 — Implementação do MVP (W06)](docs/13-IMPLEMENTACAO-MVP-W06.md): Arquitetura, estrutura de dados, garantias do EA e validação dos 20 cenários de teste na plataforma MT5.
15. [14 — Homologação Operacional em Conta Demo (W07)](docs/14-HOMOLOGACAO-W07.md): Homologação empírica em conta Demo, baterias DEMO-01 a DEMO-15 e regressão unificada.
16. [15 — Guia Operacional](docs/15-GUIA-OPERACIONAL.md): Manual de instalação, configuração, operação, observabilidade HUD e plano de contingência.
17. [16 — Checklist de Release Candidate](docs/16-RELEASE-CHECKLIST.md): Checklist rigoroso de qualidade, segurança defensiva, gates e conformidade normativa.
18. [17 — Release Notes 1.0.0-rc1](docs/17-RELEASE-NOTES-1.0.0-rc1.md): Notas oficiais da versão Release Candidate 1.0.0-rc1.

### Registros de Decisões Arquiteturais (ADRs)
* [ADR 0001 — Regras Temporais e Janelas de Proteção](file:///C:/Projetos/eddytrader/docs/adr/0001-regras-temporais-e-janelas-de-protecao.md)
* [ADR 0002 — Composição da Perda Operacional](file:///C:/Projetos/eddytrader/docs/adr/0002-composicao-da-perda-operacional.md)
* [ADR 0003 — Modelo Matemático de Janelas e Baseline](file:///C:/Projetos/eddytrader/docs/adr/0003-modelo-matematico-de-janelas-e-baseline.md)
* [ADR 0004 — Máquina de Estados e Recuperação](file:///C:/Projetos/eddytrader/docs/adr/0004-maquina-de-estados-e-recuperacao.md)
* [ADR 0005 — Garantias Técnicas do MT5 e Estratégia de Recuperação](file:///C:/Projetos/eddytrader/docs/adr/0005-garantias-tecnicas-mt5-e-estrategia-de-recuperacao.md)

---

## Instruções para Agentes Autônomos

Consulte obrigatoriamente o arquivo [AGENTS.md](file:///C:/Projetos/eddytrader/AGENTS.md) antes de propor qualquer modificação ou atuar neste repositório.
